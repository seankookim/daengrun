import { router, useLocalSearchParams } from 'expo-router';
import { useEffect, useRef, useState } from 'react';
import { Alert, Image, KeyboardAvoidingView, Platform, Pressable, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { Icon, Monogram, Row } from '../src/components/ui';
import { MediaImage } from '../src/lib/media';
import {
  ChatContext, ChatMsg, fetchCurrentOwnerBookingId, fetchCurrentRunnerJobId,
  fetchMessages, openChatForBooking, sendChatMessage, sendChatPhoto, subscribeMessages,
} from '../src/lib/api';
import { supabase } from '../src/lib/supabase';
import { session } from '../src/store';
import { colors, paper } from '../src/theme';

// 채팅 — 예약당 스레드 1개, Supabase Realtime 실배달.
// 진입: 위젯·일정 시트·미트업의 채팅 버튼(bid 전달) 또는 역할별 진행 중 예약 자동 해석.

// [2026-08-12 · Sean "remove forest"] 이 파일의 로컬 상수 FOREST = '#0F1D13' 은퇴. 은퇴된 스왈프/포레스트 팔레트의
// 마지막 잔재였고, 12개 파일에 각자 로컬 상수로 복사돼 있었다 (한 값에 주인 12명).
// paper.ink(#111111)로 접는다 — 색차는 사실상 안 보이고(둘 다 근처 검정), 그게 정확히 아무도
// 못 본 이유다. 다크 면에도 같은 토큰을 쓴다 — 캘린더 보드·정산 티켓·빕 스트랩이 이미 그런다.

const QUICK = ['네 좋아요!', '조금 늦을 것 같아요', '지금 어디쯤이세요?', '사진 부탁드려요'];

export default function Chat() {
  const { bid } = useLocalSearchParams<{ bid?: string }>();
  const isRunner = session.role === 'runner';
  const [ctx, setCtx] = useState<ChatContext | null>(null);
  // 'preaccept' = 서버가 **설계상** 거부한 상태 (0114): 러너가 수락하기 전 예약은
  // chat_threads INSERT가 정책에서 막힌다. 'error'(일시적 실패)와 같은 문장을 쓰면 안 된다 —
  // 기다려도 절대 열리지 않는데 "잠시 후 다시 시도"라고 말하는 건 시간에 대한 거짓말이다.
  const [state, setState] = useState<'loading' | 'ready' | 'none' | 'error' | 'preaccept'>('loading');
  const [msgs, setMsgs] = useState<ChatMsg[]>([]);
  const [input, setInput] = useState('');
  const [sending, setSending] = useState(false);
  const scroller = useRef<ScrollView>(null);

  // 스레드 준비: bid 없으면 진행 중 예약을 서버에서 해석
  useEffect(() => {
    let alive = true;
    (async () => {
      try {
        const bookingId = bid ?? (isRunner ? await fetchCurrentRunnerJobId() : await fetchCurrentOwnerBookingId());
        if (!bookingId) { if (alive) setState('none'); return; }
        const c = await openChatForBooking(bookingId);
        if (!alive) return;
        setCtx(c);
        setMsgs(await fetchMessages(c.threadId));
        setState('ready');
      } catch (e) {
        // [0114 · ui2-2] RLS 거부만 골라낸다. openChatForBooking → ensureThread의 INSERT가
        // is_booking_party_active에 걸리면 PostgREST가 42501 / "row-level security" 를 올린다
        // (docs/contracts/party-membership-status-filter-contract.md §C.3). 그 외의 실패
        // (네트워크·타임아웃·5xx)는 진짜 일시적 실패이므로 종전 재시도 문구를 그대로 쓴다.
        const err = e as { code?: string; message?: string };
        // Measured live shape (0114 probe, docs/security-booking-party-forgery.md): HTTP 403, code "42501",
        // 'new row violates row-level security policy for table "chat_threads"'. The code is the contract;
        // the message test is only a fallback for an SDK that drops the code.
        const denied = err?.code === '42501'
          || /row-level security policy for table "chat_threads"/i.test(err?.message ?? '');
        console.warn('[chat] open:', err?.message);
        if (alive) setState(denied ? 'preaccept' : 'error');
      }
    })();
    return () => { alive = false; };
  }, [bid, isRunner]);

  // 실시간 수신 — 내 발신도 서버 에코로 수신 (중복은 id로 방지)
  useEffect(() => {
    if (!ctx) return;
    let unsub = () => {};
    supabase.auth.getUser().then(({ data }) => {
      unsub = subscribeMessages(ctx.threadId, data.user?.id ?? null, (m) => {
        setMsgs((prev) => (prev.some((x) => x.id === m.id) ? prev : [...prev, m]));
        setTimeout(() => scroller.current?.scrollToEnd({ animated: true }), 60);
      });
    });
    return () => unsub();
  }, [ctx]);

  // 사진 메시지 — 픽업 장소·아이 상태 공유의 핵심 수단
  const sendPhoto = async () => {
    if (!ctx) return;
    let ImagePicker: any;
    try { ImagePicker = require('expo-image-picker'); } catch {
      Alert.alert('개발 빌드 업데이트 필요', '사진 기능은 새 빌드에 포함돼요'); return;
    }
    try {
      const perm = await ImagePicker.requestMediaLibraryPermissionsAsync();
      if (!perm.granted) return;
      const res = await ImagePicker.launchImageLibraryAsync({ mediaTypes: ['images'], quality: 0.6, base64: true });
      if (res.canceled || !res.assets?.[0]?.base64) return;
      await sendChatPhoto(ctx.threadId, res.assets[0].base64);
      setMsgs(await fetchMessages(ctx.threadId));
      setTimeout(() => scroller.current?.scrollToEnd({ animated: true }), 60);
    } catch (e) {
      Alert.alert('전송 실패', (e as Error).message);
    }
  };

  const send = async (body: string) => {
    if (!body.trim() || !ctx || sending) return;
    setSending(true);
    setInput('');
    try {
      await sendChatMessage(ctx.threadId, body.trim());
      // Realtime 에코가 못 오는 경우 대비 — 리페치로 정합
      setMsgs(await fetchMessages(ctx.threadId));
      setTimeout(() => scroller.current?.scrollToEnd({ animated: true }), 60);
    } catch (e) {
      Alert.alert('전송 실패', (e as Error).message);
      setInput(body);
    } finally {
      setSending(false);
    }
  };

  return (
    <KeyboardAvoidingView style={{ flex: 1, backgroundColor: colors.cream }} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
      {/* header */}
      <Row style={s.header}>
        <Pressable onPress={() => router.back()} style={s.circleBtn}><Text style={{ fontSize: 20.5 }}>‹</Text></Pressable>
        <Monogram char={(ctx?.peerName ?? '·')[0]} bg={isRunner ? '#c9a86e' : '#5a7a3c'} size={40} />
        <View style={{ flex: 1, marginLeft: 10 }}>
          <Text style={{ fontSize: 17, fontWeight: '900', color: paper.ink }}>{ctx?.peerName ?? '채팅'}</Text>
          <Text style={{ fontSize: 14, color: colors.dim, marginTop: 1 }}>
            {state === 'ready' ? '● 실시간 연결됨' : state === 'loading' ? '연결 중...' : ''}
          </Text>
        </View>
        <Pressable style={s.circleBtn} onPress={() => Alert.alert('안심 통화', '번호 노출 없는 안심 통화로 연결돼요 (준비 중)')}>
          <Icon name="Phone" glyph="●" size={16} color="#5a7a3c" />
        </Pressable>
      </Row>

      {/* booking context strip */}
      {ctx && (
        <View style={s.contextStrip}>
          <Text style={{ fontSize: 14, fontWeight: '700', color: '#3d5a2b' }}>{ctx.label}</Text>
        </View>
      )}

      {/* body */}
      {state === 'none' && (
        <View style={s.emptyWrap}>
          <Text style={{ fontSize: 16, fontWeight: '900', color: paper.ink, textAlign: 'center' }}>진행 중인 예약이 없어요</Text>
          <Text style={{ fontSize: 14, color: colors.dim, textAlign: 'center', marginTop: 6, lineHeight: 20.5 }}>
            채팅은 예약이 생기면 상대방과 자동으로 연결돼요
          </Text>
        </View>
      )}
      {state === 'preaccept' && (
        <View style={s.emptyWrap}>
          <Text style={{ fontSize: 16, fontWeight: '900', color: paper.ink, textAlign: 'center' }}>러너가 수락하면 채팅을 열 수 있어요</Text>
          <Text style={{ fontSize: 14, color: colors.dim, textAlign: 'center', marginTop: 6, lineHeight: 20.5 }}>
            요청을 수락한 러너와 바로 연결돼요
          </Text>
        </View>
      )}
      {state === 'error' && (
        <View style={s.emptyWrap}>
          <Text style={{ fontSize: 14.5, color: colors.dim, textAlign: 'center' }}>채팅을 불러오지 못했어요 — 잠시 후 다시 시도해주세요</Text>
        </View>
      )}

      {(state === 'ready' || state === 'loading') && (
        <ScrollView
          ref={scroller}
          style={{ flex: 1 }}
          contentContainerStyle={{ padding: 18, gap: 8 }}
          onContentSizeChange={() => scroller.current?.scrollToEnd({ animated: false })}
        >
          {state === 'ready' && msgs.length === 0 && (
            <Text style={{ fontSize: 14, color: colors.dim, textAlign: 'center', marginTop: 20 }}>
              첫 메시지를 보내보세요 — 픽업 장소나 아이 성향을 미리 나누면 좋아요
            </Text>
          )}
          {msgs.map((m) => (
            <View key={m.id} style={[s.bubbleRow, m.mine && { justifyContent: 'flex-end' }]}>
              {m.mine && <Text style={s.time}>{m.when}</Text>}
              <View style={[s.bubble, m.mine ? s.bubbleMine : s.bubblePeer, m.mediaUrl != null && { padding: 4 }]}>
                {m.mediaUrl ? (
                  /* [0064] media_path는 프라이빗 버킷 경로 — MediaImage가 서명 URL로 풀고 만료를 명시 실패로 그린다 */
                  <MediaImage source={m.mediaUrl} style={{ width: 190, height: 190, borderRadius: 14 }} resizeMode="cover" />
                ) : (
                  <Text style={{ fontSize: 15.5, lineHeight: 22, color: m.mine ? paper.ink : '#2c332c' }}>{m.body}</Text>
                )}
              </View>
              {!m.mine && <Text style={s.time}>{m.when}</Text>}
            </View>
          ))}
          {msgs.length > 0 && (
            <Text style={{ fontSize: 14, color: colors.dim, textAlign: 'center', marginTop: 8 }}>
              안전을 위해 모든 대화는 러닝 종료 후 30일간 보관돼요
            </Text>
          )}
        </ScrollView>
      )}

      {/* quick replies */}
      {state === 'ready' && (
        <ScrollView horizontal showsHorizontalScrollIndicator={false} style={{ maxHeight: 46 }} contentContainerStyle={{ gap: 8, paddingHorizontal: 18 }}>
          {QUICK.map((q) => (
            <Pressable key={q} style={s.quick} onPress={() => send(q)}>
              <Text style={{ fontSize: 14, fontWeight: '700', color: '#3d453d' }}>{q}</Text>
            </Pressable>
          ))}
        </ScrollView>
      )}

      {/* input bar */}
      <Row style={s.inputBar}>
        <Pressable style={s.attach} onPress={sendPhoto} disabled={state !== 'ready'}>
          <Text style={{ fontSize: 17, color: state === 'ready' ? '#5a7a3c' : colors.dim }}>▣</Text>
        </Pressable>
        <TextInput
          style={s.input}
          value={input}
          onChangeText={setInput}
          /* 플레이스홀더도 같은 법을 진다 — 수락 전 상태에서 '연결 중...'은 열릴 예정이 없는
             연결을 기다리라는 말이 된다 */
          placeholder={state === 'ready' ? '메시지 보내기' : state === 'preaccept' ? '수락 후 열려요' : '연결 중...'}
          placeholderTextColor="#a9a795"
          editable={state === 'ready'}
          onSubmitEditing={() => send(input)}
          returnKeyType="send"
        />
        <Pressable style={[s.sendBtn, (sending || state !== 'ready') && { opacity: 0.5 }]} onPress={() => send(input)}>
          <Text style={{ fontSize: 17, fontWeight: '900', color: paper.ink }}>↑</Text>
        </Pressable>
      </Row>
    </KeyboardAvoidingView>
  );
}

const s = StyleSheet.create({
  header: { paddingTop: 56, paddingHorizontal: 18, paddingBottom: 12, gap: 10, backgroundColor: colors.cream, borderBottomWidth: 1, borderBottomColor: '#DCD6C4' },
  circleBtn: { width: 40, height: 40, borderRadius: 20, backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: '#DCD6C4' },
  contextStrip: { backgroundColor: '#eef4e0', paddingVertical: 8, paddingHorizontal: 18 },
  emptyWrap: { flex: 1, justifyContent: 'center', padding: 30 },
  bubbleRow: { flexDirection: 'row', alignItems: 'flex-end', gap: 6 },
  bubble: { maxWidth: '76%', borderRadius: 18, paddingVertical: 10, paddingHorizontal: 14 },
  bubblePeer: { backgroundColor: '#fff', borderWidth: 1, borderColor: '#DCD6C4', borderBottomLeftRadius: 6 },
  bubbleMine: { backgroundColor: colors.volt, borderBottomRightRadius: 6 },
  time: { fontSize: 14, color: colors.dim, marginBottom: 3 },
  quick: { backgroundColor: '#fff', borderRadius: 99, paddingVertical: 9, paddingHorizontal: 14, borderWidth: 1, borderColor: '#DCD6C4', alignSelf: 'center' },
  inputBar: { padding: 14, paddingBottom: 30, gap: 8, backgroundColor: colors.cream },
  attach: { width: 38, height: 38, borderRadius: 19, backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: '#DCD6C4' },
  input: { flex: 1, backgroundColor: '#fff', borderRadius: 22, paddingHorizontal: 16, paddingVertical: 11, fontSize: 16, borderWidth: 1, borderColor: '#DCD6C4', color: paper.ink },
  sendBtn: { width: 42, height: 42, borderRadius: 21, backgroundColor: colors.volt, alignItems: 'center', justifyContent: 'center' },
});
