import { router, useLocalSearchParams } from 'expo-router';
import { useEffect, useMemo, useRef, useState } from 'react';
import { Alert, Animated, Dimensions, Image, Modal, Pressable, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { Avatar, Icon, Row } from '../../src/components/ui';
import { checkSlot, CoursePatch, deleteGear, NOT_FOUND, deleteRunnerPhoto, fetchGear, fetchRunnerCourseHistory, fetchRunnerProfile, GEAR_KINDS, GEAR_META, GearItem, GearKind, RunnerPublicProfile, updateMyProfile, updateRunnerBio, uploadRunnerPhoto, upsertGear } from '../../src/lib/api';
import { PatchBadge } from '../../src/components/patch';
import { haptic } from '../../src/lib/haptics';
import { goBackOrHome } from '../../src/lib/nav';
import { supabase } from '../../src/lib/supabase';
import { draft, session } from '../../src/store';
import { colors, paper } from '../../src/theme';

// 러너 공개 프로필 — 풀블리드(인스타 스타일) 스토어프런트.
// 갤러리(runners.photos) · 실슬롯 예약 · 본인이 보면 편집/미리보기 모드.
// 솔로 테스트: 본인 슬롯 예약도 허용 (owner==runner 루프가 테스트 체제)

// [2026-08-12 · Sean "remove forest"] 이 파일의 로컬 상수 FOREST = '#0F1D13' 은퇴. 은퇴된 스왈프/포레스트 팔레트의
// 마지막 잔재였고, 12개 파일에 각자 로컬 상수로 복사돼 있었다 (한 값에 주인 12명).
// paper.ink(#111111)로 접는다 — 색차는 사실상 안 보이고(둘 다 근처 검정), 그게 정확히 아무도
// 못 본 이유다. 다크 면에도 같은 토큰을 쓴다 — 캘린더 보드·정산 티켓·빕 스트랩이 이미 그런다.
const DAY = '일월화수목금토';
const W = Dimensions.get('window').width;
const TILE = (W - 4) / 3; // 3열 엣지-투-엣지, 2px 갭

const fmtMin = (m: number) => `${String(Math.floor(m / 60)).padStart(2, '0')}:${String(m % 60).padStart(2, '0')}`;

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
  const [p, setP] = useState<RunnerPublicProfile | null>(null);
  const [err, setErr] = useState<string | null>(null);
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
  // 단일 프로필 편집기 — 마이의 별도 시트 대신 여기서 이름·동네·소개 전부 (혼선 제거)
  const [editing, setEditing] = useState(false);
  const [eName, setEName] = useState('');
  const [eDistrict, setEDistrict] = useState('');
  const [eBio, setEBio] = useState('');
  const [saving, setSaving] = useState(false);

  const openEdit = () => {
    if (!p) return;
    setEName(p.name);
    setEDistrict(p.district);
    setEBio(p.bio ?? '');
    setEditing(true);
  };

  const saveEdit = async () => {
    setSaving(true);
    try {
      await updateMyProfile({ name: eName.trim() || undefined, district: eDistrict.trim() || undefined });
      await updateRunnerBio(eBio.trim());
      setEditing(false);
      if (id) fetchRunnerProfile(id).then(setP).catch(() => {});
    } catch (e) {
      Alert.alert('저장 실패', (e as Error).message);
    } finally {
      setSaving(false);
    }
  };
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

  useEffect(() => {
    if (!id) { setErr('러너 정보가 없어요'); return; }
    // Never render `e.message` — PostgREST's English reached this screen verbatim on a bad or
    // retired profile id. Not-found and failure get different sentences.
    fetchRunnerProfile(id).then(setP).catch((e) => setErr(e?.message === NOT_FOUND
      ? '러너를 찾을 수 없어요'
      : '러너 정보를 불러오지 못했어요'));
    fetchGear(id).then(setGear).catch(() => {}); // 장비는 실패해도 프로필은 뜬다
    fetchRunnerCourseHistory(id).then(setCourseHist).catch(() => {}); // 0023 미배포 시 조용히 숨김
    supabase.auth.getUser().then(({ data }) => setIsMe(data.user?.id === id)).catch(() => {});
  }, [id]);

  const avail = p ? availabilitySummary(p.availability) : [];

  // 역할 기반 모드 분리 — 편집은 러너 모드 + 본인, 예약은 보호자 모드에서만.
  // (솔로 계정에서 두 모드가 겹쳐 보이던 혼선 수정, 2026-07-23)
  const canEdit = isMe && session.role === 'runner';
  const canBook = session.role === 'owner';

  const days = useMemo(() => Array.from({ length: 7 }, (_, i) => {
    const d = new Date(Date.now() + i * 86400_000);
    return { date: d, label: i === 0 ? '오늘' : i === 1 ? '내일' : undefined, d: d.getDate(), w: DAY[d.getDay()] };
  }), []);

  const daySlots = useMemo(() => {
    if (!p) return [] as { key: string; label: string; start: Date }[];
    const day = days[dayIdx];
    const wd = day.date.getDay();
    const rules = p.availability.filter((r) => r.weekday === wd);
    const out: { key: string; label: string; start: Date }[] = [];
    const minStart = Date.now() + 2 * 3600_000;
    rules.forEach((r) => {
      for (let m = r.startMin; m + 60 <= r.endMin; m += 60) {
        const start = new Date(day.date.getFullYear(), day.date.getMonth(), day.date.getDate(), Math.floor(m / 60), m % 60);
        if (start.getTime() < minStart) continue;
        out.push({ key: start.toISOString(), label: fmtMin(m), start });
      }
    });
    return out;
  }, [p, dayIdx, days]);

  useEffect(() => {
    if (!p || daySlots.length === 0) return;
    let alive = true;
    setSlotOk((prev) => {
      const next = { ...prev };
      daySlots.forEach((sl) => { if (!(sl.key in next)) next[sl.key] = null; });
      return next;
    });
    daySlots.forEach((sl) => {
      const end = new Date(sl.start.getTime() + 60 * 60_000);
      checkSlot(p.profileId, sl.start.toISOString(), end.toISOString())
        .then((ok) => { if (alive) setSlotOk((m) => ({ ...m, [sl.key]: ok })); })
        // [honesty P1 2026-08-11] failure used to paint the slot 가능 — a booking
        // against fabricated availability is a real-world no-show. Unknown stays unknown.
        .catch(() => { if (alive) setSlotOk((m) => ({ ...m, [sl.key]: 'error' })); });
    });
    return () => { alive = false; };
  }, [p, daySlots]);

  // single-slot recheck — the retry path for a failed availability check
  const recheckSlot = (sl: { key: string; start: Date }) => {
    if (!p) return;
    setSlotOk((m) => ({ ...m, [sl.key]: null }));
    const end = new Date(sl.start.getTime() + 60 * 60_000);
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
    const d = sl.start;
    draft.timeLabel = `${d.getMonth() + 1}월 ${d.getDate()}일 (${DAY[d.getDay()]}) ${sl.label}`;
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

  return (
    <View style={{ flex: 1, backgroundColor: colors.cream }}>
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingBottom: selected ? 140 : 40 }}>
        {/* header (패딩 있는 유일한 상단 영역) */}
        <Row style={{ justifyContent: 'space-between', paddingHorizontal: 12, paddingTop: 56 }}>
          <Pressable onPress={goBackOrHome} style={s.backBtn} accessibilityRole="button" accessibilityLabel="뒤로"><Text style={{ fontSize: 20.5 }}>‹</Text></Pressable>
          <Text style={{ fontSize: 23, fontWeight: '900', color: paper.ink }}>러너 프로필</Text>
          <View style={{ width: 40 }} />
        </Row>

        {err && <View style={s.emptyBox}><Text style={s.emptyText}>{err}</Text></View>}
        {!err && !p && <View style={s.emptyBox}><Text style={s.emptyText}>불러오는 중...</Text></View>}

        {p && (
          <>
            {/* ---------- hero: 풀블리드 + 갤러리 첫 사진 배경 (사진이 디자인이다) ---------- */}
            <View style={[s.hero, { overflow: 'hidden' }]}>
              {p.photos[0] && (
                <Image
                  source={{ uri: p.photos[0] }}
                  style={{ position: 'absolute', top: 0, left: 0, right: 0, bottom: 0, opacity: 0.25 }}
                  resizeMode="cover"
                />
              )}
              <Row style={{ gap: 14 }}>
                <Avatar url={p.avatarUrl} char={p.name[0]} bg="#5a7a3c" size={76} />
                <View style={{ flex: 1, justifyContent: 'center' }}>
                  <Row style={{ gap: 6 }}>
                    <Text style={{ fontSize: 24, fontWeight: '900', color: '#fff' }}>{p.name}</Text>
                    {p.online && <View style={s.onlineDot} />}
                  </Row>
                  <Row style={{ gap: 5, marginTop: 6 }}>
                    <View style={s.limePill}><Text style={{ fontSize: 14, fontWeight: '800', color: paper.ink }}>✓ {p.tier}</Text></View>
                    {p.trainerCertified && (
                      <View style={[s.limePill, { backgroundColor: '#fde8e3' }]}>
                        <Text style={{ fontSize: 14, fontWeight: '800', color: '#d84a2f' }}>훈련사</Text>
                      </View>
                    )}
                  </Row>
                  <Text style={{ fontSize: 14, color: '#b8c4ae', marginTop: 6 }}>
                    {p.district || '동네 미설정'}{p.avgRating != null ? ` · ★ ${p.avgRating}` : ''}
                  </Text>
                </View>
                {canEdit && (
                  <Pressable onPress={openEdit} style={s.editChip}>
                    <Text style={{ fontSize: 14, fontWeight: '800', color: paper.ink }}>✎ 편집</Text>
                  </Pressable>
                )}
              </Row>
              <Row style={{ marginTop: 16, backgroundColor: '#1d3023', borderRadius: 14, paddingVertical: 12, justifyContent: 'space-around' }}>
                <HeroStat value={`${p.totalRuns}회`} label="완료 러닝" />
                <View style={s.heroDiv} />
                <HeroStat value={`${p.totalKm}km`} label="누적 거리" />
                <View style={s.heroDiv} />
                <HeroStat value={p.paceLabel} label="평균 페이스" />
                <View style={s.heroDiv} />
                <HeroStat value={p.respondRate != null ? `${p.respondRate}%` : '신규'} label="응답률" />
              </Row>
            </View>

            {/* ---------- 갤러리: 엣지-투-엣지 3열 (편집은 러너 모드 + 본인만) ---------- */}
            {(p.photos.length > 0 || canEdit) && (
              <View style={{ backgroundColor: '#fff' }}>
                <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 2 }}>
                  {p.photos.map((url) => (
                    <Pressable key={url} onLongPress={canEdit ? () => removePhoto(url) : undefined}>
                      <Image source={{ uri: url }} style={{ width: TILE, height: TILE, backgroundColor: '#DCD6C4' }} />
                    </Pressable>
                  ))}
                  {canEdit && (
                    <Pressable onPress={addPhoto} disabled={uploadingPhoto} style={s.addTile}>
                      <Text style={{ fontSize: 25.5, color: '#5a7a3c' }}>{uploadingPhoto ? '…' : '＋'}</Text>
                      <Text style={{ fontSize: 14, color: colors.dim, marginTop: 2 }}>사진 추가</Text>
                    </Pressable>
                  )}
                </View>
                {canEdit && p.photos.length > 0 && (
                  <Text style={{ fontSize: 14, color: colors.dim, padding: 8, textAlign: 'center' }}>길게 눌러 삭제</Text>
                )}
              </View>
            )}

            {/* ---------- 자기소개 ---------- */}
            <View style={s.section}>
              <Text style={s.sectionTitle}>자기소개</Text>
              <Text style={{ fontSize: 15.5, color: p.bio ? '#3d453d' : colors.dim, lineHeight: 24 }}>
                {p.bio ?? (isMe ? '아직 소개가 없어요 — 마이 > 프로필 설정에서 작성해보세요' : '아직 소개가 없어요')}
              </Text>
              {p.specialties.length > 0 && (
                <Row style={{ gap: 6, marginTop: 10, flexWrap: 'wrap' }}>
                  {p.specialties.map((sp) => (
                    <View key={sp} style={s.specChip}><Text style={{ fontSize: 14, fontWeight: '700', color: '#3d5a2b' }}>{sp}</Text></View>
                  ))}
                </Row>
              )}
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
                      <Pressable key={d.date.toISOString()} onPress={() => { setDayIdx(i); setSelected(null); }} style={[s.dayChip, dayIdx === i && { backgroundColor: paper.ink }]}>
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
                    <Text style={{ fontSize: 17, fontWeight: '900', color: paper.ink }}>{p.name} 러너와 예약하기</Text>
                    {/* [§E.5] 지명은 결제가 아니라 **홀드 직후** 나간다 (request.tsx의 pay()
                        ③번 걸음). "결제 후"는 더 이상 존재하지 않는 단계를 가리켰다. */}
                    <Text style={{ fontSize: 14, color: '#5d6b4a', marginTop: 2 }}>예약하면 이 러너에게 지명 요청이 먼저 전달돼요</Text>
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
                <Text style={{ fontSize: 15, color: colors.dim, textAlign: 'center', marginTop: 14 }}>
                  {isMe ? '내 공개 프로필 — 사진은 여기서, 소개는 마이 > 프로필 설정에서 편집해요' : '예약은 보호자 모드에서 가능해요'}
                </Text>
              )}
            </View>
          </>
        )}
      </ScrollView>

      {/* ---------- 프로필 편집 시트 (러너 단일 편집기) ---------- */}
      <Modal visible={editing} transparent animationType="slide" onRequestClose={() => setEditing(false)}>
        <Pressable style={s.editBackdrop} onPress={() => setEditing(false)} />
        <View style={s.editSheet}>
          <View style={s.editHandle} />
          <Text style={{ fontSize: 22, fontWeight: '900', color: paper.ink }}>프로필 편집</Text>
          <Text style={s.editLabel}>이름</Text>
          <TextInput value={eName} onChangeText={setEName} style={s.editInput} maxLength={20} placeholder="이름 또는 닉네임" placeholderTextColor="#b0ada0" />
          <Text style={s.editLabel}>활동 동네</Text>
          <TextInput value={eDistrict} onChangeText={setEDistrict} style={s.editInput} maxLength={20} placeholder="예: 반포동" placeholderTextColor="#b0ada0" />
          <Text style={s.editLabel}>자기소개</Text>
          <TextInput
            value={eBio}
            onChangeText={setEBio}
            style={[s.editInput, { height: 96, textAlignVertical: 'top', paddingTop: 12 }]}
            multiline
            maxLength={300}
            placeholder="러닝 경력, 반려견 경험, 나의 강점"
            placeholderTextColor="#b0ada0"
          />
          <Text style={{ fontSize: 14, color: colors.dim, marginTop: 8 }}>사진·갤러리는 이 페이지에서 바로 편집해요</Text>
          <Pressable onPress={saveEdit} disabled={saving} style={[s.editSave, saving && { opacity: 0.5 }]}>
            <Text style={{ fontSize: 16, fontWeight: '900', color: paper.ink }}>{saving ? '저장 중...' : '저장'}</Text>
          </Pressable>
        </View>
      </Modal>

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
            <Text style={{ fontSize: 16, fontWeight: '900', color: paper.ink }}>이 시간으로 ›</Text>
          </Pressable>
        </Animated.View>
      )}
    </View>
  );
}

function HeroStat({ value, label }: { value: string; label: string }) {
  return (
    <View style={{ alignItems: 'center' }}>
      <Text style={{ fontSize: 16.5, fontWeight: '900', color: '#fff' }}>{value}</Text>
      <Text style={{ fontSize: 14, color: '#b8c4ae', marginTop: 3 }}>{label}</Text>
    </View>
  );
}

const s = StyleSheet.create({
  backBtn: { width: 40, height: 40, borderRadius: 20, backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: '#DCD6C4' },
  // 풀블리드: 히어로·섹션 모두 좌우 마진 없음, 내부 패딩만
  hero: { backgroundColor: paper.ink, padding: 20, marginTop: 14 },
  heroDiv: { width: 1, backgroundColor: '#2c4034' },
  onlineDot: { width: 9, height: 9, borderRadius: 5, backgroundColor: colors.volt, alignSelf: 'center' },
  limePill: { backgroundColor: colors.volt, borderRadius: 99, paddingVertical: 3, paddingHorizontal: 8 },
  section: { backgroundColor: '#fff', paddingHorizontal: 12, paddingVertical: 16, borderBottomWidth: 1, borderBottomColor: '#DCD6C4' },
  sectionTitle: { fontSize: 15.5, fontWeight: '900', color: paper.ink, marginBottom: 8 },
  specChip: { backgroundColor: '#eef4e0', borderRadius: 99, paddingVertical: 4, paddingHorizontal: 10 },
  // 장비 로드아웃 슬롯 (0019)
  gearSlot: { width: 104, backgroundColor: '#fff', borderRadius: 14, borderWidth: 1, borderColor: '#DCD6C4', padding: 8, alignItems: 'center' },
  gearSlotEmpty: { borderStyle: 'dashed', backgroundColor: '#faf8f1' },
  gearPhoto: { width: 88, height: 66, borderRadius: 10, backgroundColor: '#DCD6C4' },
  gearBadge: { backgroundColor: '#DDF0A6', borderRadius: 99, paddingVertical: 2, paddingHorizontal: 8, marginTop: 3 },
  reviewRow: { paddingVertical: 10 },
  dayChip: { width: 46, borderRadius: 13, backgroundColor: '#f4f2ea', alignItems: 'center', paddingVertical: 8, gap: 1 },
  slotChip: { width: '22.5%', backgroundColor: '#f7f9f0', borderRadius: 12, borderWidth: 1, borderColor: '#dde8c4', alignItems: 'center', paddingVertical: 9 },
  addTile: { width: TILE, height: TILE, backgroundColor: '#f4f2ea', alignItems: 'center', justifyContent: 'center' },
  cta: { backgroundColor: colors.volt, borderRadius: 18, alignItems: 'center', paddingVertical: 15, marginTop: 16 },
  // [2026-08-20 · T4] ghostCta 삭제 — 그 스타일을 쓰던 유일한 소자가 '채팅 문의' 고스트 버튼이었고,
  // 그 버튼은 은퇴했다 (위 CTA 블록의 주석). 주인 없는 스타일을 남겨두면 다음 사람은 화면 어딘가에
  // 세컨더리 버튼이 있다고 읽는다.
  editChip: { backgroundColor: colors.volt, borderRadius: 99, paddingVertical: 7, paddingHorizontal: 12, alignSelf: 'flex-start' },
  editBackdrop: { flex: 1, backgroundColor: '#00000055' },
  editSheet: { backgroundColor: colors.cream, borderTopLeftRadius: 26, borderTopRightRadius: 26, padding: 16, paddingBottom: 40 },
  editHandle: { alignSelf: 'center', width: 44, height: 5, borderRadius: 3, backgroundColor: '#DCD6C4', marginBottom: 14 },
  editLabel: { fontSize: 14, fontWeight: '800', color: '#3d453d', marginTop: 14, marginBottom: 6 },
  editInput: { backgroundColor: '#fff', borderRadius: 14, borderWidth: 1, borderColor: '#DCD6C4', paddingVertical: 12, paddingHorizontal: 14, fontSize: 16.5, color: paper.ink },
  editSave: { backgroundColor: colors.volt, borderRadius: 16, alignItems: 'center', paddingVertical: 14, marginTop: 18 },
  confirmBar: {
    position: 'absolute', left: 0, right: 0, bottom: 0,
    flexDirection: 'row', alignItems: 'center', gap: 12,
    backgroundColor: paper.ink, paddingHorizontal: 12, paddingTop: 14, paddingBottom: 30,
    borderTopLeftRadius: 24, borderTopRightRadius: 24,
  },
  confirmBtn: { backgroundColor: colors.volt, borderRadius: 16, paddingVertical: 13, paddingHorizontal: 16 },
  emptyBox: { margin: 20, backgroundColor: '#f4f2ea', borderRadius: 18, padding: 26, alignItems: 'center' },
  emptyText: { fontSize: 15, color: colors.dim, textAlign: 'center', lineHeight: 22 },
});
