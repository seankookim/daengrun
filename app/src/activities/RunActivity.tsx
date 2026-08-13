import { HStack, Image, Text, VStack } from '@expo/ui/swift-ui';
import { background, border, font, foregroundStyle, padding } from '@expo/ui/swift-ui/modifiers';
import { createLiveActivity, type LiveActivityEnvironment } from 'expo-widgets';

// 러닝 라이브 액티비티 — 잠금화면 배너 + 다이내믹 아일랜드.
// 러너의 폰에서 러닝 중 항상 보이는 상태: 강아지·거리/목표·페이스·경과.
// 업데이트는 앱이 update()를 호출할 때. [2026-08-08] 백그라운드 위치 태스크가 붙으면서
// 잠금화면에서도 살아있다: 백그라운드 픽스 → geo.ingestFixes → run.tsx 구독 → gpsKm 변경 →
// updateRunActivity (5초 스로틀). 앱이 종료(스와이프)되면 추적도 배너도 함께 끝난다.

export type RunActivityProps = {
  dogName: string;
  km: string;        // '2.34' — 표시용 고정 포맷
  targetKm: string;  // '3'
  pace: string;      // "7'02\""
  elapsed: string;   // '23:41'
  eventLine: string; // '응가 1 · 물 2' ('' 가능)
  // 페이스 상태 (pace-state-ui-plan §1) — 클라이언트가 src/lib/pace.ts로 계산해서 넘긴다.
  // '' = 주장 없음 (게이트 미달·스테일·미상). 옵셔널: 이 prop을 모르는 구 페이로드는 ''와 같다.
  paceState?: '' | 'good' | 'slow';
};

const RunActivity = (props: RunActivityProps, env: LiveActivityEnvironment) => {
  'widget';

  // ⚠️ 모든 상수는 함수 안에 — 'widget' 함수는 문자열화되어 위젯 컨텍스트에서 실행되므로
  // 모듈 스코프 클로저가 존재하지 않는다 (CORAL ReferenceError의 원인, 2026-07-23)
  // [2026-08-10] Volt/forest retired here too — this was the last surface still speaking the old
  // language, and the one a runner stares at longest. Palette now follows the artifact world of
  // docs/labs/live-activity-lab.html §E: coral numerals, cream text, night dim. Layout and data
  // are untouched. The sibling OwnerRunActivity must keep these exact constants/names.
  const CORAL = '#FF5C3D';
  const CORAL_DEEP = '#E8552F'; // legible coral for light system material (lab --coralDeep)
  const CREAM = '#F8F6F0';      // lab --cream
  const DIM = '#9A93B5';        // lab --dim (night-violet dim, replaces forest #8fa093)

  // 잠금화면 배너 배경은 시스템(밝은 배경화면 = 밝은 소재)을 따르므로 텍스트를 스킴에 맞춘다 (HIG).
  // (expo-widgets exposes no activityBackgroundTint — a self-painted "night ground" is not
  //  available to this surface, so the banner keeps the adaptive convention with the new palette.)
  // 아일랜드 3종은 항상 검정 배경 — 고정 라이트 텍스트가 정답.
  const bannerText = env.colorScheme === 'dark' ? CREAM : '#111111';
  const bannerDim = env.colorScheme === 'dark' ? DIM : '#6b6478';
  const bannerAccent = env.colorScheme === 'dark' ? CORAL : CORAL_DEEP;

  // ---------- 페이스 상태 미니 필 (pace-state-ui-plan §3c, Sean D12 = Ⓒ② modified) ----------
  // 종이(페이퍼) 칩 문법을 OS 표면으로 그대로 가져온다: 워시 배경 + 딥 잉크 텍스트 + 라운드 0.
  // 라운드 0은 실수가 아니라 앱 전체 §3b 칩과 같은 문법이라는 선언이다. 워시가 자기 배경을
  // 들고 다니므로 밝은/어두운 잠금화면 소재 양쪽에서 대비가 칩 내부에서 완결된다.
  // 색은 함수 안 상수여야 한다 (위 ⚠️ 문자열화 법) — theme.ts에서 import할 수 없다.
  const PACE_GOOD_WASH = '#E7F5EE';
  const PACE_GOOD_INK = '#0E7F49';
  const PACE_SLOW_WASH = '#FBEED9';
  const PACE_SLOW_INK = '#9D580A';
  // 위젯은 계산하지 않는다 — 문자열 동등성 확인이 전부. 모르는 값/undefined는 전부 '주장 없음'.
  const paceState = props.paceState === 'good' || props.paceState === 'slow' ? props.paceState : '';
  const paceWash = paceState === 'good' ? PACE_GOOD_WASH : PACE_SLOW_WASH;
  const paceInk = paceState === 'good' ? PACE_GOOD_INK : PACE_SLOW_INK;
  const paceLabel = paceState === 'good' ? '양호' : '느림';
  // 색만으로 뜻을 나르지 않는다 (a11y §7): 필에는 언제나 텍스트 라벨이 붙어 있다.
  // 'heavy' = SwiftUI 800 (이 API엔 숫자 weight가 없다; 'bold'는 700).
  //
  // [2026-08-13] 잉크 엣지 1px — plan §3c가 허가한 폴백을 실측 후 채택했다.
  // 워시는 자기 배경을 들고 다니지만 '밝은 소재' 위에선 그 배경이 사라진다:
  // #E7F5EE vs 흰 소재 = 1.12:1 (사실상 무지). 글자는 여전히 읽히지만(5.06:1)
  // 칩이 '면'이 아니라 떠 있는 색 글자로 읽힌다 — §3b 칩 문법이 깨지는 지점.
  // 그래서 면의 경계를 색이 아니라 선으로 선언한다. 스킴 분기 대신 항상 그린다:
  // 잠금화면만 있는 게 아니라 StandBy·워치 스마트 스택·CarPlay 소재가 전부 다르고,
  // 자기 경계를 아는 칩은 그 전부에서 칩으로 읽힌다. (다크에선 이미 워시가 뜨므로
  // 선은 스탬프된 라벨의 테두리로 얹힌다 — 해가 없고, 코드 경로는 하나로 남는다.)
  const paceMods = [
    font({ weight: 'heavy' as const, size: 13 }),
    foregroundStyle(paceInk),
    padding({ horizontal: 6, vertical: 2 }),
    background(paceWash),
    border({ color: paceInk, width: 1 }),
    padding({ leading: 8 }),
  ];

  return {
    // ---------- 잠금화면 배너 (비-아일랜드 기기·StandBy·워치 스마트 스택도 이 뷰) ----------
    banner: (
      <VStack modifiers={[padding({ all: 14 })]}>
        <HStack>
          <Image systemName="pawprint.fill" color={bannerAccent} />
          <Text modifiers={[font({ weight: 'bold', size: 15 }), foregroundStyle(bannerText), padding({ leading: 6 })]}>
            {props.dogName} 러닝 중
          </Text>
          <Text modifiers={[font({ size: 12 }), foregroundStyle(bannerDim), padding({ leading: 8 })]}>
            {props.elapsed}
          </Text>
        </HStack>
        <HStack modifiers={[padding({ top: 8 })]}>
          {/* [2026-08-13] 히어로 숫자도 bannerAccent를 따른다. 밝은 소재에서 발·페이스는
              CORAL_DEEP로 내려가는데 숫자만 CORAL로 남아 있었다 — 한 줄에 두 개의 코랄이
              생겨 '밝은 버전'이 흐트러졌다(3.07:1 → 3.64:1로 덤). 아일랜드 3종은 항상 검정
              배경이라 아래에서 CORAL 고정을 유지한다. */}
          <Text modifiers={[font({ weight: 'bold', size: 30 }), foregroundStyle(bannerAccent)]}>
            {props.km}
          </Text>
          <Text modifiers={[font({ size: 14 }), foregroundStyle(bannerDim), padding({ leading: 3 })]}>
            / {props.targetKm}km
          </Text>
          <Text modifiers={[font({ size: 13 }), foregroundStyle(bannerAccent), padding({ leading: 12 })]}>
            {props.pace}/km
          </Text>
          {paceState !== '' ? <Text modifiers={paceMods}>{paceLabel}</Text> : null}
        </HStack>
        <Text modifiers={[font({ size: 12 }), foregroundStyle(bannerDim), padding({ top: 5 })]}>
          {props.eventLine !== '' ? props.eventLine : '도그스하이 · 반려견 피트니스'}
        </Text>
      </VStack>
    ),

    // ---------- 워치 스마트 스택 · CarPlay (작은 배너) ----------
    bannerSmall: (
      <HStack modifiers={[padding({ all: 10 })]}>
        <Image systemName="pawprint.fill" color={bannerAccent} />
        <Text modifiers={[font({ weight: 'bold', size: 14 }), foregroundStyle(bannerText), padding({ leading: 5 })]}>
          {props.dogName}
        </Text>
        <Text modifiers={[font({ weight: 'bold', size: 14 }), foregroundStyle(bannerAccent), padding({ leading: 8 })]}>
          {props.km}km
        </Text>
        <Text modifiers={[font({ size: 11 }), foregroundStyle(bannerDim), padding({ leading: 6 })]}>
          {props.elapsed}
        </Text>
      </HStack>
    ),

    // ---------- 다이내믹 아일랜드: 컴팩트 ----------
    compactLeading: <Image systemName="pawprint.fill" color={CORAL} />,
    compactTrailing: (
      <Text modifiers={[font({ weight: 'bold', size: 14 }), foregroundStyle(CORAL)]}>
        {props.km}km
      </Text>
    ),

    // ---------- 최소 (다른 액티비티와 공존 시) ----------
    minimal: <Image systemName="pawprint.fill" color={CORAL} />,

    // ---------- 확장 ----------
    expandedLeading: (
      <VStack modifiers={[padding({ all: 10 })]}>
        <Image systemName="pawprint.fill" color={CORAL} />
        <Text modifiers={[font({ weight: 'bold', size: 12 }), foregroundStyle(CREAM), padding({ top: 3 })]}>
          {props.dogName}
        </Text>
      </VStack>
    ),
    expandedTrailing: (
      <VStack modifiers={[padding({ all: 10 })]}>
        <Text modifiers={[font({ weight: 'bold', size: 24 }), foregroundStyle(CORAL)]}>
          {props.km}
        </Text>
        <Text modifiers={[font({ size: 11 }), foregroundStyle(DIM)]}>
          / {props.targetKm}km
        </Text>
      </VStack>
    ),
    expandedBottom: (
      <HStack modifiers={[padding({ all: 10 })]}>
        <Text modifiers={[font({ size: 13 }), foregroundStyle(CORAL)]}>
          {props.pace}/km
        </Text>
        {paceState !== '' ? <Text modifiers={paceMods}>{paceLabel}</Text> : null}
        <Text modifiers={[font({ size: 13 }), foregroundStyle(CREAM), padding({ leading: 12 })]}>
          {props.elapsed}
        </Text>
        <Text modifiers={[font({ size: 13 }), foregroundStyle(DIM), padding({ leading: 12 })]}>
          {props.eventLine}
        </Text>
      </HStack>
    ),
  };
};

export default createLiveActivity('RunActivity', RunActivity);
