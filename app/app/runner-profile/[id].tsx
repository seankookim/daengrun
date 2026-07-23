import { router, useLocalSearchParams } from 'expo-router';
import { useEffect, useMemo, useState } from 'react';
import { Alert, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { Avatar, Row } from '../../src/components/ui';
import { checkSlot, fetchRunnerProfile, RunnerPublicProfile } from '../../src/lib/api';
import { supabase } from '../../src/lib/supabase';
import { draft } from '../../src/store';
import { colors } from '../../src/theme';

// 러너 공개 프로필 — 러너의 스토어프런트. 매칭 카드·동네 러너 셸프에서 진입.
// 러너 본인이 보면 미리보기 모드 (CTA 숨김).

const FOREST = '#132117';
const DAY = '일월화수목금토';

const fmtMin = (m: number) => `${String(Math.floor(m / 60)).padStart(2, '0')}:${String(m % 60).padStart(2, '0')}`;

// 가용시간 압축: 모든 요일 동일하면 '매일 HH:MM–HH:MM'
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
  // 슬롯별 가능 여부 — 서버 is_slot_available (규칙+예약충돌+휴식버퍼)
  const [slotOk, setSlotOk] = useState<Record<string, boolean | null>>({});

  useEffect(() => {
    if (!id) { setErr('러너 정보가 없어요'); return; }
    fetchRunnerProfile(id).then(setP).catch((e) => setErr(e?.message ?? '불러오기 실패'));
    supabase.auth.getUser().then(({ data }) => setIsMe(data.user?.id === id)).catch(() => {});
  }, [id]);

  const avail = p ? availabilitySummary(p.availability) : [];

  // 다음 7일 날짜 스트립
  const days = useMemo(() => Array.from({ length: 7 }, (_, i) => {
    const d = new Date(Date.now() + i * 86400_000);
    return { date: d, label: i === 0 ? '오늘' : i === 1 ? '내일' : undefined, d: d.getDate(), w: DAY[d.getDay()] };
  }), []);

  // 선택한 날의 슬롯 후보 — 요일 규칙에서 60분 단위 생성, 오늘은 2시간 전 통보 반영
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

  // 선택한 날의 슬롯 충돌 검사 (병렬)
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
        .catch(() => { if (alive) setSlotOk((m) => ({ ...m, [sl.key]: true })); }); // 검사 실패 시 서버 홀드가 최종 방어
    });
    return () => { alive = false; };
  }, [p, daySlots]);

  const pickSlot = (sl: { label: string; start: Date }) => {
    if (!p) return;
    draft.preferredRunnerId = p.profileId;
    draft.preferredRunnerName = p.name;
    draft.scheduledAtIso = sl.start.toISOString();
    const d = sl.start;
    draft.timeLabel = `${d.getMonth() + 1}월 ${d.getDate()}일 (${DAY[d.getDay()]}) ${sl.label}`;
    router.push('/owner/request');
  };

  return (
    <View style={{ flex: 1, backgroundColor: colors.cream }}>
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ padding: 22, paddingTop: 56, paddingBottom: 40 }}>
        <Row style={{ justifyContent: 'space-between' }}>
          <Pressable onPress={() => router.back()} style={s.backBtn}><Text style={{ fontSize: 18 }}>‹</Text></Pressable>
          <Text style={{ fontSize: 20, fontWeight: '900', color: FOREST }}>러너 프로필</Text>
          <View style={{ width: 40 }} />
        </Row>

        {err && <View style={s.emptyBox}><Text style={s.emptyText}>{err}</Text></View>}
        {!err && !p && <View style={s.emptyBox}><Text style={s.emptyText}>불러오는 중...</Text></View>}

        {p && (
          <>
            {/* ---------- hero ---------- */}
            <View style={s.hero}>
              <Row style={{ gap: 14 }}>
                <Avatar url={p.avatarUrl} char={p.name[0]} bg="#5a7a3c" size={72} />
                <View style={{ flex: 1, justifyContent: 'center' }}>
                  <Row style={{ gap: 6 }}>
                    <Text style={{ fontSize: 20, fontWeight: '900', color: '#fff' }}>{p.name}</Text>
                    {p.online && <View style={s.onlineDot} />}
                  </Row>
                  <Row style={{ gap: 5, marginTop: 6 }}>
                    <View style={s.limePill}><Text style={{ fontSize: 9.5, fontWeight: '800', color: FOREST }}>✓ {p.tier}</Text></View>
                    {p.trainerCertified && (
                      <View style={[s.limePill, { backgroundColor: '#fde8e3' }]}>
                        <Text style={{ fontSize: 9.5, fontWeight: '800', color: '#d84a2f' }}>훈련사</Text>
                      </View>
                    )}
                  </Row>
                  <Text style={{ fontSize: 12, color: '#b8c4ae', marginTop: 6 }}>
                    {p.district || '동네 미설정'}{p.avgRating != null ? ` · ★ ${p.avgRating}` : ''}
                  </Text>
                </View>
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

            {/* ---------- 자기소개 ---------- */}
            <View style={s.card}>
              <Text style={s.cardTitle}>자기소개</Text>
              <Text style={{ fontSize: 13, color: p.bio ? '#3d453d' : colors.dim, lineHeight: 20 }}>
                {p.bio ?? (isMe ? '아직 소개가 없어요 — 마이 > 프로필 설정에서 작성해보세요' : '아직 소개가 없어요')}
              </Text>
              {p.specialties.length > 0 && (
                <Row style={{ gap: 6, marginTop: 10, flexWrap: 'wrap' }}>
                  {p.specialties.map((sp) => (
                    <View key={sp} style={s.specChip}><Text style={{ fontSize: 10.5, fontWeight: '700', color: '#3d5a2b' }}>{sp}</Text></View>
                  ))}
                </Row>
              )}
            </View>

            {/* ---------- 가능 시간 + 슬롯 예약 ---------- */}
            <View style={s.card}>
              <Text style={s.cardTitle}>러닝 가능 시간</Text>
              {avail.length === 0 ? (
                <Text style={{ fontSize: 12.5, color: colors.dim }}>가용 시간 미설정 — 오픈 매칭으로만 예약할 수 있어요</Text>
              ) : (
                <>
                  <Text style={{ fontSize: 12, color: colors.dim, marginBottom: 8 }}>{avail.join(' · ')}</Text>
                  {/* day strip */}
                  <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: 8 }}>
                    {days.map((d, i) => (
                      <Pressable key={d.date.toISOString()} onPress={() => setDayIdx(i)} style={[s.dayChip, dayIdx === i && { backgroundColor: FOREST }]}>
                        <Text style={{ fontSize: 9.5, color: dayIdx === i ? '#b8c4ae' : colors.dim }}>{d.w}</Text>
                        <Text style={{ fontSize: 15, fontWeight: '900', color: dayIdx === i ? '#fff' : FOREST }}>{d.d}</Text>
                        {d.label && <Text style={{ fontSize: 8, fontWeight: '700', color: dayIdx === i ? colors.volt : '#5a7a3c' }}>{d.label}</Text>}
                      </Pressable>
                    ))}
                  </ScrollView>
                  {/* slot grid — 서버 충돌검사 반영 */}
                  {daySlots.length === 0 ? (
                    <Text style={{ fontSize: 12, color: colors.dim, marginTop: 12 }}>이 날은 가능한 시간이 없어요</Text>
                  ) : (
                    <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 8, marginTop: 12 }}>
                      {daySlots.map((sl) => {
                        const ok = slotOk[sl.key];
                        return (
                          <Pressable
                            key={sl.key}
                            disabled={isMe || ok === false}
                            onPress={() => pickSlot(sl)}
                            style={[s.slotChip, ok === false && { opacity: 0.35 }, ok === null && { opacity: 0.6 }]}
                          >
                            <Text style={{ fontSize: 13, fontWeight: '800', color: FOREST }}>{sl.label}</Text>
                            <Text style={{ fontSize: 8.5, color: ok === false ? '#d84a2f' : ok === null ? colors.dim : '#5a7a3c', marginTop: 1 }}>
                              {ok === false ? '마감' : ok === null ? '확인 중' : '가능'}
                            </Text>
                          </Pressable>
                        );
                      })}
                    </View>
                  )}
                  <Text style={{ fontSize: 10.5, color: colors.dim, marginTop: 10 }}>
                    {isMe ? '보호자는 여기서 시간을 골라 바로 예약해요' : '시간을 고르면 코스·옵션 선택으로 이어져요'}
                  </Text>
                </>
              )}
            </View>

            {/* ---------- 후기 ---------- */}
            <View style={s.card}>
              <Text style={s.cardTitle}>
                보호자 후기{p.avgRating != null ? ` · ★ ${p.avgRating}` : ''}
              </Text>
              {p.reviews.length === 0 && (
                <Text style={{ fontSize: 12.5, color: colors.dim }}>아직 후기가 없어요 — 첫 러닝의 주인공이 되어보세요</Text>
              )}
              {p.reviews.map((v, i) => (
                <View key={i} style={[s.reviewRow, i > 0 && { borderTopWidth: 1, borderTopColor: '#f0eee3' }]}>
                  <Row style={{ justifyContent: 'space-between' }}>
                    <Text style={{ fontSize: 12, fontWeight: '800', color: '#5a7a3c' }}>
                      {v.rating != null ? '★'.repeat(v.rating) : '후기'}
                    </Text>
                    <Text style={{ fontSize: 10.5, color: colors.dim }}>{v.when}</Text>
                  </Row>
                  {v.note && <Text style={{ fontSize: 12.5, color: '#3d453d', marginTop: 4, lineHeight: 18 }}>{v.note}</Text>}
                  {v.tags.length > 0 && (
                    <Row style={{ gap: 5, marginTop: 5, flexWrap: 'wrap' }}>
                      {v.tags.map((t) => (
                        <Text key={t} style={{ fontSize: 10.5, color: colors.dim }}>#{t}</Text>
                      ))}
                    </Row>
                  )}
                </View>
              ))}
            </View>

            {/* ---------- CTA ---------- */}
            {!isMe && (
              <>
                <Pressable
                  style={s.cta}
                  onPress={() => {
                    draft.preferredRunnerId = p.profileId;
                    draft.preferredRunnerName = p.name;
                    router.push('/owner/request');
                  }}
                >
                  <Text style={{ fontSize: 15, fontWeight: '900', color: FOREST }}>{p.name} 러너와 예약하기</Text>
                  <Text style={{ fontSize: 10.5, color: '#5d6b4a', marginTop: 2 }}>결제 후 이 러너에게 지명 요청이 우선 안내돼요</Text>
                </Pressable>
                <Pressable
                  style={s.ghostCta}
                  onPress={() => Alert.alert('채팅', '러너와의 채팅은 예약 후 열려요 (실시간 채팅 준비 중)')}
                >
                  <Text style={{ fontSize: 13, fontWeight: '800', color: '#3d453d' }}>채팅 문의</Text>
                </Pressable>
              </>
            )}
            {isMe && (
              <Text style={{ fontSize: 11.5, color: colors.dim, textAlign: 'center', marginTop: 14 }}>
                내 공개 프로필 미리보기 — 보호자에게 이렇게 보여요
              </Text>
            )}
          </>
        )}
      </ScrollView>
    </View>
  );
}

function HeroStat({ value, label }: { value: string; label: string }) {
  return (
    <View style={{ alignItems: 'center' }}>
      <Text style={{ fontSize: 14.5, fontWeight: '900', color: '#fff' }}>{value}</Text>
      <Text style={{ fontSize: 9.5, color: '#b8c4ae', marginTop: 3 }}>{label}</Text>
    </View>
  );
}

const s = StyleSheet.create({
  backBtn: { width: 40, height: 40, borderRadius: 20, backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: '#eceadf' },
  hero: { backgroundColor: FOREST, borderRadius: 22, padding: 18, marginTop: 18 },
  heroDiv: { width: 1, backgroundColor: '#2c4034' },
  onlineDot: { width: 9, height: 9, borderRadius: 5, backgroundColor: colors.volt, alignSelf: 'center' },
  limePill: { backgroundColor: colors.volt, borderRadius: 99, paddingVertical: 3, paddingHorizontal: 8 },
  card: { backgroundColor: '#fff', borderRadius: 18, padding: 15, borderWidth: 1, borderColor: '#eceadf', marginTop: 12 },
  cardTitle: { fontSize: 13.5, fontWeight: '900', color: FOREST, marginBottom: 8 },
  specChip: { backgroundColor: '#eef4e0', borderRadius: 99, paddingVertical: 4, paddingHorizontal: 10 },
  reviewRow: { paddingVertical: 10 },
  dayChip: { width: 46, borderRadius: 13, backgroundColor: '#f4f2ea', alignItems: 'center', paddingVertical: 8, gap: 1 },
  slotChip: { width: '22.5%', backgroundColor: '#f7f9f0', borderRadius: 12, borderWidth: 1, borderColor: '#dde8c4', alignItems: 'center', paddingVertical: 9 },
  cta: { backgroundColor: colors.volt, borderRadius: 18, alignItems: 'center', paddingVertical: 15, marginTop: 16 },
  ghostCta: { backgroundColor: '#fff', borderRadius: 16, alignItems: 'center', paddingVertical: 13, marginTop: 8, borderWidth: 1, borderColor: '#eceadf' },
  emptyBox: { marginTop: 24, backgroundColor: '#f4f2ea', borderRadius: 18, padding: 26, alignItems: 'center' },
  emptyText: { fontSize: 13, color: colors.dim, textAlign: 'center', lineHeight: 19 },
});
