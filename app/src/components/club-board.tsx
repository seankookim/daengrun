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
            // ⚠ 프로필로 가는 문은 Sean의 요구지만(「clicking on each names should go to their
            //   profiles」), 이 보드는 R8에 따라 **profile_id를 받지 않는다**. 그래서 지금은
            //   문을 그리지 않는다 — 죽은 버튼을 그리느니 없는 게 낫다. 서버가 id를 주기로
            //   결정되면(그건 공개 범위 결정이지 구현이 아니다) 이 자리가 그 문이다.
            accessibilityRole="text"
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
              {r.dogName ?? r.ownerName ?? '참가자'}
            </Text>
            {!isCrew && r.ownerName && (
              <Text style={{ fontSize: 15, lineHeight: 21, color: paper.dim }} numberOfLines={1}>{r.ownerName}</Text>
            )}
            {r.isMine && (
              <Text style={{ fontSize: 15, lineHeight: 21, fontWeight: '800', color: '#6C5CE7' }}>내 아이</Text>
            )}

            {/* 점선 리더 — 랩 ①의 문법. 이름과 상태 사이를 눈이 따라간다 */}
            <View style={{ flex: 1, minWidth: 10, borderBottomWidth: 1.5, borderStyle: 'dotted',
                           borderColor: '#E4E3DF', transform: [{ translateY: -3 }] }} />

            {/* 러너 이름 — 수락 전에는 서버가 null을 준다. 없으면 그 자리는 비어 있다. */}
            {r.runnerName && (
              <Text style={{ fontSize: 15, lineHeight: 21, color: paper.dim }} numberOfLines={1}>{r.runnerName}</Text>
            )}
            <Text style={{ fontSize: 15, lineHeight: 21, fontWeight: '800', color: stateInk(r.state) }} numberOfLines={1}>
              {r.state}
            </Text>
          </Pressable>
        );
      })}
    </View>
  );
}
