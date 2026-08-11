import { HStack, Image, Text, VStack } from '@expo/ui/swift-ui';
import { font, foregroundStyle, padding } from '@expo/ui/swift-ui/modifiers';
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
          <Text modifiers={[font({ weight: 'bold', size: 30 }), foregroundStyle(CORAL)]}>
            {props.km}
          </Text>
          <Text modifiers={[font({ size: 14 }), foregroundStyle(bannerDim), padding({ leading: 3 })]}>
            / {props.targetKm}km
          </Text>
          <Text modifiers={[font({ size: 13 }), foregroundStyle(bannerAccent), padding({ leading: 12 })]}>
            {props.pace}/km
          </Text>
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
        <Text modifiers={[font({ weight: 'bold', size: 14 }), foregroundStyle(CORAL), padding({ leading: 8 })]}>
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
