// ═══════════ 프로필 빈칸 넛지 — 랩 ①, Sean 선택 (2026-08-25) ═══════════
// 정본: docs/labs/profile-nudge-lab.html ① (「리포트 하단 — 추천」).
//
// ⚠⚠ 이 파일은 **뒤집힌 결정**을 담고 있다. 아래 ②의 도장은 지우지 않는다 (승계, 삭제 아님).
//
// [2026-08-25 · Sean, 콘솔 판정 #18] 그의 말 그대로: **"approve on everything."**
// (콘솔 아티팩트 aad92054, 04:31:30Z. 기록: docs/decisions/2026-08-25-console-rulings.md #18,
// 그 번들 줄이 "the profile-nudge lab (① recommended) … proceed as picked" 이고 그 처분은
// "Each item's own record governs details" 라고 적는다 — 그 record 가 이 랩이다.)
// → **①이 ②를 대체한다.** 넛지는 홈의 상시 행이 아니라 **첫 러닝 리포트의 맨 아래**로 간다.
//    owner/home.tsx 의 렌더 자리는 같은 슬라이스에서 제거됐고, 그 자리에도 같은 도장을 남겼다.
//
// ⚠ 「나중에 할게요」 — 여기서 두 판정이 부딪친다. 숨기지 않고 적어둔다.
//   · 2026-08-21 (ruling #3, ②): Sean 이 일주일 스누즈를 **직접 뺐다** → "닫기 없음"이 ②의 법이었다.
//   · 2026-08-25 (판정 #18, ①): 그가 고른 ①의 프레임은 하단에 「나중에 할게요」를 **그린다**.
//   랩이 이긴다 (그는 그려진 대로의 ①을 승인했다). 다만 되살린 것은 스누즈가 **아니다**:
//   이 닫기는 **저장되지 않는다** — 이번 리포트 보기 동안만 접힌다. 리포트를 다시 열면
//   빈칸이 남아 있는 한 다시 나온다. ①의 평결 상자가 이미 그렇게 적었다
//   ("차단이 전혀 없고, 리포트를 닫으면 그냥 사라집니다"). 죽은 버튼도 아니고(진짜로 접힌다),
//   '해결'과 '숨김'이 같은 모양이 되지도 않는다(숨김은 다음 진입에 살아남지 못한다).
//
// ⚠ 랩의 이모지(🐾 💉 🚪)는 랩 속기다. 이 앱의 UI 는 이모지를 하나도 렌더하지 않는다
//   (트리 전체에서 이모지는 주석의 🔴 표식뿐). 그래서 아이콘 칸만 빼고 ①의 구조는 그대로
//   가져온다 — 잉크 아웃라인 행 · 제목 · **러너에게 무엇이 달라지는지** · 셰브런.
//
// ⚠ 코랄 아님: 리포트 프레임의 채도 있는 요소는 이미 재예약 패널이 갖고 있다 (RULING #11).
//   화면당 코랄 하나 법(DESIGN.md §5) 그대로 — 이 블록은 잉크다. ②가 홈에서 잉크였던 것과
//   같은 이유이고, 랩 ②의 평결 상자가 그 충돌을 미리 적어둔 바로 그 이유다.
//
// ─── 아래는 ②의 원래 도장. 승계됐지만 지우지 않는다 (2026-08-21 ~ 2026-08-25 출하분) ───
// ═══════════ 프로필 빈칸 행 — ruling #3, Sean 선택 ② (2026-08-21) ═══════════
// 정본: docs/labs/profile-nudge-lab.html ②.
//
// ⚠ 왜 코랄이 아닌가: ②는 홈에 사는 행이고, 홈의 코랄은 이미 예약 CTA 가 갖고 있다. 화면당
// 코랄 하나 법(DESIGN.md §5)이 그대로 적용되므로 이 행은 **잉크 아웃라인**이다 — 러너 홈에서
// 채팅이 코랄 대신 잉크가 된 것과 같은 해법이다. 랩의 ② 평결 상자가 이 충돌을 미리 적어뒀고,
// Sean 은 그걸 읽고 ②를 골랐다.
//
// ⚠ 첫 러닝 **후에만**, 그리고 차단하지 않는다 (ruling #3 의 세 조건 중 둘). 호출부가 지킨다.
//
// ⚠ 닫기 없음 (Sean 2026-08-21). 처음엔 일주일 스누즈를 달았는데 그가 뺐다 — 옳다: 이 세 칸은
// 러너가 실제로 겪는 결핍이고, 채워지면 행이 스스로 사라진다. 사라지는 조건이 이미 있는데 닫기를
// 더하면 '해결'과 '숨김'이 같은 모양이 된다.
// ─── ②의 도장 끝 ───
import { useState } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import type { ProfileGap } from '../lib/api';
import { paper } from '../theme';
import { haptic } from '../lib/haptics';

/** 각 빈칸이 **러너에게 무엇을 바꾸는지**. 「프로필을 완성하세요」가 스팸인 이유는 이걸 말하지
 *  않기 때문이다 — 셋 다 러너가 실제로 보는, 이미 배포된 화면을 가리킨다:
 *  사진 → 러너 티켓 B · 백신 → MeetupInfo · 현관 상세 → 티켓 D(door-level address).
 *  ⚠ 연락처는 넣지 않는다: `profiles.phone` 은 전원 NULL 이고 읽는 화면이 없다. 받아두고
 *  아무 데도 안 쓰면 넛지가 아니라 수집이다 (랩의 공통 노트). */
const GAP: Record<ProfileGap, { label: string; effect: string }> = {
  photo: { label: '사진', effect: '러너 티켓에 얼굴이 떠요' },
  vaccines: { label: '백신 정보', effect: '인계할 때 러너가 확인해요' },
  doorDetail: { label: '현관 상세', effect: '문 앞에서 헤매지 않아요' },
};

export function ProfileGaps({ gaps, dogName, onOpen }: {
  gaps: ProfileGap[];
  /** 아이 이름 — 있으면 사진 줄이 「초코 사진」이 된다 (랩 ①의 문구). 없으면 그냥 「사진」.
   *  모르는 이름을 지어내지 않는다. */
  dogName?: string | null;
  onOpen: (gap: ProfileGap) => void;
}) {
  // 이번 화면 보기 동안만 사는 접힘. 저장하지 않는다 (파일 머리의 두 판정 참고).
  const [later, setLater] = useState(false);

  if (gaps.length === 0) return null; // 다 채워졌으면 사라진다 — 축하 배너를 만들지 않는다
  if (later) return null;

  return (
    <View style={s.wrap}>
      <Text style={s.kicker}>프로필을 마저 채우면</Text>
      {gaps.map((g) => {
        const title = g === 'photo' && dogName ? `${dogName} 사진` : GAP[g].label;
        return (
          <Pressable
            key={g}
            onPress={() => { haptic('light'); onOpen(g); }}
            style={({ pressed }) => [s.gap, pressed && { backgroundColor: paper.wash }]}
            accessibilityRole="button"
            accessibilityLabel={`${title} — ${GAP[g].effect}`}
          >
            <View style={{ flex: 1, minWidth: 0 }}>
              <Text style={s.gapTitle}>{title}</Text>
              <Text style={s.gapSub} numberOfLines={2}>{GAP[g].effect}</Text>
            </View>
            <Text style={s.gapChev}>›</Text>
          </Pressable>
        );
      })}
      <Pressable
        onPress={() => { haptic('light'); setLater(true); }}
        style={({ pressed }) => [s.later, pressed && { backgroundColor: paper.wash }]}
        accessibilityRole="button"
        accessibilityLabel="나중에 할게요 — 이 화면에서만 접어요"
      >
        <Text style={s.laterTx}>나중에 할게요</Text>
      </Pressable>
    </View>
  );
}

const s = StyleSheet.create({
  wrap: { paddingHorizontal: 12, paddingVertical: 16 },
  // 킥커도 14pt — 한글은 레터스페이스 면제 대상이 아니다 (면제는 라틴 대문자 킥커뿐).
  kicker: { fontSize: 14, lineHeight: 18, fontWeight: '800', letterSpacing: 1.2, color: paper.dim, marginBottom: 8 },
  // 잉크 아웃라인 — 코랄은 재예약 패널의 것이다 (위 주석).
  gap: {
    flexDirection: 'row', alignItems: 'center', gap: 11,
    borderWidth: 1.5, borderColor: paper.ink, backgroundColor: paper.canvas,
    paddingVertical: 11, paddingHorizontal: 13, marginTop: 7,
  },
  gapTitle: { fontSize: 15.5, lineHeight: 20, fontWeight: '800', color: paper.ink, letterSpacing: -0.2 },
  gapSub: { fontSize: 14, lineHeight: 19, color: paper.dim, marginTop: 2 },
  gapChev: { fontSize: 18, lineHeight: 22, color: paper.actionInk },
  later: { alignItems: 'center', paddingVertical: 11, marginTop: 4 },
  laterTx: { fontSize: 14, lineHeight: 19, color: paper.dim },
});
