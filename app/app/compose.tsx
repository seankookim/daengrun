import { router, useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Alert, Pressable, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { PaperBtn } from '../src/components/paper-btn';
import { Row } from '../src/components/ui';
import { fetchMyBookings, fetchMySharedBookingIds, fetchRunnerJobs, shareRunToFeed } from '../src/lib/api';
import { useNumFont } from '../src/lib/fonts';
import { haptic } from '../src/lib/haptics';
import { session } from '../src/store';
import { CollarKey, collarColors, paper } from '../src/theme';

// 피드 컴포저 — 커뮤니티 직행 포스트 진입점 (owner home · runner home · 피드 상단 컴포즈 바가 여기로 온다).
// Real precondition (shareRunToFeed): a booking with a runs row — i.e. a COMPLETED run — and one
// post per booking (feed_posts.booking_id unique). So this screen is a RUN PICKER, not a free-text
// composer: pick a completed run, add an optional caption, share. No completed run = the honest
// empty state with a route to schedule. Already-shared runs render as "공유 완료" status, not buttons.
// Paper chrome: white canvas, sharp corners, 40px coral-border back square, ink-bar primary CTA,
// busy = label swap (F2.1). Photo/stats are NOT editable here — they come from the run report
// (photos[0], actual km/duration/PB badges), and the screen says so.

interface Cand {
  bookingId: string;
  dogName: string;
  km: number;
  when: string;
  collar?: string | null;
  shared: boolean;
}

export default function Compose() {
  const nf = useNumFont();
  const [cands, setCands] = useState<Cand[]>([]);
  const [loaded, setLoaded] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [sel, setSel] = useState<string | null>(null);
  const [caption, setCaption] = useState('');
  const [busy, setBusy] = useState(false);

  // Owner completed bookings + runner completed jobs, merged (dual-role accounts see both).
  // Each fetch self-scopes to the signed-in user, so the wrong-role call just returns [].
  const load = async () => {
    setError(null);
    try {
      const [bs, jobs, sharedIds] = await Promise.all([
        fetchMyBookings(),
        fetchRunnerJobs(),
        fetchMySharedBookingIds(),
      ]);
      const list: Cand[] = [];
      const seen = new Set<string>();
      for (const b of bs) {
        if (b.status !== 'completed') continue;
        seen.add(b.id);
        list.push({
          bookingId: b.id, dogName: b.dogName, km: b.km,
          when: `${b.dateLabel} ${b.timeLabel}`, collar: b.dogCollar ?? null,
          shared: sharedIds.includes(b.id),
        });
      }
      for (const j of jobs) {
        if (j.status !== 'completed' || seen.has(j.bookingId)) continue;
        list.push({ bookingId: j.bookingId, dogName: j.dogName, km: j.km, when: j.when, shared: sharedIds.includes(j.bookingId) });
      }
      setCands(list);
      setSel((cur) => (cur && list.some((c) => c.bookingId === cur && !c.shared) ? cur : list.find((c) => !c.shared)?.bookingId ?? null));
      setLoaded(true);
    } catch (e) {
      setError((e as Error).message ?? '불러오지 못했어요');
      setLoaded(true);
    }
  };
  useFocusEffect(useCallback(() => { load(); }, []));

  const submit = async () => {
    if (!sel || busy) return;
    setBusy(true);
    try {
      await shareRunToFeed(sel, caption.trim() || undefined);
      haptic('light');
      // Straight to the feed — the new post is at the top (fetchFeed reloads on focus).
      router.replace('/community');
    } catch (e) {
      Alert.alert('피드 공유 실패', (e as Error).message);
      load(); // e.g. '이미 피드에 공유한 러닝이에요' — refresh the 공유 완료 markers to match reality
    } finally {
      setBusy(false);
    }
  };

  const shareable = cands.filter((c) => !c.shared);
  const done = cands.filter((c) => c.shared);

  return (
    <ScrollView
      style={{ flex: 1, backgroundColor: paper.canvas }}
      contentContainerStyle={{ padding: 16, paddingTop: 56, paddingBottom: 40 }}
      keyboardShouldPersistTaps="handled"
    >
      <Row style={{ justifyContent: 'space-between' }}>
        <Pressable onPress={() => router.back()} style={s.backBtn} accessibilityRole="button" accessibilityLabel="뒤로">
          <Text style={{ fontSize: 20.5, color: paper.ink }}>‹</Text>
        </Pressable>
        <Text style={{ fontSize: 23, fontWeight: '900', color: paper.ink }}>피드 자랑하기</Text>
        <View style={{ width: 40 }} />
      </Row>
      <Text style={{ fontSize: 14.5, lineHeight: 20, color: paper.dim, textAlign: 'center', marginTop: 6 }}>
        완료된 러닝을 골라 동네 피드에 올려요
      </Text>

      {/* 3 honest states: loading ≠ error ≠ empty */}
      {!loaded && (
        <Text style={{ fontSize: 14, color: paper.dim, textAlign: 'center', marginTop: 36 }}>완료된 러닝 불러오는 중...</Text>
      )}

      {loaded && error != null && (
        <View style={s.failStrip}>
          <Text style={{ fontSize: 14, fontWeight: '700', color: paper.critical }}>러닝 기록을 불러오지 못했어요</Text>
          <Text style={{ fontSize: 14, color: paper.critical, marginTop: 3 }} numberOfLines={2}>{error}</Text>
          <PaperBtn label="다시 시도" variant="secondary" onPress={load} style={{ marginTop: 10 }} />
        </View>
      )}

      {loaded && error == null && cands.length === 0 && (
        <View style={s.emptyBox}>
          <Text style={{ fontSize: 15, fontWeight: '700', color: paper.ink, textAlign: 'center' }}>완료된 러닝이 있어야 자랑할 수 있어요</Text>
          <Text style={{ fontSize: 14.5, color: paper.dim, textAlign: 'center', marginTop: 6, lineHeight: 21 }}>
            러닝이 끝나면 사진과 기록이{'\n'}여기서 바로 피드에 올라가요
          </Text>
          <PaperBtn
            label={session.role === 'runner' ? '내 캘린더 보기' : '내 일정 보기'}
            variant="secondary"
            onPress={() => router.push(session.role === 'runner' ? '/runner/calendar' : '/owner/schedule')}
            style={{ marginTop: 14 }}
          />
        </View>
      )}

      {loaded && error == null && cands.length > 0 && (
        <>
          <Row style={{ alignItems: 'center', gap: 8, marginTop: 20, marginBottom: 10 }}>
            <Text style={s.kicker}>SHARE TO FEED</Text>
            <View style={s.kickerRule} />
          </Row>

          {shareable.length === 0 ? (
            <View style={s.emptyBox}>
              <Text style={{ fontSize: 14.5, color: paper.dim, textAlign: 'center', lineHeight: 21 }}>
                완료된 러닝을 모두 피드에 올렸어요{'\n'}다음 러닝이 끝나면 다시 자랑할 수 있어요
              </Text>
            </View>
          ) : (
            <View style={{ gap: 8 }}>
              {shareable.map((c) => {
                const on = sel === c.bookingId;
                return (
                  <Pressable
                    key={c.bookingId}
                    onPress={() => setSel(c.bookingId)}
                    style={({ pressed }) => [s.runCard, on && s.runCardOn, { transform: [{ scale: pressed ? 0.96 : 1 }] }]}
                    accessibilityRole="button"
                    accessibilityState={{ selected: on }}
                  >
                    <View style={[s.radio, on && s.radioOn]}>{on && <View style={s.radioDot} />}</View>
                    <View style={{ flex: 1, minWidth: 0 }}>
                      <Row style={{ gap: 6, alignItems: 'center' }}>
                        {c.collar && collarColors[c.collar as CollarKey] && (
                          <View style={{ width: 9, height: 9, borderRadius: 4.5, backgroundColor: collarColors[c.collar as CollarKey] }} />
                        )}
                        <Text style={{ fontSize: 15.5, fontWeight: '800', color: paper.ink }} numberOfLines={1}>
                          {c.dogName} · <Text style={nf}>{c.km}</Text>km 완주
                        </Text>
                      </Row>
                      <Text style={{ fontSize: 14, color: paper.dim, marginTop: 3 }} numberOfLines={1}>{c.when}</Text>
                    </View>
                  </Pressable>
                );
              })}
            </View>
          )}

          {shareable.length > 0 && (
            <>
              <TextInput
                value={caption}
                onChangeText={setCaption}
                placeholder="한 마디 남기기 (선택) — 예: 오늘도 신나게 달렸어요!"
                placeholderTextColor={paper.faint}
                style={s.captionInput}
                multiline
                maxLength={120}
              />
              <Text style={{ fontSize: 14, color: paper.dim, marginTop: 8, lineHeight: 19 }}>
                사진은 러닝 리포트의 인증샷이 자동으로 실리고, 거리·시간 기록이 함께 표시돼요
              </Text>
              <PaperBtn
                label="🐾 피드에 올리기"
                busyLabel="올리는 중..."
                busy={busy}
                disabled={!sel}
                onPress={submit}
                style={{ marginTop: 14 }}
              />
            </>
          )}

          {/* 이미 공유한 러닝 — 상태 표시(버튼 아님). 다시 눌러도 되는 척하지 않는다 */}
          {done.length > 0 && (
            <View style={{ marginTop: 18 }}>
              <Row style={{ alignItems: 'center', gap: 8, marginBottom: 8 }}>
                <Text style={s.kicker}>ALREADY SHARED</Text>
                <View style={s.kickerRule} />
              </Row>
              <View style={{ gap: 6 }}>
                {done.map((c) => (
                  <View key={c.bookingId} style={s.doneRow}>
                    <Text style={{ flex: 1, fontSize: 14, color: paper.dim }} numberOfLines={1}>
                      {c.dogName} · <Text style={nf}>{c.km}</Text>km · {c.when}
                    </Text>
                    <Text style={{ fontSize: 14, fontWeight: '700', color: paper.dim }}>공유 완료</Text>
                  </View>
                ))}
              </View>
            </View>
          )}
        </>
      )}
    </ScrollView>
  );
}

const s = StyleSheet.create({
  backBtn: {
    width: 40, height: 40, backgroundColor: paper.canvas, alignItems: 'center', justifyContent: 'center',
    borderWidth: 1, borderColor: paper.line,
  },
  kicker: { fontSize: 12, fontWeight: '600', letterSpacing: 2, color: paper.faint, textTransform: 'uppercase' },
  kickerRule: { flex: 1, height: 1, backgroundColor: '#EEEEEE' },

  emptyBox: { backgroundColor: paper.canvas, borderWidth: 1, borderColor: '#EEEEEE', padding: 20, marginTop: 20 },
  // 라우드-페일 스트립 — criticalWash 바닥 + critical 잉크 (코랄 line과 절대 공유 금지)
  failStrip: { backgroundColor: paper.criticalWash, padding: 14, marginTop: 20 },

  // 런 픽커 카드 — 뉴트럴 #EEE, 선택 = 코랄 1px (선택 신호에만 코랄)
  runCard: {
    flexDirection: 'row', alignItems: 'center', gap: 11,
    backgroundColor: paper.canvas, borderWidth: 1, borderColor: '#EEEEEE',
    paddingVertical: 13, paddingHorizontal: 13, minHeight: 56,
  },
  runCardOn: { borderColor: paper.line, backgroundColor: paper.wash },
  radio: {
    width: 20, height: 20, borderRadius: 10, borderWidth: 1.5, borderColor: '#DDDDDD',
    alignItems: 'center', justifyContent: 'center',
  },
  radioOn: { borderColor: paper.line },
  radioDot: { width: 10, height: 10, borderRadius: 5, backgroundColor: paper.line },

  captionInput: {
    marginTop: 12, backgroundColor: paper.canvas, borderWidth: 1, borderColor: '#EEEEEE',
    paddingVertical: 11, paddingHorizontal: 12, fontSize: 15, color: paper.ink,
    minHeight: 72, textAlignVertical: 'top',
  },

  doneRow: {
    flexDirection: 'row', alignItems: 'center', gap: 8,
    backgroundColor: paper.disabledFill, paddingVertical: 10, paddingHorizontal: 12,
  },
});
