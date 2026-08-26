import { router, useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Alert, Image, Pressable, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { PaperBtn } from '../src/components/paper-btn';
import { Row } from '../src/components/ui';
import { createFreePost, fetchMyBookings, fetchMySharedBookingIds, fetchRunnerJobs, shareRunToFeed } from '../src/lib/api';
import { useNumFont } from '../src/lib/fonts';
import { haptic } from '../src/lib/haptics';
import { goBackOrHome } from '../src/lib/nav';
import { session } from '../src/store';
import { CollarKey, collarColors, lilac, paper } from '../src/theme';

// 피드 컴포저 — 커뮤니티 직행 포스트 진입점 (owner home · runner home · 피드 상단 컴포즈 바가 여기로 온다).
//
// [Sean 2026-08-12] "let's not restrict what the users will be uploading; just give them an
// accessible way to upload the shareable card that we've already made."
// 그래서 이 화면의 기본값이 뒤집혔다: 예전엔 **러닝 피커**였고(완료된 러닝이 없으면 아무것도 못 올림),
// 이제는 **자유 컴포저**다 — 글·사진만으로 올라가고, 러닝 카드는 **선택 첨부**다.
// 서버가 그 선을 지킨다 (0074 feed_claim_gate): 자유 포스트는 예약을 요구하지 않고,
// km/durationSec/trace를 실은 포스트만 실제 완료 러닝을 요구한다.
// 자랑은 누구나, 기록은 달린 사람만.
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
  // [Sean 2026-08-12] 러닝 첨부는 이제 선택이다. null = 자유 포스트.
  const [photo, setPhoto] = useState<string | null>(null); // base64
  const [attachOpen, setAttachOpen] = useState(false);

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
      // [Sean 2026-08-12] 기본값 = **첨부 없음**. 예전엔 첫 러닝을 자동 선택했는데, 그러면 모든 포스트가
      // 조용히 러닝 주장을 달고 나간다 — "업로드를 제한하지 말라"의 반대다. 붙이는 건 사용자가 고른다.
      // 이미 고른 게 목록에서 사라졌으면(공유 완료 등) 선택을 놓는다.
      setSel((cur) => (cur && list.some((c) => c.bookingId === cur && !c.shared) ? cur : null));
      setLoaded(true);
    } catch (e) {
      setError((e as Error).message ?? '불러오지 못했어요');
      setLoaded(true);
    }
  };
  useFocusEffect(useCallback(() => { load(); }, []));

  const pickPhoto = async () => {
    // 지연 로드 — 네이티브 모듈 없는 빌드에서 앱 전체가 죽지 않게 (my.tsx 선례)
    let ImagePicker: any;
    try { ImagePicker = require('expo-image-picker'); }
    catch { Alert.alert('개발 빌드 업데이트 필요', '사진 첨부는 새 빌드에 포함돼요'); return; }
    try {
      const perm = await ImagePicker.requestMediaLibraryPermissionsAsync();
      if (!perm.granted) { Alert.alert('사진 접근 권한이 필요해요'); return; }
      const res = await ImagePicker.launchImageLibraryAsync({ mediaTypes: ['images'], quality: 0.7, base64: true });
      if (res.canceled || !res.assets?.[0]?.base64) return;
      setPhoto(res.assets[0].base64);
    } catch (e) { Alert.alert('사진을 불러오지 못했어요', (e as Error).message); }
  };

  const submit = async () => {
    if (busy) return;
    // 자유 포스트 — 러닝을 첨부하지 않은 경우. 예전엔 불가능했던 경로다.
    if (!sel) {
      if (!caption.trim() && !photo) { Alert.alert('사진이나 글을 남겨주세요'); return; }
      setBusy(true);
      try {
        await createFreePost(caption, photo);
        haptic('light');
        router.replace('/community');
      } catch (e) {
        Alert.alert('올리지 못했어요', (e as Error).message);
      } finally { setBusy(false); }
      return;
    }
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
        <Pressable onPress={goBackOrHome} style={s.backBtn} accessibilityRole="button" accessibilityLabel="뒤로">
          <Text style={{ fontSize: 20.5, color: paper.ink }}>‹</Text>
        </Pressable>
        <Text style={{ fontSize: 23, fontWeight: '900', color: paper.ink }}>피드 자랑하기</Text>
        <View style={{ width: 40 }} />
      </Row>
      <Text style={{ fontSize: 14.5, lineHeight: 20, color: paper.dim, textAlign: 'center', marginTop: 6 }}>
        사진이든 글이든 자유롭게 — 러닝 기록은 원하면 함께 붙여요
      </Text>

      {/* ───── 항상 먼저 오는 것: 글 + 사진. 러닝이 없어도 올릴 수 있다 (Sean 2026-08-12) ───── */}
      <TextInput
        value={caption}
        onChangeText={setCaption}
        placeholder="무슨 일이 있었나요?"
        placeholderTextColor={paper.faint}
        style={[s.captionInput, { marginTop: 16, minHeight: 96 }]}
        multiline
        maxLength={300}
      />
      {photo ? (
        <View style={{ marginTop: 10 }}>
          <Image source={{ uri: `data:image/jpeg;base64,${photo}` }} style={s.photoPreview} resizeMode="cover" />
          <PaperBtn label="사진 빼기" variant="secondary" onPress={() => setPhoto(null)} style={{ marginTop: 8 }} />
        </View>
      ) : (
        <PaperBtn label="사진 추가" variant="secondary" onPress={pickPhoto} style={{ marginTop: 10 }} />
      )}

      {/* 러닝 첨부 — 선택. 접혀 있고, 완료된 러닝이 있을 때만 문이 열린다.
          붙이면 서버가 그 러닝이 내 것인지 확인한다 (0074) — 기록은 달린 사람만. */}
      {loaded && error == null && shareable.length > 0 && (
        <Pressable onPress={() => setAttachOpen((v) => !v)} style={s.attachBar} accessibilityRole="button">
          <Text style={{ flex: 1, fontSize: 15, fontWeight: '800', color: paper.ink }}>
            {sel ? '러닝 기록 첨부됨' : '러닝 기록 붙이기 (선택)'}
          </Text>
          <Text style={{ fontSize: 19, color: paper.dim }}>{attachOpen ? '⌄' : '›'}</Text>
        </Pressable>
      )}
      {sel && !attachOpen && (
        <Pressable onPress={() => setSel(null)} style={{ minHeight: 44, justifyContent: 'center' }} accessibilityRole="button">
          <Text style={{ fontSize: 14, fontWeight: '800', color: paper.actionInk }}>첨부 빼기</Text>
        </Pressable>
      )}

      <PaperBtn
        label="올리기"
        busyLabel="올리는 중..."
        busy={busy}
        disabled={!caption.trim() && !photo && !sel}
        onPress={submit}
        style={{ marginTop: 14 }}
      />

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

      {loaded && error == null && cands.length === 0 && attachOpen && (
        <View style={s.emptyBox}>
          <Text style={{ fontSize: 15, fontWeight: '700', color: paper.ink, textAlign: 'center' }}>아직 붙일 러닝 기록이 없어요</Text>
          <Text style={{ fontSize: 14.5, color: paper.dim, textAlign: 'center', marginTop: 6, lineHeight: 21 }}>
            글과 사진은 지금도 올릴 수 있어요{'\n'}러닝이 끝나면 기록도 함께 붙일 수 있어요
          </Text>
          <PaperBtn
            label={session.role === 'runner' ? '내 캘린더 보기' : '내 일정 보기'}
            variant="secondary"
            onPress={() => router.push(session.role === 'runner' ? '/runner/calendar' : '/owner/schedule')}
            style={{ marginTop: 14 }}
          />
        </View>
      )}

      {loaded && error == null && cands.length > 0 && attachOpen && (
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
            /* [R4 · Sean round 5: "it looks just like an excel block, nothing more" → round 6
                pick ⓑ 도장 칸, docs/labs/club-v2-setup-lab.html:444-475] The bordered box per row
                is gone. What remains is the doc grammar: ink rules between rows, and an empty
                dashed square that asks to be stamped — the pick fills it solid ink and underlines
                its label in the accent. Two boxes abutting was the shape that read as a
                spreadsheet; a rule is not a box.
                The coral that used to signal "chosen" (border + wash) leaves with it — coral is
                the screen's CTA colour and it was spending it on a list row. */
            <View style={s.stamps}>
              {shareable.map((c, i) => {
                const on = sel === c.bookingId;
                return (
                  <Pressable
                    key={c.bookingId}
                    onPress={() => setSel(c.bookingId)}
                    style={({ pressed }) => [
                      s.scell,
                      i === shareable.length - 1 && s.scellLast,
                      pressed && s.scellPressed,
                    ]}
                    accessibilityRole="radio"
                    accessibilityState={{ selected: on, checked: on }}
                  >
                    <View style={[s.sbox, on && s.sboxOn]}>
                      {on && <Text style={s.sboxTick}>✓</Text>}
                    </View>
                    <View style={{ flex: 1, minWidth: 0 }}>
                      <Row style={{ gap: 6, alignItems: 'center' }}>
                        {c.collar && collarColors[c.collar as CollarKey] && (
                          <View style={{ width: 9, height: 9, borderRadius: 4.5, backgroundColor: collarColors[c.collar as CollarKey] }} />
                        )}
                        {/* the underline is the pick's second signal; it hugs the label, so the
                            wrapper shrinks to content rather than ruling the whole row. */}
                        <View style={[s.slWrap, on && s.slWrapOn]}>
                          <Text style={[s.sl, on && s.slOn]} numberOfLines={1}>
                            {c.dogName} · <Text style={nf}>{c.km}</Text>km 완주
                          </Text>
                        </View>
                      </Row>
                      <Text style={s.ss} numberOfLines={1}>{c.when}</Text>
                    </View>
                  </Pressable>
                );
              })}
            </View>
          )}

          {shareable.length > 0 && (
            <Text style={{ fontSize: 14, color: paper.dim, marginTop: 10, lineHeight: 19 }}>
              러닝을 붙이면 인증샷과 거리·시간 기록이 함께 실려요
            </Text>
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
  photoPreview: { width: '100%', aspectRatio: 4 / 5, backgroundColor: paper.disabledFill, borderWidth: 1, borderColor: '#EEEEEE' },
  attachBar: {
    flexDirection: 'row', alignItems: 'center', marginTop: 14, minHeight: 48,
    borderTopWidth: 1, borderBottomWidth: 1, borderColor: paper.line, paddingHorizontal: 2,
  },
  backBtn: {
    width: 40, height: 40, backgroundColor: paper.canvas, alignItems: 'center', justifyContent: 'center',
    borderWidth: 1, borderColor: paper.line,
  },
  kicker: { fontSize: 12, fontWeight: '600', letterSpacing: 2, color: paper.faint, textTransform: 'uppercase' },
  kickerRule: { flex: 1, height: 1, backgroundColor: '#EEEEEE' },

  emptyBox: { backgroundColor: paper.canvas, borderWidth: 1, borderColor: '#EEEEEE', padding: 20, marginTop: 20 },
  // 라우드-페일 스트립 — criticalWash 바닥 + critical 잉크 (코랄 line과 절대 공유 금지)
  failStrip: { backgroundColor: paper.criticalWash, padding: 14, marginTop: 20 },

  // ── 런 픽커 — ⓑ 도장 칸 (Sean round-6 pick; lab club-v2-setup-lab.html:224-236) ──
  // 상자가 없다. 행 사이의 잉크 룰과, 채워달라고 말하는 빈 점선 네모가 상태를 진다.
  // 새 헥스 0개: #EEEEEE(뉴트럴 카드 선)·paper.faint·paper.ink·lilac.accent — 전부 이미 출하 중인 값이다.
  stamps: { marginTop: 2 },
  scell: {
    flexDirection: 'row', alignItems: 'flex-start', gap: 13,
    paddingVertical: 14, paddingHorizontal: 2,
    borderTopWidth: 1, borderTopColor: '#EEEEEE', backgroundColor: paper.canvas,
  },
  scellLast: { borderBottomWidth: 1, borderBottomColor: '#EEEEEE' },
  // 눌림은 명시 색으로 — 알파 트릭 금지. 워시는 코랄이므로 중립 회색을 쓴다.
  scellPressed: { backgroundColor: '#FAFAFA' },
  // ⚠ 점선 테두리는 paper.faint(#999999, 흰 바탕 2.85:1)다. 처음 쓴 #DDDDDD는 1.3:1로,
  // '채워달라고 말하는 빈 네모'가 보이지 않으면 그 말을 못 한다 — 조용한 것과 안 보이는 것은 다르다.
  sbox: {
    width: 26, height: 26, borderWidth: 1.5, borderStyle: 'dashed', borderColor: paper.faint,
    backgroundColor: paper.canvas, alignItems: 'center', justifyContent: 'center', marginTop: 1,
  },
  sboxOn: { borderStyle: 'solid', borderColor: paper.ink, backgroundColor: paper.ink },
  sboxTick: { fontSize: 15, lineHeight: 19, fontWeight: '800', color: '#FFFFFF' },
  // 라벨 래퍼 = 밑줄의 폭. shrink로 내용에 붙는다 (룰이 행 전체를 긋지 않게).
  slWrap: { flexShrink: 1, borderBottomWidth: 2, borderBottomColor: 'transparent', paddingBottom: 2 },
  slWrapOn: { borderBottomColor: lilac.accent },
  // ⚠ lineHeight는 명시다 — Oswald 숫자(nf)가 이 Text 안에 들어온다 (BUG A: 명시 없으면 어센더가 잘린다).
  sl: { fontSize: 15.5, lineHeight: 21, fontWeight: '800', color: paper.text },
  slOn: { color: paper.ink },
  ss: { fontSize: 15, lineHeight: 20, color: paper.dim, marginTop: 5 },

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
