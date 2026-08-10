import { HStack, Image, Text, VStack } from '@expo/ui/swift-ui';
import { background, font, foregroundStyle, padding } from '@expo/ui/swift-ui/modifiers';
import { createLiveActivity, type LiveActivityEnvironment } from 'expo-widgets';

// Owner-side Live Activity — the lock screen an owner watches while someone else runs their dog.
// Design: docs/labs/live-activity-lab.html, option ② 기록형 (ticket/bib motif, picked by Sean) —
// pill + '초코 · 민준 러너' meta, hero distance, spec footer. Four mandatory states from lab §C:
// pre (인계 완료 — never draws 0.00), running, stale (the number goes GREY and says how long —
// same 90s law as owner/live), done (final km, kept 8 min). Plus 'ended' for a run aborted into
// incident_review — a live-looking banner surviving an aborted run would be a lie.
//
// THE PLUMBING DIFFERENCE from RunActivity (the runner sibling): the owner's app is NOT running
// during the run, so after start this activity is updated by APNs pushes (0063 pipeline:
// runs.trace save → trigger → relay → `apns-push-type: liveactivity`). The pushed content-state is
// {name: 'OwnerRunActivity', props: '<json string of OwnerRunActivityProps>'} — every prop is a
// preformatted STRING because the widget cannot compute (no clocks, no math over raw values).
// While the owner's app is awake, owner/live.tsx also updates it locally from the same broadcast
// that draws the map (5s throttle, runner LA convention).

export type OwnerRunActivityProps = {
  phase: 'pre' | 'running' | 'stale' | 'done' | 'ended';
  dogName: string;
  runnerName: string; // display-ready, without the '러너' suffix
  km: string;         // '2.34' — '' when the number does not exist yet (no-0.00 law)
  targetKm: string;   // '3' — '' when unknown / not applicable (done)
  pace: string;       // "7'02\"" or ''
  elapsed: string;    // '23:41' or ''
  statusLine: string; // '방금 업데이트' · 'N분째 위치가 갱신되지 않았어요' · '사진 4장' · ''
};

const OwnerRunActivity = (props: OwnerRunActivityProps, env: LiveActivityEnvironment) => {
  'widget';

  // ⚠️ ALL constants live inside the function — the 'widget' function is stringified and executed
  // in the widget extension, where module-scope closures do not exist (CORAL ReferenceError,
  // 2026-07-23). Same law as RunActivity.tsx.
  const CORAL = '#FF5C3D';
  const CORAL_DEEP = '#E8552F';
  const CREAM = '#F8F6F0';
  const DIM = '#9A93B5';
  const SAGE = '#8FB573';
  const STALE_GREY = '#6b6478';   // lab: pill.stale
  const STALE_NUM = '#8b8496';    // the number "dies grey" — stated as a color, not an opacity trick
  const STALE_TEXT = '#FF8F76';   // lab: the 'N분째' line

  // The lock-screen banner background follows the system material (HIG) — ink adapts. The Dynamic
  // Island is always black — fixed light text there.
  const bannerText = env.colorScheme === 'dark' ? CREAM : '#1C1837';
  const bannerDim = env.colorScheme === 'dark' ? DIM : '#5B594A';

  const phase = props.phase;
  const hasNum = props.km !== '';
  const pillBg = phase === 'running' ? CORAL_DEEP : phase === 'done' ? SAGE : STALE_GREY;
  const pillInk = phase === 'done' ? '#14210f' : '#ffffff';
  const pillLabel =
    phase === 'pre' ? 'HANDOFF'
    : phase === 'running' ? 'RUNNING'
    : phase === 'stale' ? 'NO SIGNAL'
    : phase === 'done' ? 'DONE'
    : 'ENDED';
  const numColor = phase === 'done' ? SAGE : phase === 'stale' ? STALE_NUM : CORAL;
  const meta = props.dogName + ' · ' + props.runnerName + ' 러너';

  // Title/foot pair for the numberless states (pre / ended / running-before-first-fix).
  const noNumTitle =
    phase === 'pre' ? '인계가 확인됐어요'
    : phase === 'ended' ? '러닝이 종료됐어요'
    : phase === 'done' ? '러닝 완료'
    : '위치 수신 대기 중';
  const noNumFoot =
    phase === 'pre' ? '곧 러닝이 시작돼요'
    : phase === 'ended' ? '앱에서 자세히 확인하세요'
    : phase === 'done' ? '리포트 보기 ›'
    : '러너가 달리기 시작하면 거리가 표시돼요';

  // Footer under the number: left spec + right status. Precomputed strings — the widget draws,
  // it does not think.
  const numUnit = phase === 'done' ? 'km 완주' : '/ ' + props.targetKm + 'km';
  const footLeft =
    phase === 'running' ? (props.pace !== '' ? props.pace + ' · ' + props.elapsed : props.elapsed)
    : phase === 'done' ? (props.statusLine !== '' ? props.elapsed + ' · ' + props.statusLine : props.elapsed)
    : '';
  const footRight =
    phase === 'stale' ? props.statusLine
    : phase === 'done' ? '리포트 보기 ›'
    : props.statusLine;
  const footRightColor = phase === 'stale' ? STALE_TEXT : phase === 'done' ? bannerText : bannerDim;

  return {
    // ---------- lock-screen banner (also StandBy / watch smart stack on non-island devices) ----------
    banner: (
      <VStack modifiers={[padding({ all: 14 })]}>
        <HStack>
          <Text
            modifiers={[
              font({ weight: 'bold', size: 11 }),
              foregroundStyle(pillInk),
              padding({ horizontal: 7, vertical: 2 }),
              background(pillBg),
            ]}
          >
            {pillLabel}
          </Text>
          <Text modifiers={[font({ size: 12 }), foregroundStyle(bannerDim), padding({ leading: 8 })]}>
            {meta}
          </Text>
        </HStack>
        {hasNum ? (
          <VStack>
            <HStack modifiers={[padding({ top: 9 })]}>
              <Text modifiers={[font({ weight: 'bold', size: 38 }), foregroundStyle(numColor)]}>
                {props.km}
              </Text>
              <Text modifiers={[font({ size: 13 }), foregroundStyle(bannerDim), padding({ leading: 4 })]}>
                {numUnit}
              </Text>
            </HStack>
            <HStack modifiers={[padding({ top: 6 })]}>
              <Text modifiers={[font({ size: 12 }), foregroundStyle(bannerDim)]}>
                {footLeft}
              </Text>
              <Text
                modifiers={[font({ size: 12 }), foregroundStyle(footRightColor), padding({ leading: 10 })]}
              >
                {footRight}
              </Text>
            </HStack>
          </VStack>
        ) : (
          <VStack modifiers={[padding({ top: 9 })]}>
            <Text modifiers={[font({ weight: 'bold', size: 15 }), foregroundStyle(bannerText)]}>
              {noNumTitle}
            </Text>
            <Text modifiers={[font({ size: 12 }), foregroundStyle(bannerDim), padding({ top: 4 })]}>
              {noNumFoot}
            </Text>
          </VStack>
        )}
      </VStack>
    ),

    // ---------- watch smart stack · CarPlay (small banner) ----------
    bannerSmall: (
      <HStack modifiers={[padding({ all: 10 })]}>
        <Image systemName="pawprint.fill" color={phase === 'stale' ? STALE_GREY : CORAL} />
        <Text modifiers={[font({ weight: 'bold', size: 14 }), foregroundStyle(bannerText), padding({ leading: 5 })]}>
          {props.dogName}
        </Text>
        <Text modifiers={[font({ weight: 'bold', size: 14 }), foregroundStyle(numColor), padding({ leading: 8 })]}>
          {hasNum ? props.km + 'km' : noNumTitle}
        </Text>
      </HStack>
    ),

    // ---------- Dynamic Island: compact (lab §D) ----------
    compactLeading: <Image systemName="pawprint.fill" color={phase === 'stale' ? STALE_GREY : CORAL} />,
    compactTrailing: (
      <Text modifiers={[font({ weight: 'bold', size: 14 }), foregroundStyle(numColor)]}>
        {hasNum ? props.km + 'km' : props.dogName}
      </Text>
    ),

    // ---------- minimal (coexisting with another activity) ----------
    minimal: <Image systemName="pawprint.fill" color={phase === 'stale' ? STALE_GREY : CORAL} />,

    // ---------- expanded ----------
    expandedLeading: (
      <VStack modifiers={[padding({ all: 10 })]}>
        <Text modifiers={[font({ weight: 'bold', size: 13 }), foregroundStyle(CREAM)]}>
          {props.dogName}
        </Text>
        <Text modifiers={[font({ size: 11 }), foregroundStyle(DIM), padding({ top: 2 })]}>
          {props.runnerName + ' 러너'}
        </Text>
      </VStack>
    ),
    expandedTrailing: (
      <VStack modifiers={[padding({ all: 10 })]}>
        <Text modifiers={[font({ weight: 'bold', size: hasNum ? 26 : 13 }), foregroundStyle(hasNum ? numColor : CREAM)]}>
          {hasNum ? props.km : noNumTitle}
        </Text>
        <Text modifiers={[font({ size: 11 }), foregroundStyle(DIM)]}>
          {hasNum ? numUnit : ''}
        </Text>
      </VStack>
    ),
    expandedBottom: (
      <HStack modifiers={[padding({ all: 10 })]}>
        <Text modifiers={[font({ size: 13 }), foregroundStyle(phase === 'stale' ? STALE_TEXT : CREAM)]}>
          {phase === 'stale' ? props.statusLine
            : hasNum ? (props.pace !== '' ? props.pace + '/km' : footRight)
            : noNumFoot}
        </Text>
        <Text modifiers={[font({ size: 13 }), foregroundStyle(DIM), padding({ leading: 12 })]}>
          {phase === 'running' || phase === 'done' ? props.elapsed : ''}
        </Text>
      </HStack>
    ),
  };
};

export default createLiveActivity('OwnerRunActivity', OwnerRunActivity);
