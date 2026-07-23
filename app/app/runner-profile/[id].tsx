import { router, useLocalSearchParams } from 'expo-router';
import { useEffect, useState } from 'react';
import { Alert, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { Avatar, Row } from '../../src/components/ui';
import { fetchRunnerProfile, RunnerPublicProfile } from '../../src/lib/api';
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

  useEffect(() => {
    if (!id) { setErr('러너 정보가 없어요'); return; }
    fetchRunnerProfile(id).then(setP).catch((e) => setErr(e?.message ?? '불러오기 실패'));
    supabase.auth.getUser().then(({ data }) => setIsMe(data.user?.id === id)).catch(() => {});
  }, [id]);

  const avail = p ? availabilitySummary(p.availability) : [];

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

            {/* ---------- 가능 시간 ---------- */}
            <View style={s.card}>
              <Text style={s.cardTitle}>러닝 가능 시간</Text>
              {avail.length === 0 ? (
                <Text style={{ fontSize: 12.5, color: colors.dim }}>가용 시간 미설정</Text>
              ) : (
                avail.map((line) => (
                  <Text key={line} style={{ fontSize: 13, color: '#3d453d', lineHeight: 21 }}>{line}</Text>
                ))
              )}
              <Text style={{ fontSize: 10.5, color: colors.dim, marginTop: 6 }}>
                시간대별 예약 선택은 곧 이 화면에서 바로 가능해져요
              </Text>
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
  cta: { backgroundColor: colors.volt, borderRadius: 18, alignItems: 'center', paddingVertical: 15, marginTop: 16 },
  ghostCta: { backgroundColor: '#fff', borderRadius: 16, alignItems: 'center', paddingVertical: 13, marginTop: 8, borderWidth: 1, borderColor: '#eceadf' },
  emptyBox: { marginTop: 24, backgroundColor: '#f4f2ea', borderRadius: 18, padding: 26, alignItems: 'center' },
  emptyText: { fontSize: 13, color: colors.dim, textAlign: 'center', lineHeight: 19 },
});
