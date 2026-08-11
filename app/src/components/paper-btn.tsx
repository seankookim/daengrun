// 액션 시스템의 물화 — F2.1 버튼 매트릭스 개정판.
//
// [Sean 2026-08-11] "검정 버튼이 싫다. 액션 버튼은 동기를 일으키고 행동을 시작시켜야 한다.
//   검정은 제일 지루하다. 버튼에 목적을 줘라. 앱에 검정 버튼과 텅 빈 흰 버튼이 너무 많다."
//
// 잉크 프라이머리 은퇴. §5의 코랄 법을 '면'으로 확장한 것 — 검정은 누구 차례인지 말하지 않았다.
// paper.action은 **신규 색이 아니라 이미 있던 #C6472C(MONEY_DEEP/GO_SKIN.deep/CORAL_INK)의 승격**이다.
// 첫 안의 #C7401F는 그것과 분리도 1.04로 눈에 구분되지 않는 중복 헥스였다 (디자인 보이스 교정).
// 실측 흰 라벨 4.84:1 — 전 크기 AA 통과.
//
// '텅 빈 흰 버튼' 문제는 secondary가 해결한다: paper.wash 면을 깔아 보조 버튼도
// **액션 가족의 일원**으로 읽히게 한다. 진짜 저관여 동작만 quiet(중립)로 남는다.
//
// [중요] 잉크는 사라지지 않는다 — **상태**로 남는다: 선택 칩·완료 스텝·라이브 필·다크 아티팩트.
// 감사 결과 잉크 fill 51곳 중 약 30곳이 버튼이 아니었다. 그것들을 코랄로 칠하면
// '선택됨'이 '누르세요'로 둔갑한다. 이 컴포넌트는 **누르면 커밋되는 것**만 칠한다.
//
// 법: 상태는 명시 fill로만 (불투명도 트릭 금지) · busy = 라벨 스왑 · 샤프 코너 ·
//     화면당 primary 1개는 호출자가 지킨다.
import { Pressable, Text, View, ViewStyle } from 'react-native';
import { BrandMark } from './brandmark';
import { haptic } from '../lib/haptics';
import { paper } from '../theme';

type Variant = 'primary' | 'climax' | 'secondary' | 'quiet' | 'destructive';

export function PaperBtn({
  label, busyLabel, onPress, variant = 'primary', disabled = false, busy = false, style, mark = false,
}: {
  label: string;
  busyLabel?: string;       // busy 시 스왑될 라벨 (기본: '처리 중...')
  onPress: () => void;
  variant?: Variant;
  disabled?: boolean;
  busy?: boolean;
  style?: ViewStyle;
  /** climax 전용 — 라벨 앞에 브랜드 마크. 앱의 정점 순간에만 (§7b Peak-End). */
  mark?: boolean;
}) {
  const blocked = disabled || busy;
  const filled = variant === 'primary' || variant === 'climax';
  const climax = variant === 'climax';

  const fillFor = (pressed: boolean) => {
    if (disabled) return paper.disabledFill;
    if (filled) return pressed && !busy ? paper.actionPressed : paper.action;
    if (variant === 'secondary') return pressed && !blocked ? '#FBE7E1' : paper.wash;
    if (variant === 'destructive') return pressed && !blocked ? paper.criticalWash : paper.canvas;
    return pressed && !blocked ? paper.wash : paper.canvas; // quiet
  };
  const labelColor = disabled ? paper.faint
    : filled ? '#FFFFFF'
      : variant === 'destructive' ? paper.critical
        : variant === 'secondary' ? paper.actionInk
          : paper.text; // quiet

  return (
    <Pressable
      onPress={blocked ? undefined : onPress}
      // [§7c 멀티모달 하모니] 커밋 순간에 촉각 — 시각과 같은 프레임. 정점 버튼만 success,
      // 나머지는 light. 눌림 자체가 아니라 '커밋'에만 울린다 (과용하면 의미가 사라진다).
      // [§7c 교정] 햅틱은 **클라이맥스에만**. 모든 프라이머리가 진동하면 인계 봉인의 특별함이
      // 사라진다 — 정확히 이 계획이 지키려던 피크다.
      onPressIn={blocked || !climax ? undefined : () => haptic('success')}
      disabled={blocked}
      accessibilityRole="button"
      accessibilityLabel={busy ? (busyLabel ?? '처리 중...') : label}
      accessibilityState={{ disabled, busy }}
      style={({ pressed }) => [
        // [리뷰 수정] 호출자 style을 variant 앞으로 옮겼다. 뒤에 있을 때 caller가 backgroundColor를
        // 얹으면 pressed 스왑이 조용히 죽었다 (address-pin이 실제로 그랬다). 이제 레이아웃은
        // 호출자가, 색은 매트릭스가 가진다 — 매트릭스가 항상 이긴다.
        style,
        { alignItems: 'center', justifyContent: 'center', flexDirection: 'row', gap: 8,
          paddingVertical: climax ? 18 : 16, borderRadius: 0,
          // [§7c] press-down에 즉시 반응. 정점 버튼은 조금 더 깊게 눌린다.
          transform: [{ scale: pressed && !blocked ? (climax ? 0.955 : 0.96) : 1 }] },
        { backgroundColor: fillFor(pressed) },
        (variant === 'secondary') && { borderWidth: 1, borderColor: disabled ? paper.faint : paper.line },
        (variant === 'destructive') && { borderWidth: 1, borderColor: disabled ? paper.faint : paper.critical },
        (variant === 'quiet') && { borderWidth: 1, borderColor: '#EEEEEE' },
      ]}
    >
      {climax && mark && !busy && (
        <View style={{ opacity: disabled ? 0.5 : 1 }}><BrandMark height={18} tint="#FFFFFF" /></View>
      )}
      <Text style={{
        // primary 17/800 · climax 19/800 (정점은 조금 더 큰 목소리) · 나머지 16/800
        fontSize: climax ? 19 : variant === 'primary' ? 17 : 16,
        fontWeight: '800',
        color: labelColor,
      }}>
        {busy ? (busyLabel ?? '처리 중...') : label}
      </Text>
    </Pressable>
  );
}
