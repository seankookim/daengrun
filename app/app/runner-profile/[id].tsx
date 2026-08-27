import { router, useFocusEffect, useLocalSearchParams } from 'expo-router';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Alert, Animated, Dimensions, Image, Pressable, ScrollView, StyleSheet, Text, TextStyle, View } from 'react-native';
import { Avatar, Icon, Row } from '../../src/components/ui';
import { checkSlot, CoursePatch, deleteGear, NOT_FOUND, deleteRunnerPhoto, fetchGear, fetchProfileIdentity, fetchProfilePosts, fetchRunnerCourseHistory, fetchRunnerProfile, fetchRunnerReviewCount, GEAR_KINDS, GEAR_META, GearItem, GearKind, ProfileIdentity, ProfilePost, RunnerPublicProfile, uploadRunnerPhoto, upsertGear } from '../../src/lib/api';
import { PatchBadge } from '../../src/components/patch';
import { StatusBarCover } from '../../src/components/status-bar-cover';
import { MediaImage } from '../../src/lib/media';
import { haptic } from '../../src/lib/haptics';
import { goBackOrHome } from '../../src/lib/nav';
import { useNumFont } from '../../src/lib/fonts';
import { supabase } from '../../src/lib/supabase';
import { draft, session } from '../../src/store';
import { colors, paper } from '../../src/theme';
import { kstCal, kstInstant, kstKey } from '../../src/lib/kst';
import { expectedDurationMs } from '../../src/lib/lateness';

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
  // 확인 바 스프링 등장 — 선택이라는 상태 변화를 모션으로
  const barY = useRef(new Animated.Value(90)).current;
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
    fetchProfileIdentity(id).then((w) => { setWho(w); setErr(null); }).catch((e) => setErr(e?.message === NOT_FOUND
      // 0행 = 이 사람의 프로필이 나에게 공개돼 있지 않다 (RLS: 본인·승인 러너·툼스톤만).
      // '없는 사람'이라고 말하지 않는다 — 우리가 아는 것은 '못 본다'까지다.
      ? '이 프로필은 공개되어 있지 않아요'
      : '프로필을 불러오지 못했어요'));
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
  const daySlots = useMemo(() => {
    if (!p) return [] as { key: string; label: string; start: Date }[];
    const day = days[dayIdx];
    const wd = day.cal.wd; // KST 요일 — availability.weekday가 KST 고정이다
    const rules = p.availability.filter((r) => r.weekday === wd);
    const out: { key: string; label: string; start: Date }[] = [];
    const minStart = Date.now() + 2 * 3600_000;
    rules.forEach((r) => {
      // ⚠ [codex 2026-08-21] 여기만 60분 고정이었다 — reschedule 에서 고친 드리프트가 세 번째
      // 예약 입구에 그대로 남아 있었다. 서버 수락 검증은 km×8+25 를 본다.
      for (let m = r.startMin; m + durMin <= r.endMin; m += 60) {
        const start = kstInstant(day.cal, Math.floor(m / 60), m % 60);
        if (start.getTime() < minStart) continue;
        out.push({ key: start.toISOString(), label: fmtMin(m), start });
      }
    });
    return out;
  }, [p, dayIdx, days, durMin]);

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
    const c = kstCal(sl.start.getTime());
    draft.timeLabel = `${c.m + 1}월 ${c.d}일 (${DAY[c.wd]}) ${sl.label}`;
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
      Alert.alert('업로드 실패', (e as Error).message);
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
      Alert.alert('장비 등록 실패', (e as Error).message);
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
          } catch (e) { Alert.alert('삭제 실패', (e as Error).message); }
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
          } catch (e) { Alert.alert('삭제 실패', (e as Error).message); }
        },
      },
    ]);
  };

  // 갤러리 탭이 존재하는 조건 = 그 소스가 존재하는 조건. 없는 탭은 안 그린다 (죽은 버튼 금지).
  const hasGallery = !!p && (p.photos.length > 0 || canEdit);
  const activeTab = hasGallery ? tab : 'posts'; // 탭이 사라져도 상태가 유령 탭을 가리키지 않게
  const metaLine = [who?.district, p?.avgRating != null ? `★ ${p.avgRating}` : null].filter(Boolean).join(' · ');

  return (
    <View style={{ flex: 1, backgroundColor: paper.canvas }}>
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingBottom: selected ? 140 : 40 }}>
        {/* ---------- ① 아이디 바 — 인스타의 상단은 이름이 아니라 **계정 아이디**다 ---------- */}
        <Row style={s.topBar}>
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
        {!err && !who && <View style={s.emptyBox}><Text style={s.emptyText}>불러오는 중...</Text></View>}

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
                <Pressable
                  onPress={() => router.push('/profile/edit')}
                  style={({ pressed }) => [s.editBtn, pressed && { backgroundColor: paper.wash }]}
                  accessibilityRole="button"
                >
                  <Text style={s.editBtnTxt}>프로필 편집</Text>
                </Pressable>
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
                    accessibilityRole="button"
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
                {posts === 'loading' && <View style={s.gridState}><Text style={s.emptyText}>게시물을 불러오는 중...</Text></View>}
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
                    <Pressable key={url} onLongPress={canEdit ? () => removePhoto(url) : undefined}>
                      <Image source={{ uri: url }} style={[s.tile, { backgroundColor: '#ECEAE2' }]} />
                    </Pressable>
                  ))}
                  {canEdit && (
                    <Pressable onPress={addPhoto} disabled={uploadingPhoto} style={[s.tile, s.addTile]}>
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
                <Stat nf={nf} value={p.respondRate != null ? `${p.respondRate}%` : '신규'} label="응답률" />
              </Row>
            </View>

            {/* ---------- 러닝 장비 로드아웃 (0019) — 슬롯제, 사진이 곧 인증 ---------- */}
            {(gear.length > 0 || canEdit) && (
              <View style={s.section}>
                <Row style={{ justifyContent: 'space-between' }}>
                  <Text style={s.sectionTitle}>러닝 장비</Text>
                  <Text style={{ fontSize: 14, color: colors.dim }}>사진으로 인증된 장비예요</Text>
                </Row>
                <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: 8, paddingTop: 2 }}>
                  {GEAR_KINDS.map((kind) => {
                    const item = gear.find((g) => g.kind === kind);
                    if (!item && !canEdit) return null; // 없는 데이터는 그리지 않는다
                    const meta = GEAR_META[kind];
                    return (
                      <Pressable
                        key={kind}
                        disabled={!canEdit || gearBusy !== null}
                        onPress={() => onGearSlot(kind)}
                        style={[s.gearSlot, !item && s.gearSlotEmpty]}
                      >
                        {item?.photoUrl ? (
                          <Image source={{ uri: item.photoUrl }} style={s.gearPhoto} />
                        ) : (
                          <View style={[s.gearPhoto, { alignItems: 'center', justifyContent: 'center', backgroundColor: '#f1eee3' }]}>
                            {gearBusy === kind || !item
                              ? <Text style={{ fontSize: 27 }}>{gearBusy === kind ? '…' : '＋'}</Text>
                              : <Icon name={meta.icon} glyph="●" size={24} color="#8a8672" />}
                          </View>
                        )}
                        <Text style={{ fontSize: 14.5, fontWeight: '800', color: item ? paper.ink : colors.dim, marginTop: 6 }}>
                          {meta.name}
                        </Text>
                        {item?.verified ? (
                          <View style={s.gearBadge}><Text style={{ fontSize: 14, fontWeight: '900', color: '#3d5a2b' }}>✓ 인증</Text></View>
                        ) : (
                          <Text style={{ fontSize: 14, color: colors.dim, marginTop: 3 }}>{meta.hint}</Text>
                        )}
                      </Pressable>
                    );
                  })}
                </ScrollView>
                {canEdit && (
                  <Text style={{ fontSize: 14, color: colors.dim, marginTop: 8 }}>
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
                  <Text style={{ fontSize: 14, color: colors.dim }}>완주 기록으로 자동 집계돼요</Text>
                </Row>
                <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: 12, paddingTop: 2 }}>
                  {courseHist.map((c) => (
                    <Pressable key={c.routeId} onPress={() => router.push(`/course/${c.routeId}`)} style={{ alignItems: 'center', width: 76 }}>
                      <PatchBadge km={c.km} name={c.name} grade={c.grade} size={64} />
                      <Text numberOfLines={1} style={{ fontSize: 14, fontWeight: '800', color: paper.ink, marginTop: 6 }}>{c.name}</Text>
                      <Text style={{ fontSize: 14, color: colors.dim, marginTop: 1 }}>×{c.count} 완주</Text>
                    </Pressable>
                  ))}
                </ScrollView>
              </View>
            )}

            {/* ---------- 가능 시간 + 슬롯 예약 ---------- */}
            <View style={s.section}>
              <Text style={s.sectionTitle}>러닝 가능 시간</Text>
              {avail.length === 0 ? (
                <Text style={{ fontSize: 14.5, color: colors.dim }}>가용 시간 미설정 — 오픈 매칭으로만 예약할 수 있어요</Text>
              ) : !canBook ? (
                <>
                  {avail.map((line) => (
                    <Text key={line} style={{ fontSize: 15, color: '#3d453d', lineHeight: 24 }}>{line}</Text>
                  ))}
                  <Text style={{ fontSize: 14, color: colors.dim, marginTop: 8 }}>
                    보호자에게는 여기가 시간대 선택 그리드로 보여요 — 예약은 보호자 모드에서
                  </Text>
                </>
              ) : (
                <>
                  <Text style={{ fontSize: 14, color: colors.dim, marginBottom: 10 }}>{avail.join(' · ')}</Text>
                  <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: 8 }}>
                    {days.map((d, i) => (
                      <Pressable key={kstKey(d.cal)} onPress={() => { setDayIdx(i); setSelected(null); }} style={[s.dayChip, dayIdx === i && { backgroundColor: paper.ink }]}>
                        <Text style={{ fontSize: 14, color: dayIdx === i ? '#b8c4ae' : colors.dim }}>{d.w}</Text>
                        <Text style={{ fontSize: 17, fontWeight: '900', color: dayIdx === i ? '#fff' : paper.ink }}>{d.d}</Text>
                        {d.label && <Text style={{ fontSize: 9, fontWeight: '700', color: dayIdx === i ? colors.volt : '#5a7a3c' }}>{d.label}</Text>}
                      </Pressable>
                    ))}
                  </ScrollView>
                  {daySlots.length === 0 ? (
                    <Text style={{ fontSize: 14, color: colors.dim, marginTop: 12 }}>이 날은 가능한 시간이 없어요</Text>
                  ) : (
                    <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 8, marginTop: 12 }}>
                      {daySlots.map((sl) => {
                        const ok = slotOk[sl.key];
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
                            style={[
                              s.slotChip,
                              ok === false && { opacity: 0.35 },
                              ok === null && { opacity: 0.6 },
                              sel && { backgroundColor: paper.ink, borderColor: paper.ink },
                            ]}
                          >
                            <Text style={{ fontSize: 15, fontWeight: '800', color: sel ? '#fff' : paper.ink }}>{sl.label}</Text>
                            <Text style={{ fontSize: 14, marginTop: 1, color: sel ? colors.volt : ok === false ? '#d84a2f' : ok === 'error' ? paper.critical : ok === null ? colors.dim : '#5a7a3c' }}>
                              {sel ? '선택됨 ✓' : ok === false ? '마감' : ok === 'error' ? '확인 실패 · 재시도' : ok === null ? '확인 중' : '가능'}
                            </Text>
                          </Pressable>
                        );
                      })}
                    </View>
                  )}
                  <Text style={{ fontSize: 14, color: colors.dim, marginTop: 10 }}>
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
                <Text style={{ fontSize: 14.5, color: colors.dim }}>아직 후기가 없어요 — 첫 러닝의 주인공이 되어보세요</Text>
              )}
              {p.reviews.map((v, i) => (
                <View key={i} style={[s.reviewRow, i > 0 && { borderTopWidth: 1, borderTopColor: '#f0eee3' }]}>
                  <Row style={{ justifyContent: 'space-between' }}>
                    <Text style={{ fontSize: 14, fontWeight: '800', color: '#5a7a3c' }}>
                      {v.rating != null ? '★'.repeat(v.rating) : '후기'}
                    </Text>
                    <Text style={{ fontSize: 14, color: colors.dim }}>{v.when}</Text>
                  </Row>
                  {v.note && <Text style={{ fontSize: 14.5, color: '#3d453d', marginTop: 4, lineHeight: 20.5 }}>{v.note}</Text>}
                  {v.tags.length > 0 && (
                    <Row style={{ gap: 5, marginTop: 5, flexWrap: 'wrap' }}>
                      {v.tags.map((t) => (
                        <Text key={t} style={{ fontSize: 14, color: colors.dim }}>#{t}</Text>
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
                    style={s.cta}
                    onPress={() => {
                      draft.preferredRunnerId = p.profileId;
                      draft.preferredRunnerName = p.name;
                      router.push('/owner/request');
                    }}
                  >
                    <Text style={{ fontSize: 17, fontWeight: '900', color: '#fff' }}>{p.name} 러너와 예약하기</Text>
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
                  <Text style={{ fontSize: 14, lineHeight: 19, color: colors.dim, textAlign: 'center', marginTop: 10 }}>
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
      </ScrollView>

      {/* 스크롤 화면이므로 ScrollView 뒤에 — 그래야 스트립이 콘텐츠 위에 그려진다 (status-bar-cover.tsx 배치법) */}
      <StatusBarCover />

      {/* [2026-08-27] 여기 있던 프로필 편집 모달은 `/profile/edit`로 접혔다 (Sean의 인스타 편집기
          모델: 행 목록, 아바타 행 없음). 같은 필드를 두 화면에서 고칠 수 있으면 규칙도 두 벌이 된다. */}

      {/* ---------- 슬롯 확인 바 — 결제 바와 같은 확인 패턴 ---------- */}
      {selected && p && canBook && (
        <Animated.View style={[s.confirmBar, { transform: [{ translateY: barY }] }]}>
          <View style={{ flex: 1 }}>
            <Text style={{ fontSize: 15, fontWeight: '900', color: '#fff' }}>
              {selected.start.getMonth() + 1}월 {selected.start.getDate()}일 ({DAY[selected.start.getDay()]}) {selected.label}
            </Text>
            <Text style={{ fontSize: 14, color: '#b8c4ae', marginTop: 2 }}>
              {p.name} 러너 · 코스·옵션 선택으로 이어져요
            </Text>
          </View>
          <Pressable onPress={() => confirmSlot(selected)} style={s.confirmBtn}>
            <Text style={{ fontSize: 16, fontWeight: '900', color: '#fff' }}>이 시간으로 ›</Text>
          </Pressable>
        </Animated.View>
      )}
    </View>
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
  // ── 페이퍼 월드: 흰 캔버스 · 솔리드 코랄 헤어라인 · 샤프 코너 (DESIGN.md §2/§4) ──
  topBar: { justifyContent: 'space-between', paddingHorizontal: 12, paddingTop: 56, paddingBottom: 12 },
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
  // 세컨더리 버튼 (버튼 매트릭스): wash 면 + 코랄 보더 + actionInk 라벨. 프라이머리는 예약 CTA다.
  editBtn: { marginTop: 14, paddingVertical: 12, alignItems: 'center', borderWidth: 1, borderColor: paper.line, backgroundColor: paper.canvas },
  editBtnTxt: { fontSize: 16, fontWeight: '800', color: paper.actionInk },
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
  sectionTitle: { fontSize: 15.5, fontWeight: '900', color: paper.ink, marginBottom: 8 },
  statDiv: { width: 1, alignSelf: 'stretch', backgroundColor: paper.line },
  specChip: { backgroundColor: '#eef4e0', borderRadius: 99, paddingVertical: 4, paddingHorizontal: 10 },
  specChipTxt: { fontSize: 15, lineHeight: 19, fontWeight: '700', color: '#3d5a2b' },
  // 장비 로드아웃 슬롯 (0019)
  gearSlot: { width: 104, backgroundColor: '#fff', borderRadius: 14, borderWidth: 1, borderColor: '#DCD6C4', padding: 8, alignItems: 'center' },
  gearSlotEmpty: { borderStyle: 'dashed', backgroundColor: '#faf8f1' },
  gearPhoto: { width: 88, height: 66, borderRadius: 10, backgroundColor: '#DCD6C4' },
  gearBadge: { backgroundColor: '#DDF0A6', borderRadius: 99, paddingVertical: 2, paddingHorizontal: 8, marginTop: 3 },
  reviewRow: { paddingVertical: 10 },
  dayChip: { width: 46, borderRadius: 13, backgroundColor: '#f4f2ea', alignItems: 'center', paddingVertical: 8, gap: 1 },
  slotChip: { width: '22.5%', backgroundColor: '#f7f9f0', borderRadius: 12, borderWidth: 1, borderColor: '#dde8c4', alignItems: 'center', paddingVertical: 9 },
  addTile: { backgroundColor: paper.wash, alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: paper.line },
  // 프라이머리 액션 = paper.action (흰 라벨 4.84:1). 볼트 라임 은퇴 — 이 화면은 페이퍼 월드다.
  cta: { backgroundColor: paper.action, alignItems: 'center', paddingVertical: 15, marginTop: 16 },
  // [2026-08-20 · T4] ghostCta 삭제 — 그 스타일을 쓰던 유일한 소자가 '채팅 문의' 고스트 버튼이었고,
  // 그 버튼은 은퇴했다 (위 CTA 블록의 주석). 주인 없는 스타일을 남겨두면 다음 사람은 화면 어딘가에
  // 세컨더리 버튼이 있다고 읽는다. editChip/editSheet 계열도 같은 이유로 삭제됐다 — 편집기는
  // 이제 `/profile/edit`이고, 이 파일에는 편집 면이 하나도 없다.
  confirmBar: {
    position: 'absolute', left: 0, right: 0, bottom: 0,
    flexDirection: 'row', alignItems: 'center', gap: 12,
    backgroundColor: paper.ink, paddingHorizontal: 15, paddingTop: 14, paddingBottom: 30,
  },
  confirmBtn: { backgroundColor: paper.action, paddingVertical: 13, paddingHorizontal: 16 },
  emptyBox: { margin: 20, padding: 26, alignItems: 'center' },
  emptyText: { fontSize: 15, color: paper.dim, textAlign: 'center', lineHeight: 22 },
});
