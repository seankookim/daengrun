import { useFocusEffect, useLocalSearchParams } from 'expo-router';
import { useCallback, useEffect, useRef, useState } from 'react';
import { Alert, AppState, Image, KeyboardAvoidingView, Platform, Pressable, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Monogram, Row } from '../src/components/ui';
import { announce, useAnnounceOnChange } from '../src/lib/a11y-announce';
import {
  GAP_DOOR_LABEL, gapClosedBy, mergeMessageSnapshot, MessageCursor, snapshotGap,
} from '../src/lib/chat-messages';
import {
  MarkReadReason, newestPeerMessageId, READ_RECEIPT_LABEL, readReceiptMessageId, shouldMarkRead,
} from '../src/lib/chat-read';
import {
  CHAT_PAGE_SIZE, chatBubble, OLDER_DOOR_BUSY_LABEL, olderCursor, olderDoorLabel, olderDoorState,
  pageIsLast,
} from '../src/lib/chat-window';
import { MediaImage } from '../src/lib/media';
import { goBackOrHome } from '../src/lib/nav';
import { CHAT_TITLE } from '../src/lib/notification-route';
import {
  ChannelLink, ChatContext, ChatMsg, fetchChatReadState, fetchCurrentOwnerBookingId,
  fetchCurrentRunnerJobId, createChatClientKey, fetchMessages, fetchOlderMessages, markChatRead,
  openChatForBooking, sendChatMessage, sendChatPhoto, subscribeMessages,
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

// How many older pages the screen fetches on its own to close a reconnect hole before it stops
// and hands the rest to a door. Bounded on purpose: a thread that moved on by thousands of
// messages must not turn one poll tick into an unbounded backfill, and a door the reader taps is
// honest about there being more, where a spinner that never ends is not.
const GAP_FILL_MAX_PAGES = 3;

export default function Chat() {
  const insets = useSafeAreaInsets();
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
  // ── [2026-09-23] 이전 메시지 더 보기 ────────────────────────────────────────────────────────
  // The read below is the NEWEST page (api.ts `fetchMessages`; it used to be the OLDEST, which is
  // the defect this door exists beside). `olderExhausted` starts FALSE and is settled by the first
  // page's own length: a first page shorter than the window is the whole thread, so the door never
  // appears. It is not a guess — `pageIsLast` reads the server's row count.
  const [olderBusy, setOlderBusy] = useState(false);
  const [olderExhausted, setOlderExhausted] = useState(false);
  // Prepending older messages grows the content, and `onContentSizeChange` below jumps to the
  // bottom on every growth — which would throw the reader back to the newest message the instant
  // they asked to see older ones. This suppresses exactly one of those jumps.
  const holdScroll = useRef(false);
  const pendingText = useRef<{ threadId: string; body: string; key: string } | null>(null);
  const sendInFlight = useRef<ChatContext | null>(null);
  const scroller = useRef<ScrollView>(null);
  const mounted = useRef(false);
  // [codex r3-14] 이벤트 핸들러(send/sendPhoto)의 await 뒤 쓰기는 mounted만으로 부족하다 —
  // bid가 바뀌어도 mounted는 참이라, A 스레드의 늦은 스냅샷·전송 실패·sending 해제가 전부 B에
  // 떨어졌다(세 effect는 alive 클로저로 이미 올바른데 핸들러 둘만 마운트 가드였다). 작업 시작
  // 시점의 ctx를 붙들고, 현재 ctx와 다르면 버린다.
  const ctxRef = useRef<ChatContext | null>(null);
  useEffect(() => { ctxRef.current = ctx; }, [ctx]);
  // [0212] 같은 이유의 거울 — 포커스/앱 복귀 핸들러는 마운트 시점 클로저를 들고 살아 있으므로,
  // `state` 를 값으로 읽으면 언제나 'loading' 을 본다.
  const stateRef = useRef(state);
  useEffect(() => { stateRef.current = state; }, [state]);
  // [2026-09-25 · codex c1] 이 화면이 **내비게이션 포커스**를 쥐고 있는가. useFocusEffect 가 아래에서
  // 세팅하지만 선언은 여기 있어야 한다 — 읽음 표시 effect(아래)와 AppState 리스너와 포커스 핸들러,
  // 셋 다 이 값을 읽는다. 앱이 active 인 것과 **이 화면이 앞에 있는 것**은 서로 다른 사실이다:
  // Expo Router 는 푸시된 화면 뒤에 채팅을 마운트한 채로 두고 폴러도 계속 돈다.
  const screenFocused = useRef(false);
  // HIG A3 — the highest PEER message id this screen has already accounted for. `null` = the
  // thread's history has not landed yet, so the first snapshot primes instead of announcing 300
  // old messages at once. Reset with the thread below, or a new thread's history announces.
  const seenPeerMsgId = useRef<number | null>(null);
  // ── [0212] 읽음 상태 ─────────────────────────────────────────────────────────────────────
  // `peerReadAt` = 상대가 이 스레드를 마지막으로 읽은 시각 (chat_thread_read_state). null 이면
  // 「아직 안 읽었다」이고 그때는 영수증을 **그리지 않는다** — 서버가 말한 적 없는 걸 화면이
  // 말하는 게 이 앱이 금지하는 바로 그것이다. 배치 규칙은 chat-read.ts 가 소유한다.
  const [peerReadAt, setPeerReadAt] = useState<string | null>(null);
  // 이 화면이 이미 읽음 표시를 보낸 가장 높은 **상대** 메시지 id. 조용한 스레드에서 폴 틱마다
  // RPC 를 부르지 않게 하는 게이트이고, 「열었다」와 「새 메시지가 왔다」를 가르는 기준이다.
  const markedOpen = useRef(false);
  const lastMarkedPeer = useRef<number | null>(null);
  // [0223 · codex #1] The ids a SUCCESSFUL FETCH has returned — the only messages a read may be
  // recorded up to (chat-read.ts `newestPeerMessageId`). A snapshot is the newest window of one
  // server order, so every message between its oldest and its newest was in it, and below its
  // oldest lies either the history the screen already holds or a hole it has marked (the gap
  // ceiling). A message that arrived by realtime alone carries no such guarantee — the channel
  // drops events across a reconnect, and the dropped ones sit below the delivered one, undrawn —
  // so it waits for the next successful poll to vouch for it. Message ids are unique across the
  // whole table, so a stale id from another thread can never match; the set is still reset with
  // the thread, for hygiene.
  const fetchedIds = useRef<Set<number>>(new Set());
  // Bumped when a fetch vouches for ids the screen already held (merge returns the same array, so
  // `msgs` alone would not re-run the acknowledgement), and after every successful return-refresh.
  const [ackTick, setAckTick] = useState(0);
  // Set by a successful return-refresh, consumed by the acknowledgement effect on the commit that
  // renders it: the acknowledgement for 'focus' happens AFTER the refreshed snapshot is on screen.
  const focusAckDue = useRef(false);
  // [codex r3-13] bid 교체는 초안·전송 플래그도 비운다 — A용 초안이 B 스레드로 전송될 수 있었고,
  // A의 진행 중 전송이 B의 보내기를 막았다. 60행의 공유 리셋 목록에 넣지 않는 이유: 그 목록은
  // loadAttempt(같은 스레드 재시도)에도 돌아, 재시도마다 멀쩡한 초안을 지우게 된다.
  // ⚠ 읽음 표시 ref 둘도 **스레드 정체**의 사실이므로 seenPeerMsgId 와 같은 자리에 있어야 한다 —
  //   A 스레드에서 표시한 id 를 B 에 들고 가면 B 의 첫 읽음 표시가 조용히 건너뛰어진다.
  useEffect(() => {
    setInput(''); setSending(false); pendingText.current = null; sendInFlight.current = null;
    seenPeerMsgId.current = null; markedOpen.current = false; lastMarkedPeer.current = null;
  }, [bid]);
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

  // ── [2026-09-25 · codex c3] 재연결 구멍 ──────────────────────────────────────────────────────
  // 스냅샷은 **가장 최신 100개**다. 자리를 비운 사이 100개가 넘게 쌓였다면 그 페이지는 화면이 들고
  // 있던 기록에 닿지 못하고, 합집합 머지는 그 둘을 **아무 말 없이** 이어 붙인다 — 가운데가 통째로
  // 빠진 대화가 끊긴 적 없는 대화처럼 보인다. 위의 「이전 메시지 더 보기」는 가장 오래된 메시지에서
  // 뒤로 가므로 구멍 아래를 판다: 그 문은 이 구멍을 절대 메우지 못한다.
  // 순서는 (a) 스스로 메우기, 막히면 (b) 구멍 자리에 문. 지어내지 않고, 들고 있던 메시지도 버리지
  // 않는다.
  const msgsRef = useRef<ChatMsg[]>(msgs);
  useEffect(() => { msgsRef.current = msgs; }, [msgs]);
  /** 한 번에 하나의 메우기만 — 폴 간격(5~15초)은 한 번의 백필보다 짧을 수 있다. */
  const gapFilling = useRef(false);
  /** 스스로 메우지 못한 구멍. `afterId` 아래에 문이 그려지고, `cursor` 가 다음 페이지의 기준이다. */
  const [gapDoor, setGapDoor] = useState<{ afterId: number; cursor: MessageCursor } | null>(null);
  const [gapBusy, setGapBusy] = useState(false);

  /** Record that a fetch returned these messages. True when it vouched for an id not seen before. */
  const noteFetched = useCallback((page: readonly ChatMsg[]): boolean => {
    let grew = false;
    for (const m of page) {
      if (!fetchedIds.current.has(m.id)) { fetchedIds.current.add(m.id); grew = true; }
    }
    return grew;
  }, []);

  /** 구멍 위에서 아래로 최대 `GAP_FILL_MAX_PAGES` 페이지를 당겨 온다. 닫혔는지와 다음 커서를
   *  돌려주고, 쓰기는 전부 스레드 정체(ctxRef)로 게이트한다 — send/deliverPhoto 와 같은 관용구. */
  const fillGap = useCallback(async (opCtx: ChatContext, afterId: number, fromCursor: MessageCursor) => {
    let cursor = fromCursor;
    for (let i = 0; i < GAP_FILL_MAX_PAGES; i += 1) {
      // eslint-disable-next-line no-await-in-loop
      const page = await fetchOlderMessages(opCtx.threadId, cursor);
      if (!mounted.current || ctxRef.current !== opCtx) return { closed: false, cursor };
      noteFetched(page);
      // 읽는 사람 위로 자라는 것이므로 loadOlder 와 같은 스크롤 억제를 쓴다.
      holdScroll.current = true;
      setMsgs((current) => mergeMessageSnapshot(current, page));
      if (gapClosedBy(afterId, page)) return { closed: true, cursor };
      // 서버가 커서보다 오래된 걸 한 창보다 적게 줬다 = 더 줄 게 없다. 구멍은 비어 있었다.
      if (pageIsLast(page.length, CHAT_PAGE_SIZE)) return { closed: true, cursor };
      const next = olderCursor(page);
      if (next === null) return { closed: true, cursor };
      cursor = next;
    }
    return { closed: false, cursor };
  }, [noteFetched]);

  /** 최신 스냅샷을 화면에 들인다 — 머지 + 구멍 탐지 + (a) 자동 메우기.
   *  ⚠ 구멍은 **이 순간에만** 관측된다: 머지가 끝나면 held 가 스냅샷을 포함하므로 다음 틱의
   *    `snapshotGap` 은 영원히 null 이다. 그래서 메우기를 시도하기 **전에** 문을 먼저 기록한다.
   *  [0223] Every caller holds a SUCCESSFUL fetch, so this is also where ids become acknowledgeable
   *  (`noteFetched`). The door below is set in the same synchronous block as the merge, so the
   *  commit that renders a hole also renders its door — the acknowledgement effect never sees one
   *  without the other. */
  const absorbSnapshot = useCallback((opCtx: ChatContext, snapshot: ChatMsg[]) => {
    const held = msgsRef.current;
    if (noteFetched(snapshot)) setAckTick((n) => n + 1);
    setMsgs((current) => mergeMessageSnapshot(current, snapshot));
    const hole = snapshotGap(held, snapshot);
    const cursor = olderCursor(snapshot);
    // ⚠ NAMED LIMITATION, not an oversight: while a fill is in flight a SECOND hole is dropped.
    //   The screen holds one door, and the door it already holds sits BELOW any newer hole, so
    //   keeping it is the conservative half. Reaching this needs the thread to jump a full window
    //   TWICE inside one bounded backfill (≈3 requests); the honest cost is that the newer hole
    //   stays unmarked until a later snapshot opens one again. Written down rather than pinned —
    //   a pin for a state this harness cannot reach would be green by construction.
    if (hole === null || cursor === null || gapFilling.current) return;
    setGapDoor({ afterId: hole.afterId, cursor });
    gapFilling.current = true;
    setGapBusy(true);
    fillGap(opCtx, hole.afterId, cursor)
      .then((out) => {
        if (!mounted.current || ctxRef.current !== opCtx) return;
        if (out.closed) setGapDoor(null);
        else setGapDoor({ afterId: hole.afterId, cursor: out.cursor });
      })
      .catch((e) => {
        // 실패는 실패로 남는다 — 문이 그대로 있고, 탭하면 같은 지점에서 다시 시도한다.
        console.warn('[chat] gap fill:', (e as Error)?.message ?? e);
      })
      .finally(() => {
        gapFilling.current = false;
        if (mounted.current && ctxRef.current === opCtx) setGapBusy(false);
      });
  }, [fillGap, noteFetched]);

  /** (b) 문. 자동 메우기가 한도에 걸렸거나 실패했을 때만 존재한다. */
  const loadGap = useCallback(() => {
    const opCtx = ctxRef.current;
    const door = gapDoor;
    if (!opCtx || door === null || gapFilling.current) return;
    gapFilling.current = true;
    setGapBusy(true);
    fillGap(opCtx, door.afterId, door.cursor)
      .then((out) => {
        if (!mounted.current || ctxRef.current !== opCtx) return;
        if (out.closed) setGapDoor(null);
        else setGapDoor({ afterId: door.afterId, cursor: out.cursor });
      })
      .catch((e) => console.warn('[chat] gap fill:', (e as Error)?.message ?? e))
      .finally(() => {
        gapFilling.current = false;
        if (mounted.current && ctxRef.current === opCtx) setGapBusy(false);
      });
  }, [gapDoor, fillGap]);

  // 스레드 준비: bid 없으면 진행 중 예약을 서버에서 해석
  useEffect(() => {
    let alive = true;
    // [codex 2026-08-31 r2-F5] bid가 바뀐 채 재실행되면 이전 스레드의 ctx·메시지가 새 스레드에
    // 합류했다(머지가 합집합이라 A의 말풍선이 B 아래 남는다) — 진입마다 스레드 중립 상태로
    // 되돌린다. retryLoad와 같은 리셋 목록이어야 한다: 하나가 늘면 둘 다 늘어야 한다.
    setCtx(null); setMsgs([]); setLink('connecting'); setPollErr(false); setState('loading');
    setOlderBusy(false); setOlderExhausted(false); setPeerReadAt(null);
    setGapDoor(null); setGapBusy(false); gapFilling.current = false;
    fetchedIds.current = new Set(); focusAckDue.current = false;
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
        noteFetched(history);
        // ⚠ 여기만 `absorbSnapshot` 을 쓰지 않는다: 위에서 msgs 를 비웠고 msgsRef 는 아직 **이전
        //   스레드**의 배열을 들고 있어(렌더 뒤에 갱신된다) 구멍 탐지가 남의 대화를 기준으로 돈다.
        //   첫 페이지는 창 그 자체이므로 구멍이 있을 수 없고, 그 아래는 olderExhausted 가 맡는다.
        setMsgs((current) => mergeMessageSnapshot(current, history));
        // The first page IS the newest window, so its own length settles whether anything older
        // exists. A short page = the whole thread is on screen and the door never appears.
        setOlderExhausted(pageIsLast(history.length, CHAT_PAGE_SIZE));
        setState('ready');
        // [0212] 첫 영수증. 아래 폴 틱이 같은 값을 계속 갱신하지만 그 첫 틱은 5~15초 뒤이고,
        // 그때까지 영수증이 없는 것과 상대가 안 읽은 것이 화면에서 같아 보인다. 실패는 로그로만 —
        // 영수증은 작동하는 화면의 장식이지 화면의 주제가 아니다.
        fetchChatReadState(c.threadId)
          .then((at) => { if (alive) setPeerReadAt(at); })
          .catch((e) => console.warn('[chat] read state:', (e as Error)?.message ?? e));
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
  }, [bid, isRunner, loadAttempt, noteFetched]);

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
        // [c3] 재연결 뒤 구멍이 생기는 자리가 바로 여기다 — 머지와 탐지를 한 문으로 묶는다.
        absorbSnapshot(ctx, next);
      } catch (e) {
        console.warn('[chat] poll:', (e as Error)?.message ?? e);
        if (alive) setPollErr(true); // 조용히 삼키면 헤더가 '받고 있다'고 우긴다
      }
    };
    const t = setInterval(tick, link === 'live' ? 15_000 : 5_000);
    return () => { alive = false; clearInterval(t); };
  }, [ctx, state, link, absorbSnapshot]);

  // ── [0212] 상대의 읽음 시각 — 기존 폴 케이던스를 그대로 탄다 ─────────────────────────────
  // 새 채널을 열지 않는다. `chat-<thread>` 는 chat_messages INSERT 만 싣는 postgres_changes 방이고
  // (0108 §1), 읽음 위치는 chat_reads 의 사실이라 그 방으로는 오지 않는다. 방을 하나 더 여는 대신
  // 이미 도는 폴에 한 번의 읽기를 얹는다 — 위 tick 과 같은 간격(실시간 15초 / 끊김 5초).
  // ⚠ 실패는 pollErr 를 켜지 않는다: 헤더의 「메시지를 못 받고 있어요」는 **메시지**에 대한 문장이고,
  //   영수증을 못 읽은 것과 메시지를 못 받는 것은 다른 사실이라 한 채널에 뭉개면 둘 다 못 믿게 된다.
  useEffect(() => {
    if (!ctx || state !== 'ready') return;
    let alive = true;
    const tick = async () => {
      try {
        const at = await fetchChatReadState(ctx.threadId);
        if (alive) setPeerReadAt(at);
      } catch (e) {
        console.warn('[chat] read state:', (e as Error)?.message ?? e);
      }
    };
    const t = setInterval(tick, link === 'live' ? 15_000 : 5_000);
    return () => { alive = false; clearInterval(t); };
  }, [ctx, state, link]);

  // ── [0212 → 0223] recording that the caller has read — open · a fetched message · coming back ──
  // Every judgment is `shouldMarkRead`'s (chat-read.ts — the only place a test can reach), and
  // there is exactly ONE call site: the effect below.
  // ⚠ **A backgrounded screen records nothing.** Expo Router keeps the previous screen mounted and
  //   the poller above keeps running, so a chat screen behind a lock screen keeps receiving
  //   messages. Marking those read would tell the counterpart 「읽음」 about a message nobody looked
  //   at — the app asserting a human action that did not happen. A phone in a pocket reads nothing.
  // 🔴 [0223 · codex #1] A read is recorded UP TO A MESSAGE, never 「up to now」. 0212's RPC wrote the
  //   server's now(), and the focus and app-return callbacks fired it BEFORE their refetch, on the
  //   screen as it was before a suspension — so every peer message that had piled up on the server
  //   became 「읽음」 unseen, and stayed so if the refetch then failed. Now:
  //   (a) coming back refreshes FIRST (`refreshThenRead`); a failed refresh records nothing;
  //   (b) the record happens in this effect, i.e. on the COMMIT that renders the refreshed snapshot;
  //   (c) it names the newest peer message a SUCCESSFUL fetch returned, below any open hole
  //       (`newestPeerMessageId`), and the server writes that message's created_at (0223).
  const recordRead = useCallback((threadId: string, upToMessageId: number, legacyFallback: boolean) => {
    markChatRead(threadId, upToMessageId, { legacyFallback })
      .catch((e) => console.warn('[chat] mark read:', (e as Error)?.message ?? e));
  }, []);

  useEffect(() => {
    if (!ctx || state !== 'ready') return;
    const focusDue = focusAckDue.current;
    focusAckDue.current = false;
    const ceilingId = gapDoor === null ? null : gapDoor.afterId;
    const target = newestPeerMessageId(msgs, { ceilingId, fetchedIds: fetchedIds.current });
    const reason: MarkReadReason = focusDue ? 'focus' : markedOpen.current ? 'message' : 'open';
    if (!shouldMarkRead({
      reason,
      ready: true,
      appActive: AppState.currentState === 'active',
      // [codex c1] 앱이 앞에 있는 것만으로는 부족하다 — 이 화면이 다른 화면 뒤에 마운트된 채
      // 폴링만 돌고 있을 수 있고, 그때 들어온 메시지를 읽음으로 찍으면 상대의 「읽음」이 거짓말이
      // 된다. 포커스를 되찾으면 refreshThenRead 가 리페치하고, 그 커밋에서 이 effect 가 표시한다.
      focused: screenFocused.current,
      newestPeerMessageId: target,
      lastMarkedPeerMessageId: lastMarkedPeer.current,
    })) return;
    // `shouldMarkRead` refuses a null target for every reason; this guard is for the type.
    if (target === null) return;
    markedOpen.current = true;
    lastMarkedPeer.current = target;
    // The skew-window fallback to 0212's now() (api.ts markChatRead) is allowed only when that
    // now() cannot read past what is on screen by more than the round trip: no hole open, and the
    // target IS the newest peer message the screen holds (no realtime-only message above it).
    const newestHeld = newestPeerMessageId(msgs);
    recordRead(ctx.threadId, target, ceilingId === null && newestHeld === target);
  }, [ctx, state, msgs, gapDoor, ackTick, recordRead]);

  /** Coming back to the screen: REFRESH, and only a successful refresh asks for an
   *  acknowledgement — which the effect above performs on the commit that renders it. A failed
   *  refresh is a failure (pollErr) and records nothing. Writes are gated on thread identity. */
  const refreshThenRead = useCallback(async (opCtx: ChatContext) => {
    let next: ChatMsg[];
    try {
      next = await fetchMessages(opCtx.threadId);
    } catch (e) {
      console.warn('[chat] refresh on return:', (e as Error)?.message ?? e);
      if (mounted.current && ctxRef.current === opCtx) setPollErr(true);
      return;
    }
    if (!mounted.current || ctxRef.current !== opCtx) return;
    setPollErr(false);
    absorbSnapshot(opCtx, next);
    focusAckDue.current = true;
    setAckTick((n) => n + 1);
  }, [absorbSnapshot]);

  // 화면이 다시 앞으로 왔을 때. 내비게이션 포커스(useFocusEffect)와 **앱 복귀**(AppState)는 서로를
  // 대신하지 못한다 — 백그라운드는 포커스된 화면을 블러하지 않으므로, 앱을 내렸다 올리는 동안
  // 도착한 메시지는 포커스 이벤트를 만들지 않는다 (owner/home.tsx:334 가 같은 이유로 둘 다 둔다).
  // ⚠ This is c1's other half: messages that arrived while unfocused are NOT recorded then, and
  //   are recorded here — [0223] after a successful refresh has put them on screen, never before.
  //   Nothing is lost, and nothing is claimed ahead of the screen.
  useFocusEffect(useCallback(() => {
    screenFocused.current = true;
    const c = ctxRef.current;
    if (c && stateRef.current === 'ready') void refreshThenRead(c);
    return () => { screenFocused.current = false; };
  }, [refreshThenRead]));

  useEffect(() => {
    const sub = AppState.addEventListener('change', (st) => {
      const c = ctxRef.current;
      // This early return does not replace the judgment's own gates — the effect above hands the
      // same facts to `shouldMarkRead` after the refresh. Here it only saves a pointless fetch.
      if (!screenFocused.current || !c || st !== 'active') return;
      if (stateRef.current !== 'ready') return;
      void refreshThenRead(c);
    });
    return () => sub.remove();
  }, [refreshThenRead]);

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
      await deliverPhoto(opCtx, res.assets[0].base64, createChatClientKey());
      return;
    } catch (e) {
      if (mounted.current && ctxRef.current === opCtx) Alert.alert('전송 실패', (e as Error).message);
      return;
    }
  };

  const deliverPhoto = async (opCtx: ChatContext, base64: string, clientKey: string): Promise<void> => {
    if (!mounted.current || ctxRef.current !== opCtx) return;
    try {
      await sendChatPhoto(opCtx.threadId, base64, clientKey);
    } catch (e) {
      if (mounted.current && ctxRef.current === opCtx) {
        Alert.alert('전송 실패', (e as Error).message, [
          { text: '취소', style: 'cancel' },
          { text: '다시 시도', onPress: () => { void deliverPhoto(opCtx, base64, clientKey); } },
        ]);
      }
      return;
    }
    // A refresh failure does not undo a successful send.
    try {
      const snapshot = await fetchMessages(opCtx.threadId);
      if (!mounted.current || ctxRef.current !== opCtx) return;
      // [c3] 이것도 「가장 최신 한 페이지」다 — 사진 한 장 보내는 동안 스레드가 한 창 넘게
      // 움직였을 수 있고, 구멍은 폴 틱과 똑같이 여기서도 생긴다.
      absorbSnapshot(opCtx, snapshot);
      setTimeout(() => scroller.current?.scrollToEnd({ animated: true }), 60);
    } catch {
      if (mounted.current && ctxRef.current === opCtx) setPollErr(true);
    }
  };

  const send = async (body: string) => {
    if (!body.trim() || !ctx || sending || sendInFlight.current === ctx) return;
    const opCtx = ctx; // [r3-14] 이 작업이 속한 스레드 — 이후의 모든 쓰기는 이 정체로 게이트
    const trimmed = body.trim();
    const pending = pendingText.current;
    const attempt = pending?.threadId === opCtx.threadId && pending.body === trimmed
      ? pending : { threadId: opCtx.threadId, body: trimmed, key: createChatClientKey() };
    pendingText.current = attempt;
    sendInFlight.current = opCtx;
    setSending(true);
    setInput('');
    try {
      await sendChatMessage(opCtx.threadId, trimmed, attempt.key);
      if (pendingText.current === attempt) pendingText.current = null;
    } catch (e) {
      // 전송 자체가 실패했을 때만 「전송 실패」+입력 복원 — 커밋된 메시지에 이 말을 하면
      // 재시도가 중복 전송이 된다 (codex r2-F10).
      if (mounted.current && ctxRef.current === opCtx) {
        // Keep this attempt's key with the restored draft, including an uncertain timeout.
        // Sending a different body starts a new attempt; successful sends retire the key.
        const code = (e as { code?: string })?.code;
        Alert.alert(
          code ? '전송 실패' : '전송이 확인되지 않았어요',
          code
            ? (e as Error).message
            : '네트워크 문제로 전송 여부를 확인하지 못했어요. 같은 메시지를 다시 보내면 중복 없이 재시도해요.',
        );
        setInput(body);
        setSending(false);
        if (sendInFlight.current === opCtx) sendInFlight.current = null;
        if (!code) {
          fetchMessages(opCtx.threadId)
            .then((snap) => {
              if (mounted.current && ctxRef.current === opCtx) absorbSnapshot(opCtx, snap);
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
      absorbSnapshot(opCtx, snapshot);
      setTimeout(() => scroller.current?.scrollToEnd({ animated: true }), 60);
    } catch {
      if (mounted.current && ctxRef.current === opCtx) setPollErr(true);
    } finally {
      // [r3-14] stale finally가 B의 sending을 풀거나 잠그지 않게 — B의 해제는 bid 효과가 맡는다
      if (sendInFlight.current === opCtx) sendInFlight.current = null;
      if (mounted.current && ctxRef.current === opCtx) setSending(false);
    }
  };

  const retryLoad = () => {
    setCtx(null);
    setMsgs([]);
    setLink('connecting');
    setPollErr(false);
    setState('loading');
    // Same reset list as the load effect above — 하나가 늘면 둘 다 늘어야 한다 (line 80).
    setOlderBusy(false);
    setOlderExhausted(false);
    setGapDoor(null);
    setGapBusy(false);
    gapFilling.current = false;
    fetchedIds.current = new Set();
    focusAckDue.current = false;
    setLoadAttempt((attempt) => attempt + 1);
  };

  // ── 「이전 메시지 더 보기」 ─────────────────────────────────────────────────────────────────
  // Pages strictly older than the oldest message on screen, by the SERVER's `(created_at, id)` on
  // that message ([0223 · codex #2] — `created_at` alone left a same-instant sibling unreachable).
  // A failure is a failure: the door comes back and `pollErr` says the screen is not receiving,
  // rather than the tap silently doing nothing.
  const loadOlder = async () => {
    const opCtx = ctx;
    if (!opCtx || olderBusy || olderExhausted) return;
    const cursor = olderCursor(msgs);
    if (cursor === null) return;
    setOlderBusy(true);
    try {
      const older = await fetchOlderMessages(opCtx.threadId, cursor);
      if (!mounted.current || ctxRef.current !== opCtx) return;
      noteFetched(older);
      holdScroll.current = true;
      // mergeMessageSnapshot is a union keyed by id, sorted by id — so it is direction-agnostic:
      // an older page merges below the window exactly as a newer snapshot merges above it, and a
      // message already held wins its own id either way.
      setMsgs((current) => mergeMessageSnapshot(current, older));
      setOlderExhausted(pageIsLast(older.length, CHAT_PAGE_SIZE));
    } catch (e) {
      console.warn('[chat] older:', (e as Error)?.message ?? e);
      if (mounted.current && ctxRef.current === opCtx) setPollErr(true);
    } finally {
      if (mounted.current && ctxRef.current === opCtx) setOlderBusy(false);
    }
  };

  const olderDoor = olderDoorState({
    hasMessages: msgs.length > 0,
    exhausted: olderExhausted,
    busy: olderBusy,
  });

  // Sending clears the draft; keep busy distinct from an unavailable or empty draft.
  const sendBlocked = !sending && (state !== 'ready' || input.trim().length === 0);

  // [0212] 「읽음」이 붙는 메시지 — 내 것 중, 상대의 읽음 시각 이하의 가장 최신 하나. 상대가 한 번도
  // 안 읽었으면(`peerReadAt === null`) null 이고 아무것도 안 그린다.
  const receiptId = readReceiptMessageId(msgs, peerReadAt);

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

  // ── HIG A3/A6 — the two things this screen changes on its own ────────────────────────────────
  // The header line above is the whole reason the channel distinction exists: a sighted user sees
  // 「메시지를 못 받고 있어요」 go critical-red and knows the 「5분 늦어요」 they are waiting for may
  // never arrive. Without this the same fact was invisible to a screen-reader user, which turns a
  // deliberately honest line back into a silent lie.
  // ⚠ 연결 중 announces nothing and primes nothing — it is the UNSETTLED state, not an answer, so
  // it gets the same treatment as a null state strip on the run and radar screens (the first
  // settled sentence is this screen's content, and only a later flip is a change). The ● is
  // decoration; it is dropped rather than spelled out.
  const linkSentence = linkLine === null || linkLine.tx === '연결 중...'
    ? null
    : linkLine.tx.replace('●', '').trim();
  useAnnounceOnChange(linkSentence);

  // A message arriving is the other one. ⚠ Only that one ARRIVED, and from whom — never the body.
  // A screen reader is a loudspeaker in whatever room its owner is standing in, and nobody chose
  // to play this conversation out loud; the message itself is read when they navigate to it.
  // `새 메시지` is the product's own chat vocabulary (notification-route's CHAT_TITLE, the title
  // the push carries), not a sentence written for this announcement.
  useEffect(() => {
    let newest: number | null = null;
    for (const m of msgs) if (!m.mine && (newest === null || m.id > newest)) newest = m.id;
    if (newest === null) return;
    if (seenPeerMsgId.current === null) { seenPeerMsgId.current = newest; return; } // history
    if (newest <= seenPeerMsgId.current) return;
    seenPeerMsgId.current = newest;
    // No peer name yet (the header reads 「채팅」) — say that one arrived and stop. A placeholder
    // name would be a fabricated field read aloud as if it were real.
    announce(ctx?.peerName ? `${CHAT_TITLE}: ${ctx.peerName}` : CHAT_TITLE);
  }, [msgs, ctx?.peerName]);

  return (
    <KeyboardAvoidingView style={{ flex: 1, backgroundColor: colors.cream }} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
      {/* header */}
      <Row style={[s.header, { paddingTop: insets.top }]}>
        <Pressable onPress={goBackOrHome} style={s.circleBtn} accessibilityRole="button" accessibilityLabel="뒤로"><Text style={{ fontSize: 20.5 }}>‹</Text></Pressable>
        <Monogram char={(ctx?.peerName ?? '·')[0]} bg={isRunner ? '#c9a86e' : '#5a7a3c'} size={40} />
        <View style={{ flex: 1, marginLeft: 10 }}>
          <Text accessibilityRole="header" style={{ fontSize: 17, fontWeight: '900', color: paper.ink }}>{ctx?.peerName ?? '채팅'}</Text>
          {/* [HIG A3] Android's live region for the same line iOS gets through `announce` above.
              polite, never assertive: the connection line is a fact worth hearing, not one worth
              cutting off whatever the user is reading to say. */}
          <Text
            accessibilityLiveRegion="polite"
            style={{ fontSize: 15, color: linkLine?.bad ? paper.critical : colors.dim, fontWeight: linkLine?.bad ? '700' : '400', marginTop: 1 }}
          >
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
          onContentSizeChange={() => {
            // An older page just landed above the reader — growing the content must NOT throw
            // them back to the newest message. One jump is suppressed, then the normal
            // follow-the-conversation behaviour resumes.
            if (holdScroll.current) { holdScroll.current = false; return; }
            scroller.current?.scrollToEnd({ animated: false });
          }}
        >
          {/* [2026-09-23] The door onto the rest of the thread. The read above is the NEWEST
              hundred; before this existed the screen read the OLDEST hundred and said nothing
              about the cap, so a long thread looked like a thread that had stopped. `olderDoor`
              is 'none' once the server has returned a short page — the control disappears rather
              than staying behind as a button that does nothing.
              Busy follows the send button's grammar exactly (see the send Pressable below): a
              LABEL SWAP that keeps its fill and reports `accessibilityState.busy` — never the
              disabled state, which in this repo means unavailable. A second tap while a page is
              in flight is a no-op because the page is already coming, not because the control is
              dead. */}
          {olderDoor !== 'none' && (
            <Pressable
              style={s.olderDoor}
              onPress={() => { if (olderDoor === 'ready') void loadOlder(); }}
              accessibilityRole="button"
              accessibilityLabel={olderDoorLabel(olderDoor)}
              accessibilityState={{ busy: olderDoor === 'busy' }}
            >
              <Text style={{ fontSize: 15, fontWeight: '700', color: '#3d453d' }}>{olderDoorLabel(olderDoor)}</Text>
            </Pressable>
          )}
          {state === 'ready' && msgs.length === 0 && (
            <Text style={{ fontSize: 15, color: colors.dim, textAlign: 'center', marginTop: 20 }}>
              첫 메시지를 보내보세요 — 픽업 장소나 아이 성향을 미리 나누면 좋아요
            </Text>
          )}
          {msgs.map((m) => {
            // [2026-09-23] `kind` is now selected and bound. Before this, a row that was neither
            // plain text nor a photo drew an EMPTY bubble — visible, unreadable, unexplained.
            const bubble = chatBubble({ kind: m.kind, body: m.body, mediaUrl: m.mediaUrl });
            return (
              <View key={m.id}>
              <View style={[s.bubbleRow, m.mine && { justifyContent: 'flex-end' }]}>
                {m.mine && <Text style={s.time}>{m.when}</Text>}
                <View style={[s.bubble, m.mine ? s.bubbleMine : s.bubblePeer, bubble.shape === 'photo' && { padding: 4 }]}>
                  {bubble.shape === 'photo' ? (
                    /* [0064] media_path는 프라이빗 버킷 경로 — MediaImage가 서명 URL로 풀고 만료를 명시 실패로 그린다 */
                    <MediaImage source={bubble.mediaUrl} style={{ width: 190, height: 190, borderRadius: 14 }} resizeMode="cover" />
                  ) : bubble.shape === 'text' ? (
                    <Text style={{ fontSize: 15.5, lineHeight: 22, color: m.mine ? paper.ink : '#2c332c' }}>{bubble.text}</Text>
                  ) : (
                    /* A kind this build cannot draw. It says what it is instead of showing
                       nothing — and `chat_messages` carries no payload column, so 위치 메시지 is a
                       label and never an invented coordinate. */
                    <View>
                      <Text style={{ fontSize: 15, fontWeight: '800', color: m.mine ? paper.ink : '#2c332c' }}>{bubble.label}</Text>
                      {bubble.text !== '' && (
                        <Text style={{ fontSize: 15.5, lineHeight: 22, marginTop: 3, color: m.mine ? paper.ink : '#2c332c' }}>{bubble.text}</Text>
                      )}
                    </View>
                  )}
                </View>
                {!m.mine && <Text style={s.time}>{m.when}</Text>}
              </View>
              {/* [0212] 영수증은 **한 줄뿐이다** — 상대가 본 마지막 내 메시지 아래에만. 말풍선마다
                  붙이면 대화가 라벨 밭이 되고, 보내는 사람이 실제로 묻는 것(「그 5분 늦어요가
                  닿았나」)에는 한 줄이면 답이 된다. 상대가 한 번도 안 읽었으면 이 줄은 없다. */}
              {m.id === receiptId && (
                <Text style={s.receipt} accessibilityLabel={`${READ_RECEIPT_LABEL} — 상대가 확인했어요`}>
                  {READ_RECEIPT_LABEL}
                </Text>
              )}
              {/* [2026-09-25 · codex c3] 구멍 위의 문. 재연결 스냅샷이 화면의 기록에 닿지 못했고
                  스스로 메우기가 한도에 걸렸을 때만 나온다 — 위의 「이전 메시지 더 보기」와 같은 칩
                  문법이고, busy 는 같은 단어(OLDER_DOOR_BUSY_LABEL)를 쓴다. 메워지면 사라진다:
                  아무것도 가져오지 못하는 문은 죽은 컨트롤이다. */}
              {gapDoor !== null && m.id === gapDoor.afterId && (
                <Pressable
                  style={[s.olderDoor, { marginTop: 4 }]}
                  onPress={() => { if (!gapBusy) loadGap(); }}
                  accessibilityRole="button"
                  accessibilityLabel={gapBusy ? OLDER_DOOR_BUSY_LABEL : GAP_DOOR_LABEL}
                  accessibilityState={{ busy: gapBusy }}
                >
                  <Text style={{ fontSize: 15, fontWeight: '700', color: '#3d453d' }}>
                    {gapBusy ? OLDER_DOOR_BUSY_LABEL : GAP_DOOR_LABEL}
                  </Text>
                </Pressable>
              )}
              </View>
            );
          })}
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
        <Pressable
          style={s.attach}
          onPress={sendPhoto}
          disabled={state !== 'ready'}
          accessibilityRole="button"
          accessibilityLabel="사진 보내기"
          accessibilityState={{ disabled: state !== 'ready' }}
        >
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
            상태가 아니다 (theme.ts:206 매트릭스).
            [busy 2026-09-22] Busy is a label swap that keeps its fill and reports only
            accessibilityState.busy; an unavailable or empty draft is the DISABLED state
            (disabledFill + faint). The two are no longer one predicate. */}
        <Pressable
          style={[s.sendBtn, sending && { width: 'auto', paddingHorizontal: 12 }, sendBlocked && { backgroundColor: paper.disabledFill }]}
          onPress={() => { if (!sending && !sendBlocked) send(input); }}
          disabled={sendBlocked}
          accessibilityRole="button"
          accessibilityLabel={sending ? '보내는 중…' : '보내기'}
          accessibilityState={{ busy: sending, disabled: sendBlocked }}
        >
          <Text style={{ fontSize: 17, fontWeight: '900', color: sendBlocked ? paper.faint : paper.ink }}>{sending ? '보내는 중…' : '↑'}</Text>
        </Pressable>
      </Row>
    </KeyboardAvoidingView>
  );
}

const s = StyleSheet.create({
  header: { paddingHorizontal: 18, paddingBottom: 12, gap: 10, backgroundColor: colors.cream, borderBottomWidth: 1, borderBottomColor: '#DCD6C4' },
  circleBtn: { width: 40, height: 40, borderRadius: 20, backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: '#DCD6C4' },
  contextStrip: { backgroundColor: '#eef4e0', paddingVertical: 8, paddingHorizontal: 18 },
  emptyWrap: { flex: 1, justifyContent: 'center', padding: 30 },
  retryBtn: { alignSelf: 'center', marginTop: 14, backgroundColor: colors.volt, borderRadius: 99, paddingVertical: 10, paddingHorizontal: 18 },
  bubbleRow: { flexDirection: 'row', alignItems: 'flex-end', gap: 6 },
  bubble: { maxWidth: '76%', borderRadius: 18, paddingVertical: 10, paddingHorizontal: 14 },
  bubblePeer: { backgroundColor: '#fff', borderWidth: 1, borderColor: '#DCD6C4', borderBottomLeftRadius: 6 },
  bubbleMine: { backgroundColor: colors.volt, borderBottomRightRadius: 6 },
  time: { fontSize: 15, color: colors.dim, marginBottom: 3 },
  // [0212] 「읽음」 — 한글 디테일 플로어 15pt (DESIGN.md §3; 한글은 키커 예외를 타지 않는다).
  // 내 말풍선은 오른쪽 정렬이므로 영수증도 그 끝을 따라간다.
  receipt: { fontSize: 15, color: colors.dim, alignSelf: 'flex-end', marginTop: 2, marginRight: 2 },
  quick: { backgroundColor: '#fff', borderRadius: 99, paddingVertical: 9, paddingHorizontal: 14, borderWidth: 1, borderColor: '#DCD6C4', alignSelf: 'center' },
  // The 「이전 메시지 더 보기」 door — the quick-reply chip grammar, centred at the top of the thread.
  olderDoor: { backgroundColor: '#fff', borderRadius: 99, paddingVertical: 9, paddingHorizontal: 16, borderWidth: 1, borderColor: '#DCD6C4', alignSelf: 'center', marginBottom: 4 },
  inputBar: { padding: 14, paddingBottom: 30, gap: 8, backgroundColor: colors.cream },
  attach: { width: 38, height: 38, borderRadius: 19, backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: '#DCD6C4' },
  input: { flex: 1, backgroundColor: '#fff', borderRadius: 22, paddingHorizontal: 16, paddingVertical: 11, fontSize: 16, borderWidth: 1, borderColor: '#DCD6C4', color: paper.ink },
  sendBtn: { width: 42, height: 42, borderRadius: 21, backgroundColor: colors.volt, alignItems: 'center', justifyContent: 'center' },
});
