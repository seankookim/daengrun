// 순백/코랄 버튼 매트릭스(F2.1)의 물화 — 웨이브 2 리뷰 M3로 신설.
// 법: 상태는 명시 fill로만 (불투명도 트릭 금지) · busy = 라벨 스왑, disabled로 칠하지 않는다 ·
// 샤프 코너 · 화면당 잉크-필 CTA 1개 법은 호출자가 지킨다.
import { Pressable, Text, ViewStyle } from 'react-native';
import { paper } from '../theme';

type Variant = 'primary' | 'secondary' | 'destructive';

export function PaperBtn({ label, busyLabel, onPress, variant = 'primary', disabled = false, busy = false, style }: {
  label: string;
  busyLabel?: string;       // busy 시 스왑될 라벨 (기본: '처리 중...')
  onPress: () => void;
  variant?: Variant;
  disabled?: boolean;
  busy?: boolean;
  style?: ViewStyle;
}) {
  const blocked = disabled || busy;
  return (
    <Pressable
      onPress={blocked ? undefined : onPress}
      disabled={blocked}
      accessibilityRole="button"
      accessibilityLabel={busy ? (busyLabel ?? '처리 중...') : label}
      accessibilityState={{ disabled, busy }}
      style={({ pressed }) => [
        { alignItems: 'center', justifyContent: 'center', paddingVertical: 16, borderRadius: 0 },
        variant === 'primary' && {
          backgroundColor: disabled ? paper.disabledFill : pressed && !busy ? paper.inkPressed : paper.ink,
        },
        variant === 'secondary' && {
          backgroundColor: pressed && !blocked ? paper.wash : paper.canvas,
          borderWidth: 1, borderColor: disabled ? paper.faint : paper.line,
        },
        variant === 'destructive' && {
          backgroundColor: pressed && !blocked ? paper.criticalWash : paper.canvas,
          borderWidth: 1, borderColor: disabled ? paper.faint : paper.critical,
        },
        style,
      ]}
    >
      <Text style={{
        fontSize: 15.5, fontWeight: '800',
        color: variant === 'primary'
          ? (disabled ? paper.faint : '#FFFFFF')
          : disabled ? paper.faint
            : variant === 'destructive' ? paper.critical : paper.ink,
      }}>
        {busy ? (busyLabel ?? '처리 중...') : label}
      </Text>
    </Pressable>
  );
}
