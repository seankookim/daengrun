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
 * 🔴 목적지 한계, 지금 시점의 사실: `/runner-profile/[id]` 는 `runners` 테이블을 읽고
 *   러너가 아니면 NOT_FOUND 를 던진다 (api.ts fetchRunnerProfile). 그래서 **보호자·크루
 *   이름은 아직 문이 아니다** — 누르면 반드시 「없음」 화면에 닿는데, 그건 정직한 문구를 단
 *   막다른 골목일 뿐 여전히 막다른 골목이다. 사람 일반 프로필 화면이 landing 되는 즉시 이
 *   조건 하나만 풀면 된다 (announcer 세션의 에이전트가 만드는 중).
 */
function PersonName({ name, id, kind, bold }: {
  name: string | null; id: string | null; kind: 'runner' | 'person'; bold?: boolean;
}) {
  const base = { fontSize: 15, lineHeight: 21, color: bold ? paper.ink : paper.dim,
                 fontWeight: (bold ? '800' : '400') as '800' | '400' };
  if (!name) return null;
  // `kind`는 스타일이 아니라 **목적지가 있느냐**다. 러너만 프로필 화면이 있다 (위 주석).
  const canOpen = id != null && kind === 'runner';
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
              {r.dogName == null && isCrew ? <PersonName name={r.ownerName} id={r.ownerProfileId} kind="person" bold /> : null}
            </Text>
            {!isCrew && r.ownerName && <PersonName name={r.ownerName} id={r.ownerProfileId} kind="person" />}
            {r.isMine && (
              <Text style={{ fontSize: 15, lineHeight: 21, fontWeight: '800', color: '#6C5CE7' }}>내 아이</Text>
            )}

            {/* 점선 리더 — 랩 ①의 문법. 이름과 상태 사이를 눈이 따라간다 */}
            <View style={{ flex: 1, minWidth: 10, borderBottomWidth: 1.5, borderStyle: 'dotted',
                           borderColor: '#E4E3DF', transform: [{ translateY: -3 }] }} />

            {/* 러너 이름 — 수락 전에는 서버가 null을 준다. 없으면 그 자리는 비어 있다. */}
            {r.runnerName && <PersonName name={r.runnerName} id={r.runnerProfileId} kind="runner" />}
            <Text style={{ fontSize: 15, lineHeight: 21, fontWeight: '800', color: stateInk(r.state) }} numberOfLines={1}>
              {r.state}
            </Text>
          </Pressable>
        );
      })}
    </View>
  );
}
