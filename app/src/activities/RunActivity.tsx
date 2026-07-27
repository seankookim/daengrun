import { HStack, Image, Text, VStack } from '@expo/ui/swift-ui';
import { font, foregroundStyle, padding } from '@expo/ui/swift-ui/modifiers';
import { createLiveActivity, type LiveActivityEnvironment } from 'expo-widgets';

// 러닝 라이브 액티비티 — 잠금화면 배너 + 다이내믹 아일랜드.
// 러너의 폰에서 러닝 중 항상 보이는 상태: 강아지·거리/목표·페이스·경과.
// 업데이트는 앱이 update()를 호출할 때 (포그라운드 러닝 기준 — 백그라운드 추적은 후속).

const VOLT = '#B9F23A';
const CORAL = '#FF6347';
const CREAM = '#F6F2E9';
const DIMTEXT = '#8fa093';

export type RunActivityProps = {
  dogName: string;
  km: string;        // '2.34' — 표시용 고정 포맷
  targetKm: string;  // '3'
  pace: string;      // "7'02\""
  elapsed: string;   // '23:41'
  eventLine: string; // '💩1 · 💧2' ('' 가능)
};

const RunActivity = (props: RunActivityProps, _env: LiveActivityEnvironment) => {
  'widget';

  return {
    // ---------- 잠금화면 배너 ----------
    banner: (
      <VStack modifiers={[padding({ all: 14 })]}>
        <HStack>
          <Image systemName="pawprint.fill" color={VOLT} />
          <Text modifiers={[font({ weight: 'bold', size: 15 }), foregroundStyle(CREAM), padding({ leading: 6 })]}>
            {props.dogName} 러닝 중
          </Text>
          <Text modifiers={[font({ size: 12 }), foregroundStyle(DIMTEXT), padding({ leading: 8 })]}>
            ⏱ {props.elapsed}
          </Text>
        </HStack>
        <HStack modifiers={[padding({ top: 8 })]}>
          <Text modifiers={[font({ weight: 'bold', size: 30 }), foregroundStyle(CORAL)]}>
            {props.km}
          </Text>
          <Text modifiers={[font({ size: 14 }), foregroundStyle(DIMTEXT), padding({ leading: 3 })]}>
            / {props.targetKm}km
          </Text>
          <Text modifiers={[font({ size: 13 }), foregroundStyle(VOLT), padding({ leading: 12 })]}>
            {props.pace}/km
          </Text>
        </HStack>
        <Text modifiers={[font({ size: 12 }), foregroundStyle(DIMTEXT), padding({ top: 5 })]}>
          {props.eventLine !== '' ? props.eventLine : '댕런 · 반려견 피트니스'}
        </Text>
      </VStack>
    ),

    // ---------- 다이내믹 아일랜드: 컴팩트 ----------
    compactLeading: <Image systemName="pawprint.fill" color={VOLT} />,
    compactTrailing: (
      <Text modifiers={[font({ weight: 'bold', size: 14 }), foregroundStyle(CORAL)]}>
        {props.km}km
      </Text>
    ),

    // ---------- 최소 (다른 액티비티와 공존 시) ----------
    minimal: <Image systemName="pawprint.fill" color={VOLT} />,

    // ---------- 확장 ----------
    expandedLeading: (
      <VStack modifiers={[padding({ all: 10 })]}>
        <Image systemName="pawprint.fill" color={VOLT} />
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
        <Text modifiers={[font({ size: 11 }), foregroundStyle(DIMTEXT)]}>
          / {props.targetKm}km
        </Text>
      </VStack>
    ),
    expandedBottom: (
      <HStack modifiers={[padding({ all: 10 })]}>
        <Text modifiers={[font({ size: 13 }), foregroundStyle(VOLT)]}>
          {props.pace}/km
        </Text>
        <Text modifiers={[font({ size: 13 }), foregroundStyle(CREAM), padding({ leading: 12 })]}>
          ⏱ {props.elapsed}
        </Text>
        <Text modifiers={[font({ size: 13 }), foregroundStyle(DIMTEXT), padding({ leading: 12 })]}>
          {props.eventLine}
        </Text>
      </HStack>
    ),
  };
};

export default createLiveActivity('RunActivity', RunActivity);
