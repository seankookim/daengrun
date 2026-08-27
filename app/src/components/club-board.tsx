// 클럽 보드 — 랩 ① 「핀 보드」 (Sean 픽). 서버는 0136 `club_session_board`.
//
// ═══ 왜 한 줄이 한 개인가 ═══
// Sean: 「the club will be running in a pack」. 그래서 이 보드는 열두 개의 독립 상태가 아니라
// **한 무리와 그 무리에서 벗어난 예외**를 그린다. 줄마다 상태 낱말이 있지만, 같은 낱말이 반복되면
// 그것이 팩의 상태다 — 다르게 읽히는 줄만 눈에 띈다.
//
// ═══ 이 컴포넌트가 걸러내는 것은 없다 ═══
// 주소·금액·전화·사건·아직 수락 안 한 러너 이름은 **애초에 오지 않는다** (계약 §4 R1~R8을
// 서버 시그니처가 강제한다). 클라이언트 필터링은 한 줄도 없고, 있어서도 안 된다 — 여기서 거르면
// 다음 화면이 거르는 걸 잊는다.
//
// ═══ BABY WORK (DESIGN.md §7a-bis) ═══
// 줄 하나 = 개 이름 · 보호자 · 상태. 설명 문단 없음. dim은 보호자 이름과 러너 이름까지만.
import { router } from 'expo-router';
import { Pressable, Text, View } from 'react-native';
import { BoardRowLive } from '../lib/api';
import { useNumFont } from '../lib/fonts';
import { paper } from '../theme';

// 목줄 색 — 줄마다 다른 테두리. 데이터가 아니라 **자리**로 정한다 (seq): 색이 어떤 사실을
// 주장하면 그 사실이 서버에 있어야 하는데, 없다. 자리색은 아무것도 주장하지 않으면서 열두 줄을
// 서로 구별되게 만든다.
const COLLARS = ['#E45F41', '#4A8FD6', '#D6568C', '#2FA39B', '#6E9B3A', '#C9A227', '#6C5CE7'];

// 상태 잉크 — 서버 낱말 그대로 받고, 색만 여기서 고른다. 매핑되지 않은 낱말은 기본 잉크로
// 그린다: 새 상태가 생겼을 때 화면이 침묵하거나 영어 토큰을 뱉는 대신 **그 낱말을 그대로**
// 보여준다 (CHARGE_LABEL 이 남긴 교훈).
function stateInk(state: string): string {
  if (state === '귀가 완료') return paper.dim;
  if (state === '러닝 중' || state === '픽업 이동 중' || state === '이동 중') return paper.action;
  if (state === '수락 대기' || state === '러너 선택 중' || state === '대기 중') return '#9A5A0E';
  if (state === '보호자 동반' || state === '함께 달려요') return paper.ink;
  return paper.ink;
}

/**
 * 이름 한 조각 = 문 하나. 아이디가 있으면 프로필로 가고, 없으면 **그냥 글자**다.
 *
 * ⚠ 아이디가 없는 경우는 두 가지이고 둘 다 눌러선 안 된다: (a) 수락 전 제안이라 서버가 일부러
 *   가렸다(0139 · R3), (b) 목적지가 아직 그 사람을 모른다. 둘 다 「눌리는 것처럼 보이는데 아무 데도
 *   못 가는 글자」가 되면 죽은 버튼이므로, 밑줄도 색도 주지 않는다.
 *
 * 🔴 The paragraph that used to sit here said the destination throws NOT_FOUND for anyone who is
 *   not a runner, so owner and crew names could not be doors. **It was wrong in both halves, and
 *   it had become the reason nobody re-checked.** Measured on the screen itself before this
 *   change: `/runner-profile/[id]` renders its header and grid from `fetchProfileIdentity`
 *   (`runner-profile/[id].tsx:23` — 「누구에게나 있다」), and a missing `runners` row only sets
 *   `runnerState = 'none'`, which hides the runner sections. The screen degrades; it does not
 *   dead-end.
 *
 *   The real dead end was one layer down and invisible from here: `profiles` had three SELECT
 *   arms (self · non-applicant runner · tombstone) and a live non-runner was in none of them, so
 *   `fetchProfileIdentity` returned ZERO ROWS. **0145 adds the fourth arm** — a policy whose
 *   predicate calls `club_session_board`, so a card can only open for someone the board already
 *   showed you. R3's courtship refusal is inherited rather than re-implemented.
 *
 * ⚠ DEPLOY ORDER: this change assumes 0145 is applied. Migration first, then the app build —
 *   the standing order in this repo. Shipped ahead of it, a tap still fails HONESTLY (the screen
 *   reports it could not read the profile) rather than dead-ending, so this is an ordering
 *   preference, not a safety gate.
 */
function PersonName({ name, id, bold }: {
  name: string | null; id: string | null; bold?: boolean;
}) {
  const base = { fontSize: 15, lineHeight: 21, color: bold ? paper.ink : paper.dim,
                 fontWeight: (bold ? '800' : '400') as '800' | '400' };
  if (!name) return null;
  // `id != null` is now the WHOLE gate. The `kind` prop existed only to say 「러너에게만 목적지가
  // 있다」, which 0145 made false — so it is gone rather than left to read as a live rule.
  // A null id still means exactly what it meant: either the server gated the name (0139 R3, a
  // proposal not yet accepted) or the row carries no person. Neither is pressable.
  const canOpen = id != null;
  if (!canOpen) return <Text style={base} numberOfLines={1}>{name}</Text>;
  return (
    <Pressable onPress={() => router.push(`/runner-profile/${id}`)} hitSlop={6}
      accessibilityRole="link" accessibilityLabel={`${name} 프로필 열기`}>
      <Text style={[base, { textDecorationLine: 'underline' }]} numberOfLines={1}>{name}</Text>
    </Pressable>
  );
}

export function ClubBoard({ rows }: { rows: BoardRowLive[] }) {
  const nf = useNumFont();

  // 팩 요약 — 서버 행을 세는 것뿐이다. 어떤 수도 지어내지 않는다.
  const dogs = rows.filter((r) => r.kind !== 'crew');
  const crew = rows.filter((r) => r.kind === 'crew');

  return (
    <View>
      {/* 카운트 줄 — 숫자는 Oswald, 명시 lineHeight ≥1.2× (BUG A) */}
      <View style={{ flexDirection: 'row', gap: 18, paddingVertical: 14 }}>
        <Text style={{ fontSize: 15, lineHeight: 21, fontWeight: '700', color: paper.dim }}>
          강아지 <Text style={[{ fontSize: 19, lineHeight: 24, fontWeight: '600', color: paper.ink }, nf]}>{dogs.length}</Text>
        </Text>
        <Text style={{ fontSize: 15, lineHeight: 21, fontWeight: '700', color: paper.dim }}>
          함께 뛰는 사람 <Text style={[{ fontSize: 19, lineHeight: 24, fontWeight: '600', color: paper.ink }, nf]}>{crew.length}</Text>
        </Text>
      </View>

      {rows.map((r, i) => {
        const collar = COLLARS[i % COLLARS.length];
        const isCrew = r.kind === 'crew';
        return (
          <Pressable
            key={`${r.kind}-${r.seq ?? i}-${r.dogName ?? r.ownerName ?? i}`}
            // [0139] Sean 2026-08-27 「for the tap for profile, yes make it like instagram」 —
            // R8이 뒤집혔고 서버가 아이디를 준다. 행 전체가 아니라 **이름 각각**이 문이다
            // (그의 표현: 「clicking on each names」): 한 행에 보호자와 러너 두 사람이 있고,
            // 행을 통째로 누르면 둘 중 누구에게 가는지 화면이 정하게 된다.
            accessibilityRole="none"
            accessibilityLabel={`${r.dogName ?? r.ownerName ?? ''} ${r.state}`}
            style={{
              flexDirection: 'row', alignItems: 'center', gap: 9, minHeight: 56,
              paddingVertical: 12, paddingHorizontal: 13,
              backgroundColor: '#FFFFFF', borderWidth: 1, borderColor: '#E4E3DF',
              marginTop: i === 0 ? 0 : -1,
            }}
          >
            {/* 목줄 점 — 개는 채운 원, 사람은 빈 사각 (두 종류를 재질로 가른다) */}
            {isCrew ? (
              <View style={{ width: 28, height: 28, borderWidth: 1.5, borderColor: '#E4E3DF',
                             alignItems: 'center', justifyContent: 'center' }}>
                <Text style={{ fontSize: 15, lineHeight: 20, fontWeight: '800', color: paper.dim }}>人</Text>
              </View>
            ) : (
              <View style={{ width: 28, height: 28, borderRadius: 14, borderWidth: 2, borderColor: collar,
                             alignItems: 'center', justifyContent: 'center' }}>
                <Text style={{ fontSize: 15, lineHeight: 20, fontWeight: '800', color: paper.ink }}>
                  {(r.dogName ?? '?').slice(0, 1)}
                </Text>
              </View>
            )}

            <Text style={{ fontSize: 15, lineHeight: 21, fontWeight: '800', color: paper.ink }} numberOfLines={1}>
              {r.dogName ?? (isCrew ? null : '참가자')}
              {r.dogName == null && isCrew ? <PersonName name={r.ownerName} id={r.ownerProfileId} bold /> : null}
            </Text>
            {!isCrew && r.ownerName && <PersonName name={r.ownerName} id={r.ownerProfileId} />}
            {r.isMine && (
              <Text style={{ fontSize: 15, lineHeight: 21, fontWeight: '800', color: '#6C5CE7' }}>내 아이</Text>
            )}

            {/* 점선 리더 — 랩 ①의 문법. 이름과 상태 사이를 눈이 따라간다 */}
            <View style={{ flex: 1, minWidth: 10, borderBottomWidth: 1.5, borderStyle: 'dotted',
                           borderColor: '#E4E3DF', transform: [{ translateY: -3 }] }} />

            {/* 러너 이름 — 수락 전에는 서버가 null을 준다. 없으면 그 자리는 비어 있다. */}
            {r.runnerName && <PersonName name={r.runnerName} id={r.runnerProfileId} />}
            <Text style={{ fontSize: 15, lineHeight: 21, fontWeight: '800', color: stateInk(r.state) }} numberOfLines={1}>
              {r.state}
            </Text>
          </Pressable>
        );
      })}
    </View>
  );
}
