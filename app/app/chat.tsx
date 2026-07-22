import { router } from 'expo-router';
import { useRef, useState } from 'react';
import { Alert, KeyboardAvoidingView, Platform, Pressable, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { Monogram, Row } from '../src/components/ui';
import { dog, session } from '../src/store';
import { colors } from '../src/theme';

// 채팅 — role-aware thread (owner ↔ runner). Realtime later via Supabase.

const FOREST = '#132117';

interface Msg { id: number; mine: boolean; text: string; time: string }

const SEED: Msg[] = [
  { id: 1, mine: false, text: '안녕하세요! 오늘 6:30 초코 러닝 맡은 김민준입니다 :)', time: '오후 3:02' },
  { id: 2, mine: true, text: '안녕하세요! 잘 부탁드려요', time: '오후 3:05' },
  { id: 3, mine: true, text: '자전거도로만 피해주시면 돼요! 초코가 자전거 보면 짖어서요', time: '오후 3:05' },
  { id: 4, mine: false, text: '네 메모 확인했어요. 서울숲 순환 코스는 자전거도로랑 완전 분리돼 있어서 안심하셔도 돼요', time: '오후 3:07' },
  { id: 5, mine: false, text: '물은 30분마다 챙길게요. 6:25쯤 2번 출입구 도착 예정입니다', time: '오후 3:08' },
];

const QUICK = ['네 좋아요!', '조금 늦을 것 같아요', '지금 어디쯤이세요?', '사진 부탁드려요'];

export default function Chat() {
  const isRunner = session.role === 'runner';
  const peer = isRunner
    ? { name: `${dog.name} 보호자님`, char: dog.name[0], color: '#c9a86e', sub: '응답 빠름' }
    : { name: '김민준 러너', char: '민', color: '#FF6347', sub: '신원인증 · 보통 5분 내 응답' };

  const [msgs, setMsgs] = useState<Msg[]>(SEED);
  const [input, setInput] = useState('');
  const scroller = useRef<ScrollView>(null);

  const send = (text: string) => {
    if (!text.trim()) return;
    setMsgs((m) => [...m, { id: m.length + 1, mine: true, text: text.trim(), time: '지금' }]);
    setInput('');
    setTimeout(() => scroller.current?.scrollToEnd({ animated: true }), 60);
  };

  return (
    <KeyboardAvoidingView style={{ flex: 1, backgroundColor: colors.cream }} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
      {/* header */}
      <Row style={s.header}>
        <Pressable onPress={() => router.back()} style={s.circleBtn}><Text style={{ fontSize: 18 }}>‹</Text></Pressable>
        <Monogram char={peer.char} bg={peer.color} size={40} />
        <View style={{ flex: 1, marginLeft: 10 }}>
          <Text style={{ fontSize: 15, fontWeight: '900', color: FOREST }}>{peer.name}</Text>
          <Text style={{ fontSize: 10.5, color: colors.dim, marginTop: 1 }}>{peer.sub}</Text>
        </View>
        <Pressable style={s.circleBtn} onPress={() => Alert.alert('안심 통화', '번호 노출 없는 안심 통화로 연결돼요 (목업)')}>
          <Text style={{ fontSize: 14, color: '#5a7a3c' }}>✆</Text>
        </Pressable>
      </Row>

      {/* booking context strip */}
      <View style={s.contextStrip}>
        <Text style={{ fontSize: 11, fontWeight: '700', color: '#3d5a2b' }}>
          오늘 오후 6:30 · {dog.name} · 서울숲 순환 코스 5km · 서울숲 2번 출입구
        </Text>
      </View>

      {/* messages */}
      <ScrollView
        ref={scroller}
        style={{ flex: 1 }}
        contentContainerStyle={{ padding: 18, gap: 8 }}
        onContentSizeChange={() => scroller.current?.scrollToEnd({ animated: false })}
      >
        {msgs.map((m) => (
          <View key={m.id} style={[s.bubbleRow, m.mine && { justifyContent: 'flex-end' }]}>
            <View style={[s.bubble, m.mine ? s.bubbleMine : s.bubblePeer]}>
              <Text style={{ fontSize: 13.5, lineHeight: 19, color: m.mine ? FOREST : '#2c332c' }}>{m.text}</Text>
            </View>
            <Text style={s.time}>{m.time}</Text>
          </View>
        ))}
        <Text style={{ fontSize: 10, color: colors.dim, textAlign: 'center', marginTop: 8 }}>
          안전을 위해 모든 대화는 러닝 종료 후 30일간 보관돼요
        </Text>
      </ScrollView>

      {/* quick replies */}
      <ScrollView horizontal showsHorizontalScrollIndicator={false} style={{ maxHeight: 46 }} contentContainerStyle={{ gap: 8, paddingHorizontal: 18 }}>
        {QUICK.map((q) => (
          <Pressable key={q} style={s.quick} onPress={() => send(q)}>
            <Text style={{ fontSize: 12, fontWeight: '700', color: '#3d453d' }}>{q}</Text>
          </Pressable>
        ))}
      </ScrollView>

      {/* input bar */}
      <Row style={s.inputBar}>
        <Pressable style={s.attach} onPress={() => Alert.alert('사진', '사진 첨부 (목업)')}>
          <Text style={{ fontSize: 15, color: colors.dim }}>▣</Text>
        </Pressable>
        <Pressable style={s.attach} onPress={() => Alert.alert('위치', '현재 위치 공유 (목업)')}>
          <Text style={{ fontSize: 15, color: colors.dim }}>⌖</Text>
        </Pressable>
        <TextInput
          style={s.input}
          value={input}
          onChangeText={setInput}
          placeholder="메시지 보내기"
          placeholderTextColor="#a9a795"
          onSubmitEditing={() => send(input)}
          returnKeyType="send"
        />
        <Pressable style={s.sendBtn} onPress={() => send(input)}>
          <Text style={{ fontSize: 15, fontWeight: '900', color: FOREST }}>↑</Text>
        </Pressable>
      </Row>
    </KeyboardAvoidingView>
  );
}

const s = StyleSheet.create({
  header: { paddingTop: 56, paddingHorizontal: 18, paddingBottom: 12, gap: 10, backgroundColor: colors.cream, borderBottomWidth: 1, borderBottomColor: '#eceadf' },
  circleBtn: { width: 40, height: 40, borderRadius: 20, backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: '#eceadf' },
  contextStrip: { backgroundColor: '#eef4e0', paddingVertical: 8, paddingHorizontal: 18 },
  bubbleRow: { flexDirection: 'row', alignItems: 'flex-end', gap: 6 },
  bubble: { maxWidth: '76%', borderRadius: 18, paddingVertical: 10, paddingHorizontal: 14 },
  bubblePeer: { backgroundColor: '#fff', borderWidth: 1, borderColor: '#eceadf', borderBottomLeftRadius: 6 },
  bubbleMine: { backgroundColor: colors.volt, borderBottomRightRadius: 6 },
  time: { fontSize: 9, color: colors.dim, marginBottom: 3 },
  quick: { backgroundColor: '#fff', borderRadius: 99, paddingVertical: 9, paddingHorizontal: 14, borderWidth: 1, borderColor: '#eceadf', alignSelf: 'center' },
  inputBar: { padding: 14, paddingBottom: 30, gap: 8, backgroundColor: colors.cream },
  attach: { width: 38, height: 38, borderRadius: 19, backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: '#eceadf' },
  input: { flex: 1, backgroundColor: '#fff', borderRadius: 22, paddingHorizontal: 16, paddingVertical: 11, fontSize: 14, borderWidth: 1, borderColor: '#eceadf', color: FOREST },
  sendBtn: { width: 42, height: 42, borderRadius: 21, backgroundColor: colors.volt, alignItems: 'center', justifyContent: 'center' },
});
