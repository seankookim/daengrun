import { router, useLocalSearchParams } from 'expo-router';
import { useEffect, useRef, useState } from 'react';
import { Alert, Image, KeyboardAvoidingView, Platform, Pressable, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { Monogram, Row } from '../src/components/ui';
import {
  ChatContext, ChatMsg, fetchCurrentOwnerBookingId, fetchCurrentRunnerJobId,
  fetchMessages, openChatForBooking, sendChatMessage, sendChatPhoto, subscribeMessages,
} from '../src/lib/api';
import { supabase } from '../src/lib/supabase';
import { session } from '../src/store';
import { colors } from '../src/theme';

// 채팅 — 예약당 스레드 1개, Supabase Realtime 실배달.
// 진입: 위젯·일정 시트·미트업의 채팅 버튼(bid 전달) 또는 역할별 진행 중 예약 자동 해석.

const FOREST = '#132117';

const QUICK = ['네 좋아요!', '조금 늦을 것 같아요', '지금 어디쯤이세요?', '사진 부탁드려요'];

export default function Chat() {
  const { bid } = useLocalSearchParams<{ bid?: string }>();
  const isRunner = session.role === 'runner';
  const [ctx, setCtx] = useState<ChatContext | null>(null);
  const [state, setState] = useState<'loading' | 'ready' | 'none' | 'error'>('loading');
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
        console.warn('[chat] open:', (e as Error)?.message);
        if (alive) setState('error');
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
        <Pressable onPress={() => router.back()} style={s.circleBtn}><Text style={{ fontSize: 18 }}>‹</Text></Pressable>
        <Monogram char={(ctx?.peerName ?? '·')[0]} bg={isRunner ? '#c9a86e' : '#5a7a3c'} size={40} />
        <View style={{ flex: 1, marginLeft: 10 }}>
          <Text style={{ fontSize: 15, fontWeight: '900', color: FOREST }}>{ctx?.peerName ?? '채팅'}</Text>
          <Text style={{ fontSize: 10.5, color: colors.dim, marginTop: 1 }}>
            {state === 'ready' ? '● 실시간 연결됨' : state === 'loading' ? '연결 중...' : ''}
          </Text>
        </View>
        <Pressable style={s.circleBtn} onPress={() => Alert.alert('안심 통화', '번호 노출 없는 안심 통화로 연결돼요 (준비 중)')}>
          <Text style={{ fontSize: 14, color: '#5a7a3c' }}>✆</Text>
        </Pressable>
      </Row>

      {/* booking context strip */}
      {ctx && (
        <View style={s.contextStrip}>
          <Text style={{ fontSize: 11, fontWeight: '700', color: '#3d5a2b' }}>{ctx.label}</Text>
        </View>
      )}

      {/* body */}
      {state === 'none' && (
        <View style={s.emptyWrap}>
          <Text style={{ fontSize: 14, fontWeight: '900', color: FOREST, textAlign: 'center' }}>진행 중인 예약이 없어요</Text>
          <Text style={{ fontSize: 12, color: colors.dim, textAlign: 'center', marginTop: 6, lineHeight: 18 }}>
            채팅은 예약이 생기면 상대방과 자동으로 연결돼요
          </Text>
        </View>
      )}
      {state === 'error' && (
        <View style={s.emptyWrap}>
          <Text style={{ fontSize: 12.5, color: colors.dim, textAlign: 'center' }}>채팅을 불러오지 못했어요 — 잠시 후 다시 시도해주세요</Text>
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
            <Text style={{ fontSize: 12, color: colors.dim, textAlign: 'center', marginTop: 20 }}>
              첫 메시지를 보내보세요 — 픽업 장소나 아이 성향을 미리 나누면 좋아요
            </Text>
          )}
          {msgs.map((m) => (
            <View key={m.id} style={[s.bubbleRow, m.mine && { justifyContent: 'flex-end' }]}>
              {m.mine && <Text style={s.time}>{m.when}</Text>}
              <View style={[s.bubble, m.mine ? s.bubbleMine : s.bubblePeer, m.mediaUrl != null && { padding: 4 }]}>
                {m.mediaUrl ? (
                  <Image source={{ uri: m.mediaUrl }} style={{ width: 190, height: 190, borderRadius: 14 }} resizeMode="cover" />
                ) : (
                  <Text style={{ fontSize: 13.5, lineHeight: 19, color: m.mine ? FOREST : '#2c332c' }}>{m.body}</Text>
                )}
              </View>
              {!m.mine && <Text style={s.time}>{m.when}</Text>}
            </View>
          ))}
          {msgs.length > 0 && (
            <Text style={{ fontSize: 10, color: colors.dim, textAlign: 'center', marginTop: 8 }}>
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
              <Text style={{ fontSize: 12, fontWeight: '700', color: '#3d453d' }}>{q}</Text>
            </Pressable>
          ))}
        </ScrollView>
      )}

      {/* input bar */}
      <Row style={s.inputBar}>
        <Pressable style={s.attach} onPress={sendPhoto} disabled={state !== 'ready'}>
          <Text style={{ fontSize: 15, color: state === 'ready' ? '#5a7a3c' : colors.dim }}>▣</Text>
        </Pressable>
        <TextInput
          style={s.input}
          value={input}
          onChangeText={setInput}
          placeholder={state === 'ready' ? '메시지 보내기' : '연결 중...'}
          placeholderTextColor="#a9a795"
          editable={state === 'ready'}
          onSubmitEditing={() => send(input)}
          returnKeyType="send"
        />
        <Pressable style={[s.sendBtn, (sending || state !== 'ready') && { opacity: 0.5 }]} onPress={() => send(input)}>
          <Text style={{ fontSize: 15, fontWeight: '900', color: FOREST }}>↑</Text>
        </Pressable>
      </Row>
    </KeyboardAvoidingView>
  );
}

const s = StyleSheet.create({
  header: { paddingTop: 56, paddingHorizontal: 18, paddingBottom: 12, gap: 10, backgroundColor: colors.cream, borderBottomWidth: 1, borderBottomColor: '#dedacb' },
  circleBtn: { width: 40, height: 40, borderRadius: 20, backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: '#dedacb' },
  contextStrip: { backgroundColor: '#eef4e0', paddingVertical: 8, paddingHorizontal: 18 },
  emptyWrap: { flex: 1, justifyContent: 'center', padding: 30 },
  bubbleRow: { flexDirection: 'row', alignItems: 'flex-end', gap: 6 },
  bubble: { maxWidth: '76%', borderRadius: 18, paddingVertical: 10, paddingHorizontal: 14 },
  bubblePeer: { backgroundColor: '#fff', borderWidth: 1, borderColor: '#dedacb', borderBottomLeftRadius: 6 },
  bubbleMine: { backgroundColor: colors.volt, borderBottomRightRadius: 6 },
  time: { fontSize: 9, color: colors.dim, marginBottom: 3 },
  quick: { backgroundColor: '#fff', borderRadius: 99, paddingVertical: 9, paddingHorizontal: 14, borderWidth: 1, borderColor: '#dedacb', alignSelf: 'center' },
  inputBar: { padding: 14, paddingBottom: 30, gap: 8, backgroundColor: colors.cream },
  attach: { width: 38, height: 38, borderRadius: 19, backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: '#dedacb' },
  input: { flex: 1, backgroundColor: '#fff', borderRadius: 22, paddingHorizontal: 16, paddingVertical: 11, fontSize: 14, borderWidth: 1, borderColor: '#dedacb', color: FOREST },
  sendBtn: { width: 42, height: 42, borderRadius: 21, backgroundColor: colors.volt, alignItems: 'center', justifyContent: 'center' },
});
