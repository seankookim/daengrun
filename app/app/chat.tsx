import { useLocalSearchParams } from 'expo-router';
import { useEffect, useRef, useState } from 'react';
import { Alert, Image, KeyboardAvoidingView, Platform, Pressable, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { Monogram, Row } from '../src/components/ui';
import { mergeMessageSnapshot } from '../src/lib/chat-messages';
import { MediaImage } from '../src/lib/media';
import { goBackOrHome } from '../src/lib/nav';
import {
  ChannelLink, ChatContext, ChatMsg, fetchCurrentOwnerBookingId, fetchCurrentRunnerJobId,
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
  const [loadAttempt, setLoadAttempt] = useState(0);
  const scroller = useRef<ScrollView>(null);
  const mounted = useRef(false);
  // [codex r3-14] 이벤트 핸들러(send/sendPhoto)의 await 뒤 쓰기는 mounted만으로 부족하다 —
  // bid가 바뀌어도 mounted는 참이라, A 스레드의 늦은 스냅샷·전송 실패·sending 해제가 전부 B에
  // 떨어졌다(세 effect는 alive 클로저로 이미 올바른데 핸들러 둘만 마운트 가드였다). 작업 시작
  // 시점의 ctx를 붙들고, 현재 ctx와 다르면 버린다.
  const ctxRef = useRef<ChatContext | null>(null);
  useEffect(() => { ctxRef.current = ctx; }, [ctx]);
  // [codex r3-13] bid 교체는 초안·전송 플래그도 비운다 — A용 초안이 B 스레드로 전송될 수 있었고,
  // A의 진행 중 전송이 B의 보내기를 막았다. 60행의 공유 리셋 목록에 넣지 않는 이유: 그 목록은
  // loadAttempt(같은 스레드 재시도)에도 돌아, 재시도마다 멀쩡한 초안을 지우게 된다.
  useEffect(() => { setInput(''); setSending(false); }, [bid]);
  // [2026-08-20] 실시간 링크 상태 — 채널의 실제 SUBSCRIBED에서만 온다 (api.ts subscribeMessages의
  // onLink). 예전엔 헤더가 `state === 'ready'`(= 메시지 fetch 성공)를 근거로 「● 실시간 연결됨」을
  // 찍었다: 서버가 프라이빗 채널을 거절하거나 조인이 타임아웃해도 화면은 연결됐다고 말했고,
  // 인계 중인 러너의 「5분 늦어요」는 영영 오지 않았다. 검증하지 않은 연결은 주장하지 않는다.
  const [link, setLink] = useState<ChannelLink>('connecting');
  // 폴백 폴링까지 실패한 상태 — 실시간이 끊긴 것과 **메시지가 아예 안 들어오는 것**은 다른 사실이라
  // 채널도 다르다. 아래 헤더가 이 둘을 다른 문장으로 말한다.
  const [pollErr, setPollErr] = useState(false);

  useEffect(() => {
    mounted.current = true;
    return () => { mounted.current = false; };
  }, []);

  // 스레드 준비: bid 없으면 진행 중 예약을 서버에서 해석
  useEffect(() => {
    let alive = true;
    // [codex 2026-08-31 r2-F5] bid가 바뀐 채 재실행되면 이전 스레드의 ctx·메시지가 새 스레드에
    // 합류했다(머지가 합집합이라 A의 말풍선이 B 아래 남는다) — 진입마다 스레드 중립 상태로
    // 되돌린다. retryLoad와 같은 리셋 목록이어야 한다: 하나가 늘면 둘 다 늘어야 한다.
    setCtx(null); setMsgs([]); setLink('connecting'); setPollErr(false); setState('loading');
    (async () => {
      try {
        const bookingId = bid ?? (isRunner ? await fetchCurrentRunnerJobId() : await fetchCurrentOwnerBookingId());
        if (!alive) return;
        if (!bookingId) { if (alive) setState('none'); return; }
        const c = await openChatForBooking(bookingId);
        if (!alive) return;
        const history = await fetchMessages(c.threadId);
        if (!alive) return;
        setCtx(c);
        setMsgs((current) => mergeMessageSnapshot(current, history));
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
  }, [bid, isRunner, loadAttempt]);

  // 실시간 수신 — 내 발신도 서버 에코로 수신 (중복은 id로 방지)
  // [leak 2026-08-20] alive 가드가 없었다. cleanup이 `unsub` 초기값(빈 함수)을 실행한 뒤에
  // getUser()가 resolve하면 **구독이 그때 붙어 버리고 해제할 주인이 없다**: 리스너가 영원히 남아
  // sharedWatchers가 0에 도달하지 못하고(채널이 프로세스 수명 내내 조인 상태), 메시지가 올 때마다
  // 언마운트된 컴포넌트에서 setMsgs가 돈다. 헤더의 상대 이름이 왕복 뒤에야 뜨는 화면이라 유저는
  // 여기서 자주 튕겨 나가고, 그래서 누수가 쌓인다. 관용구는 runner/meetup.tsx:122-129와 동일.
  useEffect(() => {
    if (!ctx) return;
    let alive = true;
    let unsub: (() => void) | null = null;
    supabase.auth.getUser().then(({ data, error }) => {
      if (!alive) return; // 왕복 도중 언마운트 — 구독 자체를 열지 않는다
      // UID 없는 구독은 내 에코를 상대 메시지로 그린다. 인증 실패는 폴백 fetch와 똑같이
      // 라우드하게 두고, 잘못된 발신자 표시는 만들지 않는다.
      if (error || !data.user) {
        console.warn('[chat] subscribe auth:', error?.message ?? 'not signed in');
        setLink('error');
        setPollErr(true);
        return;
      }
      unsub = subscribeMessages(ctx.threadId, data.user.id, (m) => {
        setMsgs((prev) => mergeMessageSnapshot([...prev.filter((x) => x.id !== m.id), m], []));
        setTimeout(() => scroller.current?.scrollToEnd({ animated: true }), 60);
      }, (s) => { if (alive) setLink(s); });
    }, (error) => {
      if (!alive) return;
      console.warn('[chat] subscribe auth:', (error as Error)?.message ?? error);
      setLink('error');
      setPollErr(true);
    });
    return () => { alive = false; unsub?.(); };
  }, [ctx]);

  // [fallback 2026-08-20] 스레드가 열려 있는 동안의 폴백 리페치.
  // 레지스트리의 계약은 "모든 소비처가 폴백 폴링을 유지한다"인데(api.ts subscribeShared 헤더)
  // 채팅에는 그게 **하나도** 없었다 — 인터벌도, 포커스 리페치도. 포커스 리페치만으로는 폴백이
  // 아니다: 그건 화면을 떠났다 돌아올 때만 도는데, 인계 중 두 사람은 화면을 보며 기다린다.
  // 실시간이 살아 있으면 15초(에코가 이미 일을 한다), 죽었거나 확인 전이면 5초.
  useEffect(() => {
    if (!ctx || state !== 'ready') return;
    let alive = true;
    const tick = async () => {
      try {
        const next = await fetchMessages(ctx.threadId);
        if (!alive) return;
        setPollErr(false);
        // mergeMessageSnapshot은 새 ID가 없으면 같은 배열을 돌려준다 — 매 틱 리렌더는
        // 스크롤을 흔들고 이미지 말풍선을 다시 태우므로 상태를 갈지 않는다.
        setMsgs((prev) => mergeMessageSnapshot(prev, next));
      } catch (e) {
        console.warn('[chat] poll:', (e as Error)?.message ?? e);
        if (alive) setPollErr(true); // 조용히 삼키면 헤더가 '받고 있다'고 우긴다
      }
    };
    const t = setInterval(tick, link === 'live' ? 15_000 : 5_000);
    return () => { alive = false; clearInterval(t); };
  }, [ctx, state, link]);

  // 사진 메시지 — 픽업 장소·아이 상태 공유의 핵심 수단
  const sendPhoto = async () => {
    if (!ctx) return;
    const opCtx = ctx; // [r3-14] send()와 같은 정체 게이트
    let ImagePicker: any;
    try { ImagePicker = require('expo-image-picker'); } catch {
      Alert.alert('개발 빌드 업데이트 필요', '사진 기능은 새 빌드에 포함돼요'); return;
    }
    try {
      const perm = await ImagePicker.requestMediaLibraryPermissionsAsync();
      if (!perm.granted) return;
      const res = await ImagePicker.launchImageLibraryAsync({ mediaTypes: ['images'], quality: 0.6, base64: true });
      if (res.canceled || !res.assets?.[0]?.base64) return;
      await sendChatPhoto(opCtx.threadId, res.assets[0].base64);
    } catch (e) {
      if (mounted.current && ctxRef.current === opCtx) Alert.alert('전송 실패', (e as Error).message);
      return;
    }
    // [codex r2-F10] 전송과 리페치는 다른 실패다 — 전송이 이미 커밋된 뒤 리페치가 죽으면
    // 「전송 실패」는 거짓말이고, 다시 보내면 중복이 된다. 리페치 실패는 폴 실패로만 말한다
    // (헤더가 「받지 못하고 있어요」를 맡는다).
    try {
      const snapshot = await fetchMessages(opCtx.threadId);
      if (!mounted.current || ctxRef.current !== opCtx) return;
      setMsgs((current) => mergeMessageSnapshot(current, snapshot));
      setTimeout(() => scroller.current?.scrollToEnd({ animated: true }), 60);
    } catch {
      if (mounted.current && ctxRef.current === opCtx) setPollErr(true);
    }
  };

  const send = async (body: string) => {
    if (!body.trim() || !ctx || sending) return;
    const opCtx = ctx; // [r3-14] 이 작업이 속한 스레드 — 이후의 모든 쓰기는 이 정체로 게이트
    setSending(true);
    setInput('');
    try {
      await sendChatMessage(opCtx.threadId, body.trim());
    } catch (e) {
      // 전송 자체가 실패했을 때만 「전송 실패」+입력 복원 — 커밋된 메시지에 이 말을 하면
      // 재시도가 중복 전송이 된다 (codex r2-F10).
      if (mounted.current && ctxRef.current === opCtx) {
        // [codex r3-15, 클라 절반] INSERT 실패에는 두 종류가 있다: 서버가 거절했다(PostgREST
        // 코드가 실려 온다 — 확실한 실패)와 응답이 사라졌다(네트워크 — 커밋 여부를 **모른다**).
        // 모르는 것을 「전송 실패」로 단정하면 재시도가 중복을 만든다. 완결(멱등 키 컬럼 +
        // unique 인덱스 + 23505→성공 매핑)은 서버 스키마 몫 — 백엔드 큐에 전달됨. 그 전까지
        // 클라가 정직하게 할 수 있는 일: 불확실을 불확실이라 말하고, 목록을 다시 읽어 커밋된
        // 메시지가 있으면 보여준다.
        const code = (e as { code?: string })?.code;
        Alert.alert(
          code ? '전송 실패' : '전송이 확인되지 않았어요',
          code
            ? (e as Error).message
            : '네트워크 문제로 전송 여부를 확인하지 못했어요 — 아래 목록에 방금 메시지가 보이면 다시 보내지 마세요',
        );
        setInput(body);
        setSending(false);
        if (!code) {
          fetchMessages(opCtx.threadId)
            .then((snap) => {
              if (mounted.current && ctxRef.current === opCtx) setMsgs((cur) => mergeMessageSnapshot(cur, snap));
            })
            .catch(() => {});
        }
      }
      return;
    }
    try {
      // Realtime 에코가 못 오는 경우 대비 — 리페치로 정합. 실패는 폴 실패로만.
      const snapshot = await fetchMessages(opCtx.threadId);
      if (!mounted.current || ctxRef.current !== opCtx) return;
      setMsgs((current) => mergeMessageSnapshot(current, snapshot));
      setTimeout(() => scroller.current?.scrollToEnd({ animated: true }), 60);
    } catch {
      if (mounted.current && ctxRef.current === opCtx) setPollErr(true);
    } finally {
      // [r3-14] stale finally가 B의 sending을 풀거나 잠그지 않게 — B의 해제는 bid 효과가 맡는다
      if (mounted.current && ctxRef.current === opCtx) setSending(false);
    }
  };

  const retryLoad = () => {
    setCtx(null);
    setMsgs([]);
    setLink('connecting');
    setPollErr(false);
    setState('loading');
    setLoadAttempt((attempt) => attempt + 1);
  };

  // 보내기가 실제로 할 일이 없는 조건 — send()의 가드와 같은 술어를 버튼이 그대로 입는다.
  const sendBlocked = sending || state !== 'ready' || input.trim().length === 0;

  // 헤더 상태 줄. 세 사실을 뭉개지 않는다:
  //   실시간 조인 성공 = 「● 실시간 연결됨」 (이제 이 문장의 유일한 근거는 SUBSCRIBED다)
  //   실시간은 죽었지만 폴링이 돈다 = 그 사실을 말한다 (메시지는 늦게라도 온다)
  //   실시간도 죽고 폴링도 실패 = critical 잉크의 라우드 페일 (침묵하면 화면이 '받고 있다'고 우긴다)
  // ⚠ 순서가 의미다. 채널이 살아 있으면(link==='live') 폴 실패는 유저에게 아무것도 뜻하지 않는다 —
  // 메시지는 에코로 들어오고 있다. 그때 실패를 외치는 것도 지어낸 주장이다. 폴 실패는 **폴링이
  // 유일한 통로일 때만** 사실이 된다.
  // 문장은 짧게 유지한다 — 이 줄은 모노그램·백버튼과 한 행을 나눠 쓰므로 길어지면 헤더가 2행이 된다.
  const linkLine: { tx: string; bad: boolean } | null =
    state === 'loading' ? { tx: '연결 중...', bad: false }
      : state !== 'ready' ? null
        : link === 'live' ? { tx: '● 실시간 연결됨', bad: false }
          : pollErr ? { tx: '메시지를 못 받고 있어요', bad: true }
            : link === 'connecting' ? { tx: '연결 중...', bad: false }
              : { tx: '실시간 끊김 — 새로고침 중', bad: false };

  return (
    <KeyboardAvoidingView style={{ flex: 1, backgroundColor: colors.cream }} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
      {/* header */}
      <Row style={s.header}>
        <Pressable onPress={goBackOrHome} style={s.circleBtn} accessibilityRole="button" accessibilityLabel="뒤로"><Text style={{ fontSize: 20.5 }}>‹</Text></Pressable>
        <Monogram char={(ctx?.peerName ?? '·')[0]} bg={isRunner ? '#c9a86e' : '#5a7a3c'} size={40} />
        <View style={{ flex: 1, marginLeft: 10 }}>
          <Text style={{ fontSize: 17, fontWeight: '900', color: paper.ink }}>{ctx?.peerName ?? '채팅'}</Text>
          <Text style={{ fontSize: 15, color: linkLine?.bad ? paper.critical : colors.dim, fontWeight: linkLine?.bad ? '700' : '400', marginTop: 1 }}>
            {linkLine?.tx ?? ''}
          </Text>
        </View>
        {/* [dead button 2026-08-19] 안심 통화 버튼 은퇴. 유일한 효과가 "(준비 중)" 알럿이었다 —
            없는 기능을 있는 것처럼 배치한 버튼이고, 그건 이 앱이 금지한 것이다. 번호 마스킹
            연동(PG/통신)이 실제로 붙는 날 같은 자리로 돌아온다. */}
      </Row>

      {/* booking context strip */}
      {ctx && (
        <View style={s.contextStrip}>
          <Text style={{ fontSize: 15, fontWeight: '700', color: '#3d5a2b' }}>{ctx.label}</Text>
        </View>
      )}

      {/* body */}
      {state === 'none' && (
        <View style={s.emptyWrap}>
          <Text style={{ fontSize: 16, fontWeight: '900', color: paper.ink, textAlign: 'center' }}>진행 중인 예약이 없어요</Text>
          <Text style={{ fontSize: 15, color: colors.dim, textAlign: 'center', marginTop: 6, lineHeight: 20.5 }}>
            채팅은 예약이 생기면 상대방과 자동으로 연결돼요
          </Text>
        </View>
      )}
      {state === 'preaccept' && (
        <View style={s.emptyWrap}>
          <Text style={{ fontSize: 16, fontWeight: '900', color: paper.ink, textAlign: 'center' }}>러너가 수락하면 채팅을 열 수 있어요</Text>
          <Text style={{ fontSize: 15, color: colors.dim, textAlign: 'center', marginTop: 6, lineHeight: 20.5 }}>
            요청을 수락한 러너와 바로 연결돼요
          </Text>
        </View>
      )}
      {state === 'error' && (
        <View style={s.emptyWrap}>
          <Text style={{ fontSize: 15, color: colors.dim, textAlign: 'center' }}>채팅을 불러오지 못했어요 — 잠시 후 다시 시도해주세요</Text>
          <Pressable
            style={s.retryBtn}
            onPress={retryLoad}
            accessibilityRole="button"
            accessibilityLabel="채팅 다시 시도"
          >
            <Text style={{ fontSize: 15, fontWeight: '800', color: paper.ink }}>다시 시도</Text>
          </Pressable>
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
            <Text style={{ fontSize: 15, color: colors.dim, textAlign: 'center', marginTop: 20 }}>
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
            <Text style={{ fontSize: 15, color: colors.dim, textAlign: 'center', marginTop: 8 }}>
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
              <Text style={{ fontSize: 15, fontWeight: '700', color: '#3d453d' }}>{q}</Text>
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
        {/* [dead button 2026-08-19] 예전엔 opacity 0.5만 걸려 있었다 — 흐릿해 보이지만 여전히
            눌렸고, 수락 전이나 빈 입력에서도 send()를 호출했다 (send가 안에서 return하므로
            **아무 일도 안 일어나는 버튼**). 상태를 명시 disabled로 말한다: 불투명도는 표현이지
            상태가 아니다 (theme.ts:206 매트릭스). */}
        <Pressable
          style={[s.sendBtn, sendBlocked && { opacity: 0.5 }]}
          onPress={() => send(input)}
          disabled={sendBlocked}
          accessibilityRole="button"
          accessibilityLabel="보내기"
          accessibilityState={{ disabled: sendBlocked }}
        >
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
  retryBtn: { alignSelf: 'center', marginTop: 14, backgroundColor: colors.volt, borderRadius: 99, paddingVertical: 10, paddingHorizontal: 18 },
  bubbleRow: { flexDirection: 'row', alignItems: 'flex-end', gap: 6 },
  bubble: { maxWidth: '76%', borderRadius: 18, paddingVertical: 10, paddingHorizontal: 14 },
  bubblePeer: { backgroundColor: '#fff', borderWidth: 1, borderColor: '#DCD6C4', borderBottomLeftRadius: 6 },
  bubbleMine: { backgroundColor: colors.volt, borderBottomRightRadius: 6 },
  time: { fontSize: 15, color: colors.dim, marginBottom: 3 },
  quick: { backgroundColor: '#fff', borderRadius: 99, paddingVertical: 9, paddingHorizontal: 14, borderWidth: 1, borderColor: '#DCD6C4', alignSelf: 'center' },
  inputBar: { padding: 14, paddingBottom: 30, gap: 8, backgroundColor: colors.cream },
  attach: { width: 38, height: 38, borderRadius: 19, backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: '#DCD6C4' },
  input: { flex: 1, backgroundColor: '#fff', borderRadius: 22, paddingHorizontal: 16, paddingVertical: 11, fontSize: 16, borderWidth: 1, borderColor: '#DCD6C4', color: paper.ink },
  sendBtn: { width: 42, height: 42, borderRadius: 21, backgroundColor: colors.volt, alignItems: 'center', justifyContent: 'center' },
});
