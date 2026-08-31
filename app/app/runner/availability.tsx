import { useCallback, useEffect, useState } from 'react';
import { Alert, Pressable, ScrollView, StyleSheet, Text, TextStyle, View } from 'react-native';
import { PaperBtn } from '../../src/components/paper-btn';
import { StatusBarCover } from '../../src/components/status-bar-cover';
import { Row } from '../../src/components/ui';
import { AvailRule, fetchMyAvailability, fetchMyBookingRules, RunnerBookingRules, saveMyAvailability, saveMyBookingRules } from '../../src/lib/api';
import { useNumFont } from '../../src/lib/fonts';
import { goBackOrHome } from '../../src/lib/nav';
import { layout, paper } from '../../src/theme';

// 가용시간 설정 — 실편집기. runner_availability_rules 실저장.
// 반영 지점: 러너 공개 프로필 슬롯 그리드 · 보호자 예약 슬롯 시트 · 서버 is_slot_available.
// v1: 요일당 1구간, 30분 단위. 다구간·예외일정·예약규칙은 v2.
//
// [paper repaint 2026-08-11] cream/forest/volt legacy scrapped → paper chrome.
// Behavior frozen: load/mutate/bump/applyToAll/save, 30-min clamps, dirty gate, sticky
// save bar. §3b applied: day toggle = explicit ink/canvas chip (no tint pill), stepper
// values Oswald with lineHeight 25 (BUG A), save = PaperBtn (busy label swap, no opacity).
//
// [journey v4 · R8 2026-08-19] Two things left, no behaviour moved:
//  · 전체 적용 was a coral link on EVERY enabled row (seven corals competing with 저장하기).
//    It is now one ink line under the grid, sourced from Monday. `applyToAll` is called
//    unchanged — same one-day-to-the-enabled-days semantics.
//  · The '예약 규칙 (준비 중)' block is gone. Three rows of numbers no server ever returns
//    (2시간 전 / 4건 / 30분) read as settings the runner owns; the muted ink said "준비 중"
//    but the numbers still looked like state. A 준비 중 plate is not drawn (lab R8).

// 2026-08-24 enhancement wave (docs/labs/enh-runner-home-lab.html D①② · Sean: "For runner home I
// like all new updates you are showing me"). Two changes, zero behaviour moved:
//  · D① what these rules actually govern. 「설정한 시간에만 요청을 받아요」 is true of the owner's
//    SLOT PICKER and false of the open pool — 0056's marketplace_open_requests reads neither this
//    table nor `online` (its predicates are status='matching' · runner_id is null ·
//    club_session_id is null · is_active_runner()). A runner who sets 주 2일 and then keeps getting
//    open requests currently has no way to reconcile the screen with reality, and the wrong
//    inference (「설정이 안 먹네」) is the one that makes them stop maintaining it.
//    ⚠ This does NOT unify the three predicates (DESIGN.md §9, DO-NOT-REFACTOR) — it publishes
//    their jurisdiction. This table feeds exactly one of them (0003 is_slot_available §1, weekly
//    rule containment) plus the runner's public profile grid; 0015 available_runners and
//    0054 runners_available_for never read it (they read `online` + live bookings, which is why
//    that sentence lives on the home toggle instead — one fact, one home).
//  · D② the save bar says what it will overwrite. saveMyAvailability is delete-all-then-insert:
//    one 저장하기 replaces the runner's entire week. The screen already refuses to mount the bar
//    from an unseeded grid; what it never did was say what the write contains.
//  NOT built (lab D③ 예약 규칙 — 하루 최대 러닝 / 러닝 사이 휴식): both numbers are really enforced
//  (is_slot_available §5 and §3, defaults coalesce(…,4)/coalesce(…,30)) and the row exists with
//  self-all RLS, but the client has NO read/write pair over runner_booking_rules — api.ts only
//  ever inserts the row at apply time (api.ts:784). Drawing steppers seeded from the hardcoded
//  defaults would print a default as if it were a saved value, which is the exact failure R8
//  deleted the old 준비 중 plate for. It needs the api.ts pair first.

const DAY_ORDER = [1, 2, 3, 4, 5, 6, 0]; // 월…일
const SRC_WD = DAY_ORDER[0];             // 전체 적용의 소스 = 월요일 (그리드 첫 줄)
const DAY_NAME = '일월화수목금토';

interface DayState { enabled: boolean; startMin: number; endMin: number }
const DEFAULT_DAY: DayState = { enabled: false, startMin: 360, endMin: 1320 };

const fmtMin = (m: number) => `${String(Math.floor(m / 60)).padStart(2, '0')}:${String(m % 60).padStart(2, '0')}`;

export default function Availability() {
  const nf = useNumFont(); // Oswald — stepper time values
  const [days, setDays] = useState<DayState[]>(Array.from({ length: 7 }, () => ({ ...DEFAULT_DAY })));
  const [loaded, setLoaded] = useState(false);
  const [loadErr, setLoadErr] = useState(false);
  const [saving, setSaving] = useState(false);
  const [dirty, setDirty] = useState(false);
  // [D② 2026-08-24] 마지막으로 **성공한 로드**의 스냅샷. 저장 바의 diff는 오직 이것과 비교한다 —
  // 기본값과 비교하면 서버에 없던 변경을 지어내게 되고, 실패한 로드에서는 스냅샷 자체가 없다
  // (그때는 저장 바가 아예 마운트되지 않는다 — 아래 loaded 게이트).
  const [base, setBase] = useState<DayState[] | null>(null);

  // [honesty P1 2026-08-11] A failed load used to setLoaded(true) and render the
  // default all-쉬는날 grid as if it were the runner's saved rules — one 저장하기
  // tap then overwrote the real server rules with an empty set. Failure now
  // renders as failure, and the save bar only mounts after a real load succeeded.
  const load = useCallback(() => {
    setLoadErr(false);
    fetchMyAvailability()
      .then((rules) => {
        const next = Array.from({ length: 7 }, () => ({ ...DEFAULT_DAY }));
        rules.forEach((r) => { next[r.weekday] = { enabled: true, startMin: r.startMin, endMin: r.endMin }; });
        setDays(next);
        setBase(next.map((d) => ({ ...d }))); // [D②] diff의 기준선 — days와 객체를 공유하지 않는다
        setLoaded(true);
      })
      .catch((e) => { console.warn('[avail] load:', e?.message ?? e); setLoadErr(true); });
  }, []);
  useEffect(() => { load(); }, [load]);

  const mutate = (wd: number, patch: Partial<DayState>) => {
    setDays((ds) => ds.map((d, i) => (i === wd ? { ...d, ...patch } : d)));
    setDirty(true);
  };

  const bump = (wd: number, field: 'startMin' | 'endMin', delta: number) => {
    const d = days[wd];
    if (field === 'startMin') {
      mutate(wd, { startMin: Math.min(Math.max(d.startMin + delta, 300), d.endMin - 60) });
    } else {
      mutate(wd, { endMin: Math.min(Math.max(d.endMin + delta, d.startMin + 60), 1440) });
    }
  };

  // [honesty 2026-08-19 · runner review P2] 이 함수는 **켜져 있는 다른 요일**에만 값을 복사한다
  // (요일을 켜지도, 끄지도 않는다). 바꿀 대상이 없으면 화면에서는 아무것도 움직이지 않는데도
  // setDirty(true)가 저장 바를 '저장됨 ✓'(비활성)에서 '저장하기'로 뒤집어, 러너에게 있지도 않은
  // 미저장 변경을 알리고 아무것도 바꾸지 않는 왕복을 팔았다. 실제 변화가 있을 때만 dirty다.
  const applyToAll = (srcWd: number) => {
    const src = days[srcWd];
    const changes = days.some((d, i) => i !== srcWd && d.enabled && (d.startMin !== src.startMin || d.endMin !== src.endMin));
    if (!changes) return;
    setDays((ds) => ds.map((d) => (d.enabled ? { ...d, startMin: src.startMin, endMin: src.endMin } : d)));
    setDirty(true);
  };

  const save = async () => {
    if (!loaded) return; // hard guard — never write from a grid the server didn't seed
    setSaving(true);
    // [D②] 이 저장이 서버에 쓴 바로 그 상태가 다음 diff의 기준선이 된다. 갱신하지 않으면 두 번째
    // 편집이 **이미 저장된 변경까지** 다시 열거한다 (저장 전 로드와 비교하게 되므로).
    const written = days.map((d) => ({ ...d }));
    try {
      const rules: AvailRule[] = days
        .map((d, wd) => ({ weekday: wd, startMin: d.startMin, endMin: d.endMin, enabled: d.enabled }))
        .filter((d) => d.enabled)
        .map(({ weekday, startMin, endMin }) => ({ weekday, startMin, endMin }));
      await saveMyAvailability(rules);
      setBase(written);
      setDirty(false);
      Alert.alert('저장 완료', '보호자 예약 화면과 내 공개 프로필에 바로 반영됐어요');
    } catch (e) {
      Alert.alert('저장 실패', (e as Error).message);
    } finally {
      setSaving(false);
    }
  };

  const activeCount = days.filter((d) => d.enabled).length;

  // ═══ [U5 · 예약 규칙 2026-08-31] 가용시간과 독립인 자기 상태 — 그리드의 D② 저장 모델(전체
  // 교체·스티키 바)과 절대 섞지 않는다: 이 두 숫자는 UPDATE 두 칸이고, 실패·더티·저장이 전부
  // 따로 논다. 서버가 읽는 두 칸만 편집한다(api.ts 주석 참조). ═══
  const [rules, setRules] = useState<RunnerBookingRules | null>(null);
  const [rulesBase, setRulesBase] = useState<RunnerBookingRules | null>(null);
  const [rulesState, setRulesState] = useState<'loading' | 'ready' | 'absent' | 'error'>('loading');
  const [rulesSaving, setRulesSaving] = useState(false);
  const loadRules = useCallback(() => {
    setRulesState('loading');
    fetchMyBookingRules()
      .then((r) => {
        if (r == null) { setRulesState('absent'); return; }
        setRules(r);
        setRulesBase({ ...r });
        setRulesState('ready');
      })
      .catch((e) => { console.warn('[rules] load:', e?.message ?? e); setRulesState('error'); });
  }, []);
  useEffect(() => { loadRules(); }, [loadRules]);
  const rulesDirty = rules != null && rulesBase != null
    && (rules.restAfterMin !== rulesBase.restAfterMin || rules.maxSessionsPerDay !== rulesBase.maxSessionsPerDay);
  // 클램프 — 서버엔 CHECK가 없다(0001:108-114는 default뿐): 자기 슬롯 계산에만 먹는 값이라
  // 타인을 겨냥하진 못하지만, 0분 미만·비상식 상한은 클라가 막는다. 휴식 0..120 · 상한 1..8.
  const bumpRest = (delta: number) => setRules((r) => (r ? { ...r, restAfterMin: Math.min(Math.max(r.restAfterMin + delta, 0), 120) } : r));
  const bumpMax = (delta: number) => setRules((r) => (r ? { ...r, maxSessionsPerDay: Math.min(Math.max(r.maxSessionsPerDay + delta, 1), 8) } : r));
  const saveRules = async () => {
    if (!rules || !rulesDirty) return;
    setRulesSaving(true);
    const written = { ...rules };
    try {
      await saveMyBookingRules(written);
      setRulesBase(written);
    } catch (e) {
      Alert.alert('규칙 저장 실패', (e as Error).message);
    } finally {
      setRulesSaving(false);
    }
  };

  // [D② 2026-08-24] 저장이 무엇을 덮어쓰는지. saveMyAvailability는 delete-all-then-insert이므로
  // 저장하기 한 번이 러너의 **주 전체**를 교체한다. 이 절들은 전부 마지막 성공 로드(base)와 현재
  // 그리드의 비교이고, 기본값에서 파생된 문장은 하나도 없다.
  // 가장 파괴적인 저장 — 모든 요일 해제 — 은 침묵하지 않고 자기 결과를 말한다: 0003
  // is_slot_available §1이 해당 요일의 규칙 행을 찾지 못하면 그 슬롯은 무조건 false다.
  const diffClauses = ((): string[] => {
    if (!base) return [];
    const changedDays = DAY_ORDER.filter((wd) => base[wd].enabled !== days[wd].enabled
      || (base[wd].enabled && days[wd].enabled
        && (base[wd].startMin !== days[wd].startMin || base[wd].endMin !== days[wd].endMin)));
    if (changedDays.length === 0) return [];
    if (activeCount === 0 && base.some((d) => d.enabled)) {
      return ['모든 요일 해제 · 보호자 예약 화면에서 내 슬롯이 사라져요'];
    }
    return changedDays.map((wd) => {
      const a = base[wd];
      const b = days[wd];
      const nm = DAY_NAME[wd];
      if (!a.enabled) return `${nm} 추가`;
      if (!b.enabled) return `${nm} 해제`;
      if (a.endMin === b.endMin) return `${nm} ${fmtMin(a.startMin)} → ${fmtMin(b.startMin)}`;
      if (a.startMin === b.startMin) return `${nm} ${fmtMin(a.endMin)} → ${fmtMin(b.endMin)}`;
      return `${nm} ${fmtMin(a.startMin)}–${fmtMin(a.endMin)} → ${fmtMin(b.startMin)}–${fmtMin(b.endMin)}`;
    });
  })();
  // 세 절까지만 인쇄하고 나머지는 세어서 말한다 — 저장 바에서 네 줄로 자라면 버튼을 밀어낸다.
  const diffShown = diffClauses.slice(0, 3).join(' · ');
  const diffMore = diffClauses.length > 3 ? ` 외 ${diffClauses.length - 3}개` : '';

  return (
    <View style={{ flex: 1, backgroundColor: paper.canvas }}>
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingHorizontal: layout.gutter, paddingTop: 56, paddingBottom: 120 }}>
        <Row style={{ justifyContent: 'space-between', marginBottom: 4 }}>
          <Pressable onPress={goBackOrHome} style={s.backBtn} accessibilityRole="button" accessibilityLabel="뒤로">
            <Text style={{ fontSize: 20.5, color: paper.ink }}>‹</Text>
          </Pressable>
          <Text style={{ fontSize: 22, fontWeight: '900', color: paper.ink }}>가용시간 설정</Text>
          <View style={{ width: 40 }} />
        </Row>
        {/* [honesty 2026-08-19 · runner review P2] '주 N일 러닝'은 로드가 **성공한** 뒤에만.
            days의 시드는 전부 쉬는 날이라, 로딩 중과 실패 후에 '주 0일 러닝'이 찍혔다 — 서버에
            무엇이 저장돼 있는지 아직 모르는 화면이 0일이라고 단언하던 자리다. loaded는 성공한
            로드에서만 true가 된다(실패는 loadErr만 세운다). */}
        {/* [D①] 종전 문장은 「설정한 시간에만 요청을 받아요」였다 — 보호자 슬롯 시트에는 참이고
            오픈 풀에는 거짓이다. 이 줄은 이 표가 실제로 정하는 것만 말한다. */}
        <Text style={{ fontSize: 15, lineHeight: 19, color: paper.dim, textAlign: 'center', marginBottom: 14 }}>
          보호자가 예약할 수 있는 시간이에요{loaded ? ` · 주 ${activeCount}일` : ''}
        </Text>

        {/* [D①] 관할 세 줄. 데이터가 아니라 **이 표의 관할 범위**라 로드 상태와 무관하게 그린다
            (러너의 값을 주장하지 않는다). 지명(0054)은 여기 없다 — 그것은 online과 확정 예약을
            읽으므로 홈 토글의 문장이 진다. 한 사실은 한 집에서만 말한다. */}
        <View style={s.juris}>
          <Row style={s.jurisRow}>
            <Text style={s.jurisLbl}>보호자 예약 화면의 내 슬롯</Text>
            <Text style={s.jurisOwn}>이 설정이 정해요</Text>
          </Row>
          <Row style={[s.jurisRow, s.jurisDiv]}>
            <Text style={s.jurisLbl}>내 공개 프로필 시간표</Text>
            <Text style={s.jurisOwn}>이 설정이 정해요</Text>
          </Row>
          <Row style={[s.jurisRow, s.jurisDiv]}>
            <Text style={s.jurisLbl}>열린 요청(오픈 풀)</Text>
            <Text style={s.jurisState}>시간과 무관하게 도착해요</Text>
          </Row>
        </View>

        {!loaded && !loadErr && (
          <View style={s.card}><Text style={{ fontSize: 15, color: paper.dim, textAlign: 'center', paddingVertical: 10 }}>불러오는 중...</Text></View>
        )}

        {/* loud-fail strip — criticalWash bg + critical ink (never shares paper.line) + retry */}
        {!loaded && loadErr && (
          <View style={s.failStrip}>
            <Text style={{ fontSize: 15, fontWeight: '700', color: paper.critical }}>저장된 가용시간을 불러오지 못했어요</Text>
            <Text style={{ fontSize: 15, lineHeight: 19, color: paper.critical, marginTop: 3 }}>
              불러오기 전에는 편집과 저장을 열지 않아요 — 기존 설정을 지우지 않기 위해서예요
            </Text>
            <Pressable onPress={load} style={s.retryBtn} accessibilityRole="button">
              <Text style={{ fontSize: 16, fontWeight: '800', color: paper.critical, textDecorationLine: 'underline' }}>다시 시도</Text>
            </Pressable>
          </View>
        )}

        {loaded && (
          <View style={s.card}>
            {DAY_ORDER.map((wd, i) => {
              const d = days[wd];
              return (
                <View key={wd}>
                  {i > 0 && <View style={s.div} />}
                  <View style={{ paddingVertical: 11 }}>
                    {/* 전체 적용 링크가 이 줄의 오른쪽에서 내려가면서 space-between 래퍼도 함께
                        은퇴했다 — 자식 하나짜리 정렬 컨테이너는 남겨두면 다음 사람을 속인다 */}
                    <Row style={{ gap: 10 }}>
                      <Text style={{ width: 24, fontSize: 17, fontWeight: '900', color: d.enabled ? paper.ink : '#BBBBBB' }}>
                        {DAY_NAME[wd]}
                      </Text>
                      {/* day toggle — explicit state colors (§3b, no tint-pill legacy):
                          on = ink fill + white label · off = canvas + neutral border + dim */}
                      <Pressable
                        onPress={() => mutate(wd, { enabled: !d.enabled })}
                        style={({ pressed }) => [s.toggleChip, d.enabled ? s.toggleChipOn : s.toggleChipOff, pressed && { transform: [{ scale: 0.96 }] }]}
                        accessibilityRole="switch"
                        accessibilityState={{ checked: d.enabled }}
                      >
                        <Text style={{ fontSize: 15, fontWeight: '800', color: d.enabled ? '#FFFFFF' : paper.dim }}>
                          {d.enabled ? '가능' : '쉬는 날'}
                        </Text>
                      </Pressable>
                    </Row>
                    {d.enabled && (
                      <Row style={{ gap: 8, marginTop: 10, justifyContent: 'center' }}>
                        <Stepper value={fmtMin(d.startMin)} nf={nf} onMinus={() => bump(wd, 'startMin', -30)} onPlus={() => bump(wd, 'startMin', 30)} />
                        <Text style={{ fontSize: 16, color: paper.dim, alignSelf: 'center' }}>—</Text>
                        <Stepper value={fmtMin(d.endMin)} nf={nf} onMinus={() => bump(wd, 'endMin', -30)} onPlus={() => bump(wd, 'endMin', 30)} />
                      </Row>
                    )}
                  </View>
                </View>
              );
            })}
          </View>
        )}

        {/* 전체 적용 — 그리드 아래 잉크 한 줄. 캡션이 소스 요일의 **실제 시간**을 말하므로 이 문은
            자기가 무엇을 할지 미리 보여준다. 월요일이 쉬는 날이면 문을 그리지 않는다: 화면 어디에도
            보이지 않는 시간을 나머지 요일에 퍼뜨리는 버튼이 되기 때문이다 (죽은 버튼 금지법의 이웃 —
            누르면 무언가는 일어나지만 러너가 보지 못한 값이 움직인다). 대신 켜는 방법을 말한다. */}
        {/* [honesty 2026-08-19 · runner review P2] 켜진 요일이 하나뿐이면 '나머지 가능한 요일'이
            존재하지 않는다 — 캡션은 없는 요일들을 가리키고, 문은 0개 요일에 값을 복사한 뒤
            (applyToAll의 no-op 가드 이전에는) 저장 바만 흔들었다. 켜진 요일이 둘 이상일 때만
            이 블록 전체가 존재한다: 월요일이 꺼진 안내 문장도 마찬가지로 그때만 의미가 있다. */}
        {loaded && activeCount > 1 && (days[SRC_WD].enabled ? (
          <Row style={s.applyRow}>
            <Text style={s.applyCaption} numberOfLines={2}>
              월요일 {fmtMin(days[SRC_WD].startMin)}–{fmtMin(days[SRC_WD].endMin)}을 나머지 가능한 요일에
            </Text>
            <Pressable
              onPress={() => applyToAll(SRC_WD)}
              hitSlop={8}
              style={s.applyBtn}
              accessibilityRole="button"
              accessibilityLabel="월요일 시간을 나머지 가능한 요일에 전체 적용"
            >
              <Text style={s.applyLink}>전체 적용 ›</Text>
            </Pressable>
          </Row>
        ) : (
          <Text style={s.applyOff}>월요일을 ‘가능’으로 켜면 그 시간을 나머지 요일에 한 번에 적용할 수 있어요</Text>
        ))}

        <Text style={{ fontSize: 15, color: paper.dim, textAlign: 'center', marginTop: 14, lineHeight: 19 }}>
          30분 단위 · 요일당 1구간 (다구간·휴가 등 예외 일정은 준비 중){'\n'}
          변경 사항은 내 공개 프로필과 보호자 예약 화면에 즉시 반영돼요
        </Text>

        {/* ═══ [U5 · 예약 규칙] 서버는 이 두 숫자를 줄곧 집행해 왔다(is_slot_available, 0003) —
            러너가 보고 바꿀 표면이 없었을 뿐이다. 자기 저장 버튼(세컨더리)을 갖는다: 스티키
            바의 프라이머리는 가용시간의 것이고, 화면당 프라이머리는 하나다(강조 예산). ═══ */}
        <View style={s.rulesHead}>
          <Text style={{ fontSize: 20, fontWeight: '800', color: paper.ink }}>예약 규칙</Text>
        </View>
        {rulesState === 'loading' && (
          <View style={s.card}><Text style={{ fontSize: 15, color: paper.dim, textAlign: 'center', paddingVertical: 10 }}>불러오는 중...</Text></View>
        )}
        {rulesState === 'error' && (
          <View style={s.failStrip}>
            <Text style={{ fontSize: 15, fontWeight: '700', color: paper.critical }}>저장된 예약 규칙을 불러오지 못했어요</Text>
            <Pressable onPress={loadRules} style={s.retryBtn} accessibilityRole="button">
              <Text style={{ fontSize: 16, fontWeight: '800', color: paper.critical, textDecorationLine: 'underline' }}>다시 시도</Text>
            </Pressable>
          </View>
        )}
        {rulesState === 'absent' && (
          /* 행은 러너 등록이 만든다 — 없다는 건 등록 전이거나 데이터 문제. 기본값을 지어내
             그리지 않고 부재를 부재로 말한다. */
          <View style={s.card}>
            <Text style={{ fontSize: 15, lineHeight: 19, color: paper.text, textAlign: 'center', paddingVertical: 10 }}>
              예약 규칙이 아직 만들어지지 않았어요 — 러너 등록을 마치면 생겨요
            </Text>
          </View>
        )}
        {rulesState === 'ready' && rules && (
          <View style={s.card}>
            <View style={{ paddingVertical: 11 }}>
              <Row style={{ justifyContent: 'space-between', alignItems: 'center' }}>
                <View style={{ flex: 1, paddingRight: 10 }}>
                  <Text style={{ fontSize: 16, fontWeight: '800', color: paper.ink }}>러닝 사이 휴식</Text>
                  <Text style={{ fontSize: 15, lineHeight: 19, color: paper.dim, marginTop: 2 }}>
                    확정 예약 앞뒤로 이 시간만큼 새 예약을 막아요
                  </Text>
                </View>
                <Stepper value={`${rules.restAfterMin}분`} nf={nf}
                  onMinus={() => bumpRest(-10)} onPlus={() => bumpRest(10)}
                  a11yMinus="휴식 10분 빼기" a11yPlus="휴식 10분 더하기" />
              </Row>
            </View>
            <View style={s.div} />
            <View style={{ paddingVertical: 11 }}>
              <Row style={{ justifyContent: 'space-between', alignItems: 'center' }}>
                <View style={{ flex: 1, paddingRight: 10 }}>
                  <Text style={{ fontSize: 16, fontWeight: '800', color: paper.ink }}>하루 최대 세션</Text>
                  <Text style={{ fontSize: 15, lineHeight: 19, color: paper.dim, marginTop: 2 }}>
                    이 횟수를 채우면 그날은 더 받지 않아요
                  </Text>
                </View>
                <Stepper value={`${rules.maxSessionsPerDay}회`} nf={nf}
                  onMinus={() => bumpMax(-1)} onPlus={() => bumpMax(1)}
                  a11yMinus="하루 최대 1회 빼기" a11yPlus="하루 최대 1회 더하기" />
              </Row>
            </View>
            {rulesDirty && (
              <Pressable
                onPress={saveRules}
                disabled={rulesSaving}
                style={({ pressed }) => [s.rulesSaveBtn, pressed && { backgroundColor: paper.wash }]}
                accessibilityRole="button"
              >
                <Text style={{ fontSize: 16, fontWeight: '800', color: paper.ink, textAlign: 'center' }}>
                  {rulesSaving ? '저장 중...' : `규칙 저장 — 휴식 ${rules.restAfterMin}분 · 하루 ${rules.maxSessionsPerDay}회`}
                </Text>
              </Pressable>
            )}
          </View>
        )}
      </ScrollView>
      {/* 시스템 바 스트립 — 요일 그리드가 시계 뒤로 지나가던 것 */}
      <StatusBarCover />

      {/* sticky save — PaperBtn matrix: busy = label swap, saved = explicit disabledFill.
          Mounts ONLY after a real load: saving an unseeded grid would wipe server rules. */}
      {loaded && (
        <View style={s.saveBar}>
          {/* [D②] 저장 전 한 줄. 바뀐 게 없으면(그리고 저장됨 ✓ 상태면) 그리지 않는다 — 30분
              클램프에 걸려 값이 제자리인 조작도 dirty를 세우므로, 절이 0개인 dirty가 실제로 있다.
              그때 「바뀌는 것 · 」만 남기면 없는 변경을 있다고 말하는 셈이다. */}
          {dirty && diffClauses.length > 0 && (
            <Text style={s.diff} numberOfLines={2}>
              <Text style={s.diffK}>바뀌는 것 · </Text>
              <Text style={s.diffV}>{diffShown}{diffMore}</Text>
            </Text>
          )}
          <PaperBtn
            label={dirty ? '저장하기' : '저장됨 ✓'}
            busyLabel="저장 중..."
            busy={saving}
            disabled={!dirty}
            onPress={save}
          />
        </View>
      )}
    </View>
  );
}

function Stepper({ value, nf, onMinus, onPlus, a11yMinus = '30분 빼기', a11yPlus = '30분 더하기' }: {
  value: string; nf: TextStyle | null; onMinus: () => void; onPlus: () => void;
  /* [U5] 예약 규칙 스텝퍼가 재사용하면서 하드코드였던 접근성 라벨이 거짓말이 됐다 — 기본값은
     기존 호출부(시간 그리드) 그대로, 새 호출부만 자기 라벨을 넘긴다. */
  a11yMinus?: string; a11yPlus?: string;
}) {
  return (
    <Row style={s.stepper}>
      <Pressable onPress={onMinus} style={s.stepBtn} accessibilityRole="button" accessibilityLabel={a11yMinus}>
        <Text style={s.stepBtnText}>−</Text>
      </Pressable>
      <View style={{ paddingHorizontal: 12, justifyContent: 'center' }}>
        {/* Oswald time value — lineHeight 25 = 1.28× (BUG A) */}
        <Text style={[{ fontSize: 19.5, lineHeight: 25, fontWeight: '900', color: paper.ink, fontVariant: ['tabular-nums'] as const }, nf]}>{value}</Text>
      </View>
      <Pressable onPress={onPlus} style={s.stepBtn} accessibilityRole="button" accessibilityLabel={a11yPlus}>
        <Text style={s.stepBtnText}>＋</Text>
      </Pressable>
    </Row>
  );
}

const s = StyleSheet.create({
  // paper back button grammar — 40×40 square, canvas, 1px coral
  backBtn: {
    width: 40, height: 40, backgroundColor: paper.canvas, alignItems: 'center', justifyContent: 'center',
    borderWidth: 1, borderColor: paper.line,
  },
  card: { backgroundColor: paper.canvas, borderWidth: 1, borderColor: '#EEEEEE', paddingHorizontal: 14, paddingVertical: 6 },
  // loud-fail strip — community.tsx failStrip grammar (criticalWash + critical, retry ≥40pt)
  failStrip: { backgroundColor: paper.criticalWash, padding: 13 },
  // [액션 시스템 2026-08-11] 잉크 테두리 박스 은퇴. 이 버튼은 criticalWash 라우드-페일 스트립
  // 안에 있는데, 잉크 테두리가 크리티컬 잉크와 싸웠다. 실패 스트립은 박스 버튼이 필요 없다 —
  // runner/run.tsx failAction의 밑줄 텍스트 문법으로 통일 (박스 9개 삭제, 결정 1개).
  retryBtn: { alignSelf: 'flex-start', marginTop: 10, minHeight: 44, justifyContent: 'center' },
  div: { height: 1, backgroundColor: '#EEEEEE' },
  // [U5 · 예약 규칙] 섹션 머리 + 세컨더리 저장(캔버스 면 + 코랄 보더 — 버튼 매트릭스의 세컨더리;
  // 프라이머리는 스티키 바 하나뿐이다)
  rulesHead: { marginTop: 26, marginBottom: 8 },
  rulesSaveBtn: { marginTop: 6, marginBottom: 10, minHeight: 48, justifyContent: 'center', borderWidth: 1, borderColor: paper.line, backgroundColor: paper.canvas, paddingHorizontal: 14 },
  // [D①] 관할 표 — 값이 아니라 범위를 인쇄하는 표라 카드 문법을 그대로 쓰되 값 열이 없다.
  juris: { borderWidth: 1, borderColor: '#EEEEEE', paddingHorizontal: 13, marginBottom: 12 },
  jurisRow: { alignItems: 'center', gap: 10, minHeight: 48, paddingVertical: 11 },
  jurisLbl: { flex: 1, minWidth: 0, fontSize: 15, lineHeight: 19, color: paper.dim },
  jurisOwn: { flexShrink: 0, fontSize: 15, lineHeight: 19, fontWeight: '800', color: paper.ink },
  jurisState: { flexShrink: 0, fontSize: 15, lineHeight: 19, color: paper.dim },
  jurisDiv: { borderTopWidth: 1, borderTopColor: '#EEEEEE' },
  // [D②] 저장 바의 diff 줄 — 라벨은 딤, 절은 잉크 (무엇이 바뀌는지가 읽히는 쪽이어야 한다)
  diff: { marginBottom: 9 },
  diffK: { fontSize: 15, lineHeight: 19, color: paper.dim },
  diffV: { fontSize: 15, lineHeight: 19, fontWeight: '800', color: paper.ink },
  toggleChip: { paddingVertical: 8, paddingHorizontal: 15, borderRadius: 0 },
  toggleChipOn: { backgroundColor: paper.ink },
  toggleChipOff: { backgroundColor: paper.canvas, borderWidth: 1, borderColor: '#EEEEEE' },
  stepper: { gap: 0, backgroundColor: paper.canvas, borderWidth: 1, borderColor: '#EEEEEE' },
  stepBtn: { width: 46, height: 46, alignItems: 'center', justifyContent: 'center' },
  stepBtnText: { fontSize: 22, fontWeight: '800', color: paper.ink },
  // 전체 적용 한 줄 — 잉크 링크 (코랄은 이 화면에서 저장하기 하나). 문은 ≥44pt.
  applyRow: { justifyContent: 'space-between', gap: 12, marginTop: 10 },
  applyCaption: { flexShrink: 1, fontSize: 15, lineHeight: 19, color: paper.dim },
  applyBtn: { minHeight: 44, justifyContent: 'center' },
  applyLink: { fontSize: 15, lineHeight: 19, fontWeight: '800', color: paper.ink },
  applyOff: { fontSize: 15, lineHeight: 19, color: paper.dim, marginTop: 10 },
  saveBar: {
    position: 'absolute', left: 0, right: 0, bottom: 0, backgroundColor: paper.canvas,
    paddingHorizontal: layout.gutter, paddingTop: 10, paddingBottom: 30,
    borderTopWidth: 1, borderTopColor: paper.line,
  },
});
