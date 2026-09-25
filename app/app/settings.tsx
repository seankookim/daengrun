import { router, useFocusEffect } from 'expo-router';
import { useCallback, useEffect, useState } from 'react';
import { Alert, Linking, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useAuth } from '../src/auth-context';
import { DeleteAccountSheet } from '../src/components/delete-account-sheet';
import { PhoneRow } from '../src/components/phone-row';
import { Row, ScreenHead } from '../src/components/ui';
import { fetchMyProfile, fetchMyRunnerBase, MyProfile, opsMe } from '../src/lib/api';
import { kstCal, kstMonthDay } from '../src/lib/kst';
import { session } from '../src/store';
import { layout, paper } from '../src/theme';

// 설정 — 실화면. 가짜 하위메뉴 없음: 실계정 정보 + 실동작만, 나머지는 정직 라벨.

// [2026-08-12 · Sean "remove forest"] 이 파일의 로컬 상수 FOREST = '#0F1D13' 은퇴. 은퇴된 스왈프/포레스트 팔레트의
// 마지막 잔재였고, 12개 파일에 각자 로컬 상수로 복사돼 있었다 (한 값에 주인 12명).
// paper.ink(#111111)로 접는다 — 색차는 사실상 안 보이고(둘 다 근처 검정), 그게 정확히 아무도
// 못 본 이유다. 다크 면에도 같은 토큰을 쓴다 — 캘린더 보드·정산 티켓·빕 스트랩이 이미 그런다.
const APP_VERSION = '0.9 (파일럿)';

// 변경 잠금 안내 — 「7일에 한 번」이라는 숫자는 여기서 말하지 않는다. 쿨다운의 길이는 서버의
// _base_change_cooldown() (0123 §4b, Sean 2026-08-25 T1 룰링) 하나에만 있고, 클라가 되뇌면
// 숫자가 두 벌이 된다. 서버가 주는 can_change_at만 쓰고, 잠기지 않았으면 아무 말도 안 한다.
const lockSuffix = (iso: string | null): string => {
  if (!iso) return '';
  const t = Date.parse(iso);
  if (Number.isNaN(t) || t <= Date.now()) return '';
  // 날짜는 KST 로 읽는다 — can_change_at 은 서버 instant 이고, 기기 로컬로 읽으면 KST 자정
  // 근처의 만료가 하루 어긋나 「내일부터」를 「오늘부터」로 말한다. base-pin.tsx 와 같은 문자열.
  return ` · ${kstMonthDay(kstCal(t))}부터 변경 가능`;
};

export default function Settings() {
  const insets = useSafeAreaInsets();
  const { session: auth, signOut } = useAuth();
  const [profile, setProfile] = useState<MyProfile | null>(null);
  const [deleteOpen, setDeleteOpen] = useState(false);
  // [0123 · Sean Q6 ruling B] 러너 활동 기준 위치. 네 상태가 **전부 다르게** 그려져야 한다:
  //   'loading'  — 아직 모름 (로딩은 「미설정」이 아니다) → 섹션은 그리고 값 자리에 「확인 중…」
  //   'unset'    — 러너인데 아직 안 정함 → 진짜 문
  //   'set'      — 지정됨
  //   'none'     — 러너 계정이 아님 → **섹션 자체를 안 그린다** (없는 문을 만들지 않는다)
  //   'error'    — 못 읽음 → **섹션 자체를 안 그린다**
  // 🔴 'error'가 'none'과 같은 처리인 것이 픽스 라운드의 MAJOR-4다. 첫 판은 「저장된 위치를
  // 불러오지 못했어요 / —」라는 줄을 그렸고, 그건 한 사람의 일시적 장애에는 정직하지만 **배포
  // 순서에는 재앙**이다: 0123이 아직 안 올라간 서버에 붙은 빌드는 my_runner_base()가 없어서
  // 모든 호출이 실패하고, 그러면 러너가 아닌 **모든 보호자**의 설정 화면에 영구히 깨진 줄이
  // 하나 생긴다 — 자기와 아무 상관도 없는 기능에 대해. 러너 활동은 설정의 부가 섹션이므로
  // 못 읽을 때의 정직한 답은 침묵이다 (요청함의 문은 별개 경로로 살아 있다).
  // 모드(session.role)가 아니라 **서버 진실**로 가른다: 보호자 모드로 들어와도 러너 계정이면
  // 이 문은 찾을 수 있어야 한다 (Sean: "switch this address in settings").
  const [base, setBase] = useState<'loading' | 'none' | 'unset' | 'set' | 'error'>('loading');
  // 잠금 해제 시각 (0123 §4b). 서버가 준 결과값이고, 여기서는 한 줄 덧붙이는 데만 쓴다.
  const [lockedUntil, setLockedUntil] = useState<string | null>(null);

  // [honesty 2026-09-17] The profile read was `.catch(() => {})`, so the 이름 row printed '—'
  // identically while the read was in flight and after it had failed. '—' now means LOADING
  // only; a failure gets a strip with a retry, and 계정 is the one card on this screen whose
  // rows are server truth rather than local state.
  const [profileErr, setProfileErr] = useState(false);
  // [0198] 운영 콘솔 입구. `ops_me()` is the only way a client can learn its own membership —
  // `ops_recipients` is SEALED (0084 §E: RLS on, zero policies), so there is no table read.
  //
  // ⚠ **FALSE MEANS THE ROW IS NOT DRAWN AT ALL — no disabled placeholder, no 「준비 중」 label.**
  //   An operator console is not a feature an ordinary person is waiting for, so a greyed row
  //   telling every runner and owner about a screen they can never open would be an advertisement
  //   for a door rather than a door. The 「없는 문을 만들지 않는다」 rule the 러너 활동 section
  //   below already follows.
  // ⚠ **AND A FAILED CHECK IS ALSO 「NOT DRAWN」, DELIBERATELY, WHICH IS THE ONE PLACE THIS FILE
  //   DEPARTS FROM ITS OWN LOUD-FAIL HABIT.** The reason is deploy order and it is the identical
  //   argument the 러너 활동 comment above makes: a build that reaches a server without 0198 gets
  //   a missing-function error from `ops_me()` for EVERY user, and a failure strip here would put
  //   a permanent broken line on the settings screen of every 보호자 in the product about a
  //   feature that is not theirs. The console is reachable at `/ops` regardless — this row is a
  //   shortcut, not the only path — and the gate behind it is the server's, so silence costs an
  //   operator one retry and costs everyone else nothing.
  const [isOps, setIsOps] = useState(false);
  const loadProfile = useCallback(() => {
    setProfileErr(false);
    fetchMyProfile().then(setProfile).catch((e) => {
      console.warn('[settings] profile:', (e as Error)?.message ?? e);
      setProfileErr(true);
    });
    opsMe()
      .then((me) => setIsOps(me.isOps))
      .catch((e) => {
        console.warn('[settings] ops_me:', (e as Error)?.message ?? e);
        setIsOps(false);
      });
  }, []);
  useEffect(() => { loadProfile(); }, [loadProfile]);

  // 화면에 돌아올 때마다 다시 읽는다 — 핀 화면에서 저장/삭제하고 back으로 오면 이 줄이 낡는다.
  useFocusEffect(
    useCallback(() => {
      let alive = true;
      fetchMyRunnerBase()
        .then((b) => {
          if (!alive) return;
          if (b == null) { setBase('none'); setLockedUntil(null); return; }
          setLockedUntil(b.canChangeAt);
          setBase(b.lat != null && b.lng != null ? 'set' : 'unset');
        })
        .catch((e) => {
          console.warn('[settings] runner base:', (e as Error)?.message ?? e);
          if (alive) setBase('error');
        });
      return () => { alive = false; };
    }, []),
  );

  return (
    <ScrollView style={{ flex: 1, backgroundColor: paper.canvas }} contentContainerStyle={{ paddingHorizontal: layout.gutter, paddingTop: insets.top, paddingBottom: 40 }}>
      <ScreenHead title="설정" />

      {/* 계정 (실정보) — paper grammar: a full-bleed coral rule and a 20/800 title divide the
          sections; rows inside separate with neutral #EEE (DESIGN.md §2 · §3b). No cards. */}
      <View style={s.rule} />
      <Text style={s.section}>계정</Text>
      <InfoRow label="이메일" value={auth?.user.email ?? '—'} />
      <View style={s.div} />
      <InfoRow label="이름" value={profile?.name ?? '—'} />
      <View style={s.div} />
      <InfoRow label="현재 모드" value={session.role === 'runner' ? '러너' : '보호자'} />

      {/* 이메일·현재 모드는 로컬에서 오고 이름만 서버에서 온다 — 그래서 실패는 행 아래 한 줄이다. */}
      {profileErr && (
        <View style={s.failStrip}>
          <Text style={{ fontSize: 15, lineHeight: 21, fontWeight: '800', color: paper.critical }}>
            내 정보를 불러오지 못했어요
          </Text>
          <Pressable onPress={loadProfile} accessibilityRole="button" style={s.retryBtn}>
            <Text style={{ fontSize: 16, fontWeight: '800', color: paper.critical, textDecorationLine: 'underline' }}>
              다시 시도
            </Text>
          </Pressable>
        </View>
      )}

      {/* 실동작 — an untitled section: the rule alone separates it from 계정 */}
      <View style={s.rule} />
      <View>
        <Pressable onPress={() => router.dismissTo('/')} style={s.actionRow} accessibilityRole="button">
          <Text style={s.actionText}>역할 전환 (보호자 ↔ 러너)</Text>
          <Text style={s.chev}>›</Text>
        </Pressable>
        <View style={s.div} />
        {/* [charge slice 2026-08-13] 준비 중 카드의 '결제 수단 — PG 연동 후' InfoRow가 여기로 승격.
            실화면이 생겼다: 등록된 카드·청구 내역·실패한 청구의 재시도가 전부 서버 진실이다. */}
        <Pressable onPress={() => router.push('/payments')} style={s.actionRow} accessibilityRole="button">
          <Text style={s.actionText}>결제 관리</Text>
          <Text style={s.chev}>›</Text>
        </Pressable>
        <View style={s.div} />
        {/* [0187] 준비 중 카드의 '알림 설정 — 푸시 도입 후' InfoRow가 여기로 승격.
            그 라벨은 2026-08-13에 쓰인 뒤로 계속 거짓이었다: 푸시는 0024부터 나가고 있었고
            (push_tokens + notifications_push 트리거 → Expo), 없던 것은 끄는 문 하나뿐이었다.
            이제 카테고리별 스위치가 서버의 notification_prefs를 쓰고, 그 값이 발송 경로
            (notify_push)를 실제로 가른다 — 화면만 있는 설정이 아니다. */}
        <Pressable onPress={() => router.push('/notification-settings')} style={s.actionRow} accessibilityRole="button">
          <Text style={s.actionText}>알림 설정</Text>
          <Text style={s.chev}>›</Text>
        </Pressable>
        <View style={s.div} />
        <Pressable
          onPress={() => Linking.openURL('mailto:seankookim@uchicago.edu?subject=도그스하이 문의')}
          style={s.actionRow}
          accessibilityRole="button"
        >
          <Text style={s.actionText}>문의하기</Text>
          <Text style={s.chev}>›</Text>
        </Pressable>
        <View style={s.div} />
        <Pressable
          onPress={async () => { await signOut(); router.dismissTo('/login'); }}
          style={s.actionRow}
          accessibilityRole="button"
        >
          <Text style={[s.actionText, s.endSession]}>로그아웃</Text>
        </Pressable>
        <View style={s.div} />
        {/* [O-6 2026-08-20] 계정 삭제는 '준비 중 · 문의로 처리' InfoRow에서 여기로 승격.
            App Store 5.1.1(v)는 인앱 개시를 요구한다 — 문의 메일은 개시가 아니고,
            비활성 카드 안의 회색 라벨은 '찾을 수 있는' 위치도 아니다 (계약 §C.2 1).
            로그아웃과 같은 잉크: 둘 다 세션을 끝내는 행이고, 무게 차이는 시트가 진다.
            (2026-09-25: the untokenized coral hex became paper.critical — the destructive label
            ink of the button matrix.) */}
        <Pressable onPress={() => setDeleteOpen(true)} style={s.actionRow} accessibilityRole="button">
          <Text style={[s.actionText, s.endSession]}>계정 삭제</Text>
          <Text style={s.chev}>›</Text>
        </Pressable>
      </View>

      {/* 운영 — [0198] 운영 담당자에게만. is_ops가 false이거나 확인에 실패하면 섹션째로 없다
          (위의 isOps 주석에 그 둘을 같게 처리하는 이유가 적혀 있다). */}
      {isOps && (
        <>
          <View style={s.rule} />
          <Text style={s.section}>운영</Text>
          <View>
            <Pressable
              onPress={() => router.push('/ops')}
              style={s.actionRow}
              accessibilityRole="button"
              accessibilityLabel="운영 콘솔"
            >
              <View style={{ flex: 1, paddingRight: 10 }}>
                <Text style={s.actionText}>운영 콘솔</Text>
                {/* The console draws five desks (지급 대기 · 배송 대기 · 반환 좌초 · 인계 멈춤 ·
                    운영자 명단) and the old hint named two, so it read as the whole of it. This
                    sentence names the two KINDS of work instead of a partial list. */}
                <Text style={s.actionHint}>운영 대기열과 담당자 알림을 여기서 처리해요</Text>
              </View>
              <Text style={s.chev}>›</Text>
            </Pressable>
          </View>
        </>
      )}

      {/* 러너 활동 — 러너 계정에서만. 「없는 문을 만들지 않는다」: 러너가 아니면 섹션째로 없다.
          [0123 · Sean's Q6 ruling B 2026-08-25, verbatim: 「go with B for distance, and the runner
          should be able to switch this address in settings.」] 이 줄이 그 "settings"다.
          로딩 중에도 섹션을 그리는 이유: 러너에게 이 문이 **깜빡였다 나타나는** 것보다, 있는 줄
          알고 들어와서 상태를 읽는 편이 낫다. 값 자리에는 「확인 중…」이 서고 0도 「미설정」도 아니다. */}
      {(base === 'set' || base === 'unset' || base === 'loading') && (
        <>
          <View style={s.rule} />
          <Text style={s.section}>러너 활동</Text>
          <View>
            <Pressable
              onPress={() => router.push('/runner/base-pin')}
              style={s.actionRow}
              accessibilityRole="button"
              accessibilityLabel="활동 기준 위치 설정"
            >
              <View style={{ flex: 1, paddingRight: 10 }}>
                <Text style={s.actionText}>활동 기준 위치</Text>
                {/* 반올림을 여기서도 말한다 — 러너가 문을 열기 전에 무엇이 저장되는지 안다.
                    이건 사과가 아니라 기능이다: 우리는 러너가 어디 사는지 정확히 알고 싶지 않다. */}
                <Text style={s.actionHint}>
                  {base === 'set'
                    ? `요청 카드에 출발지까지 대략 거리가 표시돼요 · 약 1km 격자로만 저장돼요${lockSuffix(lockedUntil)}`
                    : base === 'unset'
                      ? '지정하면 요청 카드에 출발지까지 대략 거리가 보여요'
                      : '확인 중…'}
                </Text>
              </View>
              <Text style={s.baseValue}>
                {base === 'set' ? '지정됨' : base === 'unset' ? '설정 안 됨' : '확인 중…'}
              </Text>
              <Text style={[s.chev, { marginLeft: 6 }]}>›</Text>
            </Pressable>
          </View>
        </>
      )}

      {/* 연락처 — [Sean 2026-08-28] 「guest is a member and needs a phone number enter thing.」
          섹션 전체(게이트 읽기·상태 기계·문구·실패 처리)는 `src/components/phone-row.tsx`가 가진다.
          여기서 마운트만 하는 이유가 둘이고 두 번째가 더 중요하다: ① 이 화면은 이미 커서
          react-doctor 의 `no-giant-component` 에 걸렸다 — **측정했다, 이 슬라이스 전 27건 후 28건이고
          늘어난 하나가 이 파일이었다**; ② 언젠가 클럽 세션 화면에도 같은 문이 필요해지면 그 화면은
          이걸 그대로 마운트하면 되고, 게이트와 문구를 두 벌로 만들지 않는다.
          ⚠ 게이트가 닫혀 있으면(=오늘의 상태) 이 컴포넌트는 **null 을 반환한다** — 섹션 자체가 없다. */}
      <PhoneRow />

      {/* DEV 전용 — 프로덕션 빌드에선 렌더되지 않음 (__DEV__ 게이트, 화면 자체도 이중 게이트) */}
      {__DEV__ && (
        <View style={s.devCard}>
          <Pressable onPress={() => router.push('/dev/club-lab')} style={s.actionRow} accessibilityRole="button">
            <Text style={[s.actionText, { color: '#4A3DA8' }]}>R2 커스터디 랩 (DEV)</Text>
            <Text style={s.chev}>›</Text>
          </Pressable>
        </View>
      )}

      {/* [0187] 준비 중 섹션 삭제. 계정 삭제가 O-6에서 떠난 뒤 남아 있던 단 한 줄이
          「알림 설정 · 푸시 도입 후」였고, 그것이 실동작 카드로 승격하면서 카드가 비었다.
          빈 준비 중 카드는 아무것도 말하지 않으면서 자리를 차지한다 — 섹션째 뺀다.
          다시 준비 중인 것이 생기면 s.cardPending 과 InfoRow 의 muted 가 그대로 기다리고 있다
          (두 스타일은 다음 승격 대기열의 문법이므로 남겨둔다). */}
      <Text style={{ fontSize: 15, color: paper.dim, textAlign: 'center', marginTop: 18 }}>
        도그스하이 {APP_VERSION} · 반려견 피트니스
      </Text>

      {/* 열려 있을 때만 마운트 — 시트의 상태(거절 문구·꾹 누름 확인)가 다음 열기로 새지 않는다 */}
      {deleteOpen && <DeleteAccountSheet onClose={() => setDeleteOpen(false)} />}
    </ScrollView>
  );
}

// muted = the 준비 중 card's non-interactive row. Ink, not alpha (theme.ts:205-207).
function InfoRow({ label, value, muted }: { label: string; value: string; muted?: boolean }) {
  return (
    <Row style={{ justifyContent: 'space-between', paddingVertical: 12 }}>
      <Text style={{ fontSize: 15.5, color: muted ? paper.dim : paper.text }}>{label}</Text>
      <Text style={{ fontSize: 15.5, fontWeight: '700', color: muted ? paper.dim : paper.ink }} numberOfLines={1}>{value}</Text>
    </Row>
  );
}

const s = StyleSheet.create({
  // full-bleed: the rule escapes the scroll gutter so it runs edge to edge (DESIGN.md §2)
  rule: { height: 1, backgroundColor: paper.line, marginHorizontal: -layout.gutter, marginTop: 22 },
  section: { fontSize: 20, lineHeight: 25, fontWeight: '800', color: paper.ink, marginTop: 14, marginBottom: 2 }, // → theme.secTitle
  // __DEV__-only club-lab entry: left as its own violet-bordered box (never ships), corners squared
  devCard: { marginTop: 10, paddingHorizontal: 15, borderWidth: 1, borderColor: '#7B6CDF' },
  cardPending: { backgroundColor: paper.disabledFill }, // 준비 중 card — explicit fill, no alpha
  div: { height: 1, backgroundColor: '#EEEEEE' },
  chev: { fontSize: 16, color: paper.dim },
  endSession: { color: paper.critical },
  actionRow: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', paddingVertical: 14 },
  actionText: { fontSize: 16, fontWeight: '700', color: paper.ink },
  // 15pt 플로어 + paper.dim(5.7:1) — 디테일 텍스트 법 (theme.ts)
  actionHint: { fontSize: 15, lineHeight: 19, fontWeight: '600', color: paper.dim, marginTop: 3 },
  baseValue: { fontSize: 15.5, fontWeight: '700', color: paper.ink },
  // loud-fail strip — criticalWash ground, critical ink, underlined retry ≥44pt (house grammar)
  failStrip: { backgroundColor: paper.criticalWash, padding: 13, marginTop: 10 },
  retryBtn: { alignSelf: 'flex-start', marginTop: 8, minHeight: 44, justifyContent: 'center' },
});
