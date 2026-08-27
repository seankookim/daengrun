import { useEffect, useState } from 'react';
import { Pressable, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { PaperBtn } from '../../src/components/paper-btn';
import { Row } from '../../src/components/ui';
import { StatusBarCover } from '../../src/components/status-bar-cover';
import { fetchMyProfile, fetchMyRunnerBio, fetchMyRunnerStatus, MyProfile, setMyHandle, updateMyProfile, updateRunnerBio } from '../../src/lib/api';
import { goBackOrHome } from '../../src/lib/nav';
import { paper } from '../../src/theme';

// 프로필 편집 — 인스타의 편집 화면 모양 (Sean 2026-08-27, 스크린샷이 모델): 라벨 왼쪽 · 값 오른쪽,
// 헤어라인으로만 나뉜 평평한 행 목록. **아바타 행은 없다 — Sean의 명시 제외**
// (「without the avatar though」). 사진은 마이 화면에서 바꾸고, 이 화면은 그 문을 열지도 흉내내지도
// 않는다: 없는 문을 그리는 것과 있는 문을 숨기는 것 둘 다 정직하지 않아서, 한 줄로 어디 있는지만 말한다.
//
// ═══ 인스타의 행 중 이 제품에 컬럼이 있는 것과 없는 것 ═══
//   이름      → profiles.name      ✅ updateMyProfile
//   아이디    → profiles.handle    ✅ set_my_handle (0074) — 직접 UPDATE는 안 된다 (컬럼 화이트리스트 없음)
//   동네      → profiles.district  ✅ updateMyProfile  (인스타에는 없는, 이 제품에만 있는 행)
//   소개      → runners.bio        ✅ updateRunnerBio — **러너에게만 존재하는 컬럼**이라
//                                     러너가 아닌 계정에는 이 행을 그리지 않는다.
//   대명사    → 컬럼 없음          ✗ 안 그린다
//   링크      → 컬럼 없음          ✗ 안 그린다
// 없는 컬럼을 클라에서 지어내면 저장 버튼이 거짓말을 하게 된다 — 행을 아예 만들지 않는 쪽이 정직하다.
//
// 저장은 세 개의 서로 다른 쓰기다 (프로필 UPDATE · set_my_handle RPC · runners UPDATE). 하나가
// 실패하면 앞의 것은 이미 저장돼 있으므로, 실패 문장이 **어디까지 저장됐는지**까지 말한다.

type Step = 'profile' | 'handle' | 'bio';

const STEP_FAIL: Record<Step, string> = {
  profile: '이름·동네를 저장하지 못했어요',
  handle: '이름·동네는 저장됐지만 아이디를 바꾸지 못했어요',
  bio: '이름·동네·아이디는 저장됐지만 소개를 저장하지 못했어요',
};

export default function ProfileEdit() {
  // 'loading' / 'error' / 실데이터 — 세 상태를 서로 다르게 그린다 (로딩은 빈 값이 아니다)
  const [loaded, setLoaded] = useState<MyProfile | null>(null);
  const [loadErr, setLoadErr] = useState(false);
  // 러너 여부는 **서버 진실**로 가른다 (session.role은 로컬 모드 상태일 뿐이다).
  // tier === null = runners 행 없음. 'error'면 소개 행을 안 그린다 — 못 읽은 것을 '비어 있음'으로
  // 그리면 러너의 기존 소개를 빈 칸으로 덮어쓸 수 있다.
  const [runner, setRunner] = useState<'loading' | 'yes' | 'no' | 'error'>('loading');

  const [name, setName] = useState('');
  const [handle, setHandle] = useState('');
  const [district, setDistrict] = useState('');
  const [bio, setBio] = useState('');

  // ⚠ 소개 읽기가 **끝났는지**를 따로 든다. 이게 없으면 폼이 먼저 뜨고 나중에 도착한 서버 소개가
  // 사용자가 그 사이 타이핑한 글자를 덮어쓴다 — 세 읽기가 서로 다른 속도로 오는 화면의 고전적인 사고다.
  const [bioReady, setBioReady] = useState(false);
  // 서버에서 읽어온 소개 원본. 저장은 **바뀐 경우에만** 소개를 쓴다.
  // ⚠ `fetchMyRunnerBio`는 실패해도 던지지 않는다 (error를 안 본다) — 못 읽었을 때도 null을 돌려주므로
  //    빈 칸으로 시작한다. 그 상태에서 무조건 쓰면 러너의 기존 소개가 ''로 덮인다. 「안 건드렸으면
  //    안 쓴다」는 그 경로를 **구조적으로** 막는다 (runner==='error' 가드는 우연히 같은 일을 할 뿐이다).
  const [loadedBio, setLoadedBio] = useState('');
  const [saving, setSaving] = useState(false);
  const [saveErr, setSaveErr] = useState<string | null>(null);

  // gen을 올리면 아래 이펙트가 다시 돈다 — 실패 스트립의 '다시 시도'가 쓰는 유일한 손잡이다.
  // (막다른 실패 화면은 이 앱에서 강제 종료 말고 나갈 길이 없다 — nav.ts의 같은 교훈.)
  const [gen, setGen] = useState(0);

  useEffect(() => {
    let alive = true;
    fetchMyProfile()
      .then((p) => {
        if (!alive) return;
        if (!p) { setLoadErr(true); return; } // 로그인 안 됨 — 빈 폼을 그리면 저장이 반드시 실패한다
        setLoadErr(false);
        setLoaded(p);
        setName(p.name ?? '');
        setHandle(p.handle ?? '');
        setDistrict(p.district ?? '');
      })
      .catch(() => { if (alive) setLoadErr(true); });
    fetchMyRunnerStatus()
      .then((r) => { if (alive) setRunner(r.tier ? 'yes' : 'no'); })
      .catch(() => { if (alive) setRunner('error'); });
    fetchMyRunnerBio()
      .then((b) => { if (!alive) return; setBio(b ?? ''); setLoadedBio(b ?? ''); setBioReady(true); })
      .catch(() => { if (alive) setBioReady(true); }); // 못 읽었으면 빈 칸으로 시작한다
    return () => { alive = false; };
  }, [gen]);

  // 세 읽기가 모두 끝나야 폼을 그린다. 하나라도 늦으면 늦게 온 값이 사용자의 타이핑을 덮거나
  // (소개), 있는 칸이 없는 것처럼 보인다 (소개 행 자체).
  const ready = !!loaded && runner !== 'loading' && bioReady;

  const save = async () => {
    const n = name.trim();
    if (!n) { setSaveErr('이름을 입력해주세요'); return; } // profiles.name은 NOT NULL이다
    setSaveErr(null);
    setSaving(true);
    let step: Step = 'profile';
    try {
      // district는 빈 문자열도 그대로 보낸다 — `|| undefined`로 접으면 지운 동네가 저장 후
      // 되살아난다 (편집기가 사용자가 한 일을 되돌리는 것은 거짓말의 한 종류다).
      await updateMyProfile({ name: n, district: district.trim() });
      step = 'handle';
      // 서버가 소문자로 정규화하므로 비교도 소문자로 한다. 안 바뀌었으면 안 부른다 —
      // 서버는 멱등이지만, 실패 메시지를 아이디 탓으로 돌리려면 호출이 아이디를 바꿀 때만 일어나야 한다.
      const h = handle.trim().toLowerCase();
      if (h && h !== (loaded?.handle ?? '').toLowerCase()) await setMyHandle(h);
      step = 'bio';
      // 안 바뀌었으면 안 쓴다 — 소개를 못 읽은 채 저장을 눌러도 기존 소개가 ''로 덮이지 않는다.
      if (runner === 'yes' && bio.trim() !== loadedBio.trim()) await updateRunnerBio(bio.trim());
      // `router.back()`은 빈 스택에서 no-op이고 이 앱의 모든 라우트는 딥링크로 열린다 (nav.ts).
      goBackOrHome();
    } catch (e) {
      // setMyHandle은 서버 문장을 이미 사람 말로 옮겨서 던진다 (api.ts) — 그대로 붙인다.
      setSaveErr(`${STEP_FAIL[step]} — ${(e as Error).message}`);
    } finally {
      setSaving(false);
    }
  };

  return (
    <View style={{ flex: 1, backgroundColor: paper.canvas }}>
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingBottom: 40 }} keyboardShouldPersistTaps="handled">
        <Row style={s.topBar}>
          <Pressable onPress={goBackOrHome} style={s.backBtn} accessibilityRole="button" accessibilityLabel="뒤로">
            <Text style={{ fontSize: 21, color: paper.ink }}>‹</Text>
          </Pressable>
          <Text style={s.topName}>프로필 편집</Text>
          <View style={{ width: 40 }} />
        </Row>

        {loadErr && (
          <Pressable onPress={() => setGen((g) => g + 1)} style={s.failStrip} accessibilityRole="button">
            <Text style={s.failText}>프로필을 불러오지 못했어요</Text>
            <Text style={s.failSub}>눌러서 다시 시도 — 빈 폼을 저장하면 지금 값이 덮어써져요</Text>
          </Pressable>
        )}
        {/* 러너 판정이 끝나기 전에는 폼을 안 그린다 — '소개' 행이 뒤늦게 튀어나오면 그 사이에
            저장한 러너는 자기 소개 칸이 있는 줄도 모른 채 화면을 떠난다. */}
        {!loadErr && !ready && (
          <View style={s.state}><Text style={s.stateTxt}>불러오는 중...</Text></View>
        )}

        {ready && (
          <>
            <View style={s.list}>
              <Field label="이름" value={name} onChange={setName} placeholder="이름 또는 닉네임" maxLength={20} />
              {/* 소문자·공백 제거는 **정규화**이지 검증이 아니다 — 서버가 하는 것과 같은 접기라서
                  규칙이 두 벌이 되지 않는다 (0074의 교훈). 길이·문자셋·예약어 판정은 전부 서버 몫이고,
                  실패하면 그 문장이 그대로 실패 스트립에 올라온다. 은퇴한 마이 시트의 동작 그대로. */}
              <Field
                label="아이디"
                value={handle}
                onChange={(t) => setHandle(t.toLowerCase().replace(/\s/g, ''))}
                placeholder="아이디 만들기"
                maxLength={20}
                prefix="@"
                autoCapitalize="none"
              />
              <Field label="동네" value={district} onChange={setDistrict} placeholder="예: 반포동" maxLength={20} />
              {runner === 'yes' && (
                <Field label="소개" value={bio} onChange={setBio} placeholder="러닝 경력 · 반려견 경험 · 나의 강점" maxLength={300} multiline last />
              )}
            </View>

            {/* 러너 여부를 못 읽었을 때: 조용히 행을 빼면 '소개 같은 건 없다'로 읽힌다.
                왜 없는지를 말하고, 저장은 소개를 건드리지 않는다 (빈 칸으로 덮어쓰지 않는다). */}
            {runner === 'error' && (
              <Text style={s.note}>소개는 지금 불러올 수 없어요 — 저장해도 기존 소개는 그대로예요</Text>
            )}

            {/* 아이디 규칙은 서버(0074)가 정본이다 — 클라는 형식을 흉내내지 않고 규칙만 옮겨 적는다 */}
            <Text style={s.note}>아이디는 영문 소문자·숫자·밑줄(_)·점(.) · 3~20자예요</Text>
            <Text style={s.note}>프로필 사진은 마이 화면에서 사진을 눌러 바꿔요</Text>

            {saveErr && (
              <View style={s.failStrip}>
                <Text style={s.failText}>{saveErr}</Text>
              </View>
            )}

            {/* busy = label swap (button matrix — no opacity tricks).
                [Sean 2026-08-26 press behaviour] PaperBtn now owns the fill and the 4px lip;
                this file keeps only the layout margins. */}
            <PaperBtn label="저장" busyLabel="저장 중..." onPress={save} busy={saving} style={s.save} />
          </>
        )}
      </ScrollView>

      <StatusBarCover />
    </View>
  );
}

// 인스타 편집기의 한 행: 라벨 왼쪽 · 값 오른쪽 · 아래 헤어라인 하나.
function Field({
  label, value, onChange, placeholder, maxLength, prefix, multiline, autoCapitalize, last,
}: {
  label: string;
  value: string;
  onChange: (v: string) => void;
  placeholder: string;
  maxLength: number;
  prefix?: string;
  multiline?: boolean;
  autoCapitalize?: 'none' | 'sentences';
  last?: boolean;
}) {
  return (
    <View style={[s.row, last && { borderBottomWidth: 0 }]}>
      <Text style={s.rowLabel}>{label}</Text>
      <View style={s.rowValue}>
        {prefix ? <Text style={s.prefix}>{prefix}</Text> : null}
        <TextInput
          value={value}
          onChangeText={onChange}
          placeholder={placeholder}
          placeholderTextColor={paper.faint}
          maxLength={maxLength}
          multiline={multiline}
          autoCapitalize={autoCapitalize}
          autoCorrect={false}
          style={[s.input, multiline && { minHeight: 66, textAlignVertical: 'top' }]}
        />
      </View>
    </View>
  );
}

const s = StyleSheet.create({
  // 페이퍼 월드 — 흰 캔버스 · 솔리드 코랄 헤어라인 · 샤프 코너
  topBar: { justifyContent: 'space-between', paddingHorizontal: 12, paddingTop: 56, paddingBottom: 12 },
  backBtn: { width: 40, height: 40, alignItems: 'center', justifyContent: 'center' },
  topName: { flex: 1, textAlign: 'center', fontSize: 17, fontWeight: '800', color: paper.ink },
  list: { borderTopWidth: 1, borderTopColor: paper.line },
  row: { flexDirection: 'row', alignItems: 'flex-start', gap: 12, paddingHorizontal: 15, paddingVertical: 14, borderBottomWidth: 1, borderBottomColor: paper.line },
  rowLabel: { width: 78, paddingTop: 4, fontSize: 16, lineHeight: 21, fontWeight: '700', color: paper.ink },
  rowValue: { flex: 1, flexDirection: 'row', alignItems: 'flex-start' },
  prefix: { fontSize: 16, lineHeight: 21, paddingTop: 4, color: paper.dim },
  input: { flex: 1, paddingVertical: 4, paddingHorizontal: 0, fontSize: 16, lineHeight: 21, color: paper.ink },
  note: { fontSize: 15, lineHeight: 20, color: paper.dim, paddingHorizontal: 15, marginTop: 10 },
  // Layout only — PaperBtn owns fill, padding and the 17/800 label.
  save: { marginHorizontal: 15, marginTop: 22 },
  state: { paddingVertical: 40, alignItems: 'center' },
  stateTxt: { fontSize: 15, lineHeight: 21, color: paper.dim },
  failStrip: { marginHorizontal: 15, marginTop: 14, padding: 14, backgroundColor: paper.criticalWash, borderWidth: 1, borderColor: paper.critical },
  failText: { fontSize: 15, lineHeight: 20, fontWeight: '700', color: paper.critical },
  failSub: { fontSize: 15, lineHeight: 20, color: paper.critical, marginTop: 3 },
});
