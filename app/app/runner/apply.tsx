import { router } from 'expo-router';
import { useCallback, useEffect, useState } from 'react';
import { Pressable, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { Row } from '../../src/components/ui';
import {
  fetchMyRunnerApplication, fetchMyRunnerCert, fetchMyRunnerStatus,
  MyRunnerCert, RunnerApplication, submitRunnerApplication, withdrawRunnerApplication,
} from '../../src/lib/api';
import { useDisplayFont } from '../../src/lib/displayFont';
import { useNumFont } from '../../src/lib/fonts';
import { lilac, lilacRadius, lilacShadow } from '../../src/theme';

// Runner certification center — the real funnel (0062 / plan §6.2).
//
// History: until 2026-08-05 this screen drew a hardcoded 5-step progress bar with checkmarks for a
// funnel that did not exist. That mock was removed and the screen was cut back to two honest things:
// the server runner record, and a description of the process. It still lied in two smaller ways —
// the process it described had five steps where the pilot has three, and section ③ said personal
// progress tracking was "준비 중" when the real blocker was that there was nowhere to apply.
//
// Now the screen has three sections:
//   ① server runner record — unchanged, reads `runners` columns verbatim.
//   ② the process, cut to the 3 steps the pilot actually performs (§7.2). Still a description of
//      the process, NOT a per-person checklist.
//   ③ my application — bound to `runner_my_application()`. Loading, load failure, never-applied,
//      submitted, under_review, approved, rejected (soft/hard), withdrawn and the attempt cap are
//      nine different renderings because they are nine different facts.
//
// Two rules that are easy to get wrong and are load-bearing here:
//   - submitted / under_review carry NO approval CTA. The next actor is the operator, not the
//     applicant; a greyed-out "승인 대기" button would be a dead button.
//   - the approved state's second line is bound to the runner's REAL `online` value. Approval
//     deliberately does not flip `online` (0062 §3.4), so an approved runner who never turned the
//     switch on is invisible to owners, and the screen has to say which of the two is true.
//
// funnel_step / identity_verified / education_modules_done are still not drawn: 0062 deprecates the
// first and the approval RPC is the only writer of the second.

const TIER_LABEL: Record<string, string> = {
  applicant: '지원자', certified: '인증 러너', veteran: '베테랑', master: '마스터',
};

// The process, as performed during the pilot. Three steps, because there are three steps —
// docs/runner-recruitment.md's fuller funnel (info session, pace test, insurance, bib) is Sean's
// ops, not something this app runs or records. A 5-step brochure over a 3-step process is the same
// class of fabrication the 2026-08-05 repaint removed.
const STEPS: { no: string; label: string; desc: string }[] = [
  { no: '01', label: '지원서', desc: '활동 지역 · 평균 페이스 · 감당 가능한 견종 크기와 러닝·반려견 경험을 적어요' },
  { no: '02', label: '화상 확인', desc: '운영자가 화상 통화로 신분증을 확인하고, 러닝과 반려견 경험을 직접 물어봐요' },
  { no: '03', label: '승인', desc: '승인되면 등급이 인증 러너가 되고 요청을 받기 시작해요' },
];

// Specialty chips. `runners.specialties` is a free text[] (0001:62) with no server-side vocabulary,
// so this list is the client's own; capped at 6 to mirror the array_length check on the table.
const SPECIALTY_OPTIONS = [
  '대형견', '중형견', '소형견', '노견', '퍼피',
  '새벽 러닝', '야간 러닝', '장거리', '행동 교정', '트레일',
];
const SPECIALTY_MAX = 6;

// KST calendar day of an ISO timestamp. The device clock may be UTC (simulator) or abroad, and a
// submission date that is off by one day is a wrong fact, not a rounding detail.
function kstDay(iso: string): string | null {
  const t = Date.parse(iso);
  if (Number.isNaN(t)) return null;
  const d = new Date(t + 9 * 3_600_000);
  return `${d.getUTCMonth() + 1}월 ${d.getUTCDate()}일`;
}

export default function Apply() {
  const df = useDisplayFont(); // display face — screen title, once
  const nf = useNumFont();     // Oswald — numerals / latin kickers (explicit lineHeight required, BUG A)

  // ① server runner record. null = no `runners` row. The separate loaded flag exists because
  // "not arrived" and "known to be nothing" are different facts and neither is drawn as zero.
  const [cert, setCert] = useState<MyRunnerCert | null>(null);
  const [certLoaded, setCertLoaded] = useState(false);
  const [certErr, setCertErr] = useState<string | null>(null);

  // ③ my application. Same three-way split: not loaded / failed / loaded (row or null).
  const [app, setApp] = useState<RunnerApplication | null>(null);
  const [appLoaded, setAppLoaded] = useState(false);
  const [appErr, setAppErr] = useState<string | null>(null);

  // `online` for the approved state's second line. Its own tri-state: until it is known, that line
  // is not drawn at all rather than guessing a switch position on the runner's behalf.
  const [online, setOnline] = useState<boolean | null>(null);

  const loadCert = useCallback(() => {
    setCertErr(null);
    fetchMyRunnerCert()
      .then((c) => { setCert(c); setCertErr(null); })
      .catch((e) => setCertErr(e?.message ?? '러너 정보를 불러오지 못했어요'))
      .finally(() => setCertLoaded(true));
  }, []);

  const loadApp = useCallback(() => {
    setAppErr(null);
    fetchMyRunnerApplication()
      .then((a) => { setApp(a); setAppErr(null); })
      .catch((e) => setAppErr(e?.message ?? '지원 현황을 불러오지 못했어요'))
      .finally(() => setAppLoaded(true));
  }, []);

  useEffect(() => {
    loadCert();
    loadApp();
    fetchMyRunnerStatus()
      .then((s) => setOnline(s.online))
      .catch(() => setOnline(null)); // stays unknown — the online line simply does not render
  }, [loadCert, loadApp]);

  // ——— the form ———
  const [formOpen, setFormOpen] = useState(false);
  const [district, setDistrict] = useState('');
  const [paceMin, setPaceMin] = useState('');
  const [paceSec, setPaceSec] = useState('');
  const [maxWeight, setMaxWeight] = useState('');
  const [radius, setRadius] = useState('3');
  const [specialties, setSpecialties] = useState<string[]>([]);
  const [bio, setBio] = useState('');
  const [runExp, setRunExp] = useState('');
  const [dogExp, setDogExp] = useState('');
  const [kakao, setKakao] = useState('');
  const [contactWindow, setContactWindow] = useState('');
  const [cTerms, setCTerms] = useState(false);
  const [cPrivacy, setCPrivacy] = useState(false);
  const [cIdCheck, setCIdCheck] = useState(false);
  const [formErr, setFormErr] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [withdrawing, setWithdrawing] = useState(false);
  const [withdrawErr, setWithdrawErr] = useState<string | null>(null);
  const [confirmWithdraw, setConfirmWithdraw] = useState(false);

  const toggleSpecialty = (sp: string) => {
    setSpecialties((cur) => (
      cur.includes(sp) ? cur.filter((x) => x !== sp)
        : cur.length >= SPECIALTY_MAX ? cur
          : [...cur, sp]
    ));
  };

  // Client-side validation mirrors the check constraints on `runner_applications` (0062 §3.2) one
  // for one, so the constraint is a backstop and never the UX. A constraint violation that reaches
  // the server is therefore a bug in this function, and api.ts surfaces it raw rather than dressing
  // it up as a funnel state.
  const validate = (): string | null => {
    const d = district.trim();
    if (d.length < 1) return '활동 지역을 적어주세요';
    if (d.length > 40) return '활동 지역은 40자까지 적을 수 있어요';

    const pm = Number(paceMin);
    const ps = paceSec.trim() === '' ? 0 : Number(paceSec);
    if (!Number.isFinite(pm) || paceMin.trim() === '') return '평균 페이스를 적어주세요';
    if (!Number.isFinite(ps) || ps < 0 || ps > 59) return '페이스의 초는 0~59 사이로 적어주세요';
    const pace = Math.round(pm * 60 + ps);
    if (pace < 180 || pace > 900) return '평균 페이스는 1km당 3분 00초 ~ 15분 00초 사이로 적어주세요';

    const w = Number(maxWeight);
    if (maxWeight.trim() === '' || !Number.isFinite(w)) return '감당 가능한 최대 체중을 적어주세요';
    if (w < 1 || w > 80) return '감당 가능한 최대 체중은 1~80kg 사이로 적어주세요';

    const r = Number(radius);
    if (radius.trim() === '' || !Number.isFinite(r)) return '활동 반경을 적어주세요';
    if (r < 0.5 || r > 20) return '활동 반경은 0.5~20km 사이로 적어주세요';

    if (specialties.length > SPECIALTY_MAX) return `전문 분야는 ${SPECIALTY_MAX}개까지 고를 수 있어요`;

    const b = bio.trim();
    if (b.length < 10) return '한 줄 소개를 10자 이상 적어주세요';
    if (b.length > 500) return '한 줄 소개는 500자까지 적을 수 있어요';

    const re = runExp.trim();
    if (re.length < 10) return '러닝 경력을 10자 이상 적어주세요';
    if (re.length > 1000) return '러닝 경력은 1000자까지 적을 수 있어요';

    const de = dogExp.trim();
    if (de.length < 10) return '반려견 경험을 10자 이상 적어주세요';
    if (de.length > 1000) return '반려견 경험은 1000자까지 적을 수 있어요';

    const k = kakao.trim();
    if (k.length < 1) return '카카오톡 ID를 적어주세요';
    if (k.length > 60) return '카카오톡 ID는 60자까지 적을 수 있어요';
    if (contactWindow.trim().length > 200) return '연락 가능한 시간은 200자까지 적을 수 있어요';

    if (!cTerms || !cPrivacy || !cIdCheck) return '필수 동의 항목 세 개를 모두 확인해주세요';
    return null;
  };

  const submit = async () => {
    if (submitting) return;
    const bad = validate();
    if (bad) { setFormErr(bad); return; }
    setFormErr(null);
    setSubmitting(true);
    try {
      await submitRunnerApplication({
        district: district.trim(),
        paceSecPerKm: Math.round(Number(paceMin) * 60 + (paceSec.trim() === '' ? 0 : Number(paceSec))),
        maxDogWeightKg: Number(maxWeight),
        serviceRadiusKm: Number(radius),
        specialties,
        bio: bio.trim(),
        runningExperience: runExp.trim(),
        dogExperience: dogExp.trim(),
        contactKakao: kakao.trim(),
        // ⚠ Privacy precondition (plan §3.6). No 개인정보처리방침 is published — a draft exists at
        // docs/legal/privacy-policy.md but is unpublished and unreviewed. Collecting a phone number
        // before that policy is live is a compliance problem, so the pilot form collects a KakaoTalk
        // ID only and the consent copy says the operator will contact them there. The table's
        // runner_app_contact_present constraint accepts either one, so the phone field can be added
        // as a sibling of the Kakao field the day the policy is published — nothing else changes.
        contactPhone: null,
        contactWindow: contactWindow.trim() === '' ? null : contactWindow.trim(),
        consentTerms: cTerms,
        consentPrivacy: cPrivacy,
        consentIdCheck: cIdCheck,
      });
      setFormOpen(false);
      setAppLoaded(false); // the new row is the screen's next fact — show loading, not a stale state
      loadApp();
    } catch (e) {
      setFormErr((e as Error).message);
    } finally {
      setSubmitting(false);
    }
  };

  const withdraw = async () => {
    if (!app || withdrawing) return;
    setWithdrawErr(null);
    setWithdrawing(true);
    try {
      await withdrawRunnerApplication(app.id);
      setConfirmWithdraw(false);
      setAppLoaded(false);
      loadApp();
    } catch (e) {
      setWithdrawErr((e as Error).message);
    } finally {
      setWithdrawing(false);
    }
  };

  const openForm = () => {
    setFormErr(null);
    setFormOpen(true);
  };

  return (
    <View style={{ flex: 1, backgroundColor: lilac.bg }}>
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingHorizontal: 14, paddingTop: 58, paddingBottom: 40 }}>

        {/* ————— 마스트헤드 ————— */}
        <Row style={{ gap: 10 }}>
          <Pressable onPress={() => router.back()} style={s.backBtn} accessibilityRole="button" accessibilityLabel="뒤로">
            <Text style={{ fontSize: 19, fontWeight: '700', color: lilac.head, marginTop: -2 }}>‹</Text>
          </Pressable>
          <View style={s.rule} />
          <Text style={[s.kick, nf]}>RUNNER · CERTIFICATION</Text>
        </Row>
        <Text style={[s.h1, df]}>인증 센터</Text>
        <Text style={s.lede}>
          검증된 러너만 아이들을 만나요{'\n'}여기서 지원하고, 심사가 어디까지 왔는지 확인할 수 있어요
        </Text>

        {/* ————— ① 내 러너 레코드 — 서버 진실 ————— */}
        <SecRule no="§" en="RECORD" ko="내 러너 레코드" />
        {!certLoaded && (
          <View style={s.plain}><Text style={s.plainTxt}>러너 레코드를 불러오는 중이에요…</Text></View>
        )}
        {certLoaded && certErr !== null && (
          <View style={s.errBox}>
            <View style={s.errTick} />
            <View style={{ flex: 1 }}>
              <Text style={s.errT}>러너 레코드를 불러오지 못했어요</Text>
              <Text style={s.errD}>{certErr}</Text>
              <Pressable onPress={loadCert} style={s.retry} accessibilityRole="button" accessibilityLabel="러너 레코드 다시 불러오기">
                <Text style={s.retryTxt}>다시 시도</Text>
              </Pressable>
            </View>
          </View>
        )}
        {certLoaded && certErr === null && cert === null && (
          <View style={s.plain}>
            <Text style={s.plainT}>아직 러너로 등록되어 있지 않아요</Text>
            <Text style={s.plainTxt}>
              러너 레코드가 만들어져야 등급과 누적 기록이 생겨요{'\n'}러너 모드로 한 번 들어오면 레코드가 만들어져요
            </Text>
          </View>
        )}
        {certLoaded && certErr === null && cert !== null && (
          <View style={s.rec}>
            <View style={s.recInner}>
              <Row style={s.recStrap}>
                <Text style={[s.micro, nf]}>SERVER RECORD</Text>
                <View style={s.srcTag}><Text style={[s.srcTagTxt, nf]}>RUNNERS</Text></View>
              </Row>

              <Text style={s.recK}>현재 등급</Text>
              <Text style={s.recTier}>{TIER_LABEL[cert.tier] ?? cert.tier}</Text>
              <Text style={s.recNote}>
                {cert.tier === 'applicant'
                  ? '지원자 등급은 아직 요청을 받을 수 없어요 — 인증이 끝나야 매칭에 올라가요'
                  : '요청을 받을 수 있는 등급이에요 — 지명 목록과 오픈 요청에 올라가요'}
              </Text>

              <Row style={s.grid}>
                {/* 단위는 숫자 Text 밖의 형제로 둔다 — Oswald(라틴 전용) 안에 한글을 넣지 않는다 */}
                <View style={s.cell}>
                  <Text style={s.cellK}>완주</Text>
                  <Row style={s.cellVal}>
                    <Text style={[s.cellV, nf]}>{cert.totalRuns.toLocaleString()}</Text>
                    <Text style={s.cellU}>회</Text>
                  </Row>
                </View>
                <View style={[s.cell, s.cellDiv]}>
                  <Text style={s.cellK}>누적 거리</Text>
                  <Row style={s.cellVal}>
                    <Text style={[s.cellV, nf]}>{cert.totalKm.toFixed(1)}</Text>
                    <Text style={s.cellU}>km</Text>
                  </Row>
                </View>
                <View style={[s.cell, s.cellDiv]}>
                  <Text style={s.cellK}>정산 수수료</Text>
                  <Row style={s.cellVal}>
                    <Text style={[s.cellV, nf]}>{Math.round(cert.commissionRate * 100)}</Text>
                    <Text style={s.cellU}>%</Text>
                  </Row>
                </View>
              </Row>
            </View>
            <Text style={s.recFoot}>
              네 값 모두 서버 러너 레코드에서 그대로 읽어요 — 완주와 거리는 정산이 올리고, 수수료율은 정산에 그대로 쓰여요
            </Text>
          </View>
        )}

        {/* ————— ② 인증 절차의 구성 — 개인 체크마크 아님 ————— */}
        <SecRule no="§" en="PROCESS" ko="인증 절차는 이렇게 구성돼요" />
        <View style={s.stepCard}>
          <Text style={s.stepLede}>아래는 절차가 무엇인지에 대한 설명이에요 — 내가 어디까지 왔는지는 아래 §APPLICATION에서 볼 수 있어요</Text>
          {STEPS.map((st, i) => (
            <View key={st.no} style={[s.step, i > 0 && s.stepDiv]}>
              <Text style={[s.stepNo, nf]}>{st.no}</Text>
              <View style={{ flex: 1 }}>
                <Text style={s.stepT}>{st.label}</Text>
                <Text style={s.stepD}>{st.desc}</Text>
              </View>
            </View>
          ))}
          <Text style={s.stepFoot}>파일럿 기간에는 운영자가 한 명씩 직접 확인해요 — 자동 심사는 없어요</Text>
        </View>

        {/* ————— ③ 내 지원 현황 — runner_my_application()에 바인딩 ————— */}
        <SecRule no="§" en="APPLICATION" ko="내 지원 현황" />

        {/* not loaded — loading is not empty */}
        {!appLoaded && (
          <View style={s.plain}><Text style={s.plainTxt}>지원 현황을 불러오는 중이에요…</Text></View>
        )}

        {/* load failed — failures render as failures, and 다시 시도 really re-fetches */}
        {appLoaded && appErr !== null && (
          <View style={s.errBox}>
            <View style={s.errTick} />
            <View style={{ flex: 1 }}>
              <Text style={s.errT}>지원 현황을 불러오지 못했어요</Text>
              <Text style={s.errD}>{appErr}</Text>
              <Pressable onPress={loadApp} style={s.retry} accessibilityRole="button" accessibilityLabel="지원 현황 다시 불러오기">
                <Text style={s.retryTxt}>다시 시도</Text>
              </Pressable>
            </View>
          </View>
        )}

        {/* Grandfathered: certified with no application row. Every runner certified before 0062
            existed is in this state, so it is the common case today, not an edge case. Without
            this branch they saw "아직 지원서를 내지 않았어요" plus a submit CTA that fills out ten
            fields and then dies on the server's already_certified guard — a dead button by the
            length of a whole form. Found on the simulator, 2026-08-10. */}
        {appLoaded && appErr === null && app === null && !formOpen
          && certLoaded && certErr === null && cert !== null && cert.tier !== 'applicant' && (
          <View style={s.stateCard}>
            <StateStrap tone={lilac.voltDeep} label="승인" />
            <Text style={s.stateT}>이미 인증된 러너예요</Text>
            <Text style={s.stateD}>
              지금 등급은 {TIER_LABEL[cert.tier] ?? cert.tier}예요 — 지원서를 다시 낼 필요는 없어요.{'\n'}
              등급이나 기록이 잘못돼 보이면 설정의 문의하기로 알려주세요.
            </Text>
          </View>
        )}

        {/* no row — never applied. The screen's first real submit. */}
        {appLoaded && appErr === null && app === null && !formOpen
          && !(certLoaded && certErr === null && cert !== null && cert.tier !== 'applicant') && (
          <View style={s.stateCard}>
            <Text style={s.stateT}>아직 지원서를 내지 않았어요</Text>
            <Text style={s.stateD}>
              지원서를 내면 운영자가 확인하고 화상 통화 일정을 알려드려요.{'\n'}
              통화에서는 신분증으로 신원을 확인하고, 러닝과 반려견 경험을 직접 물어봐요 — 10~15분이면 끝나요.
            </Text>
            <Pressable onPress={openForm} style={s.ctaPrimary} accessibilityRole="button" accessibilityLabel="러너 지원서 작성 시작">
              <Text style={s.ctaPrimaryT}>러너 지원서 작성</Text>
              <Text style={s.ctaPrimaryGo}>›</Text>
            </Pressable>
          </View>
        )}

        {/* submitted — NO approval CTA: the next actor is the operator, and a disabled button is a dead button */}
        {appLoaded && appErr === null && app !== null && app.state === 'submitted' && !formOpen && (
          <View style={s.stateCard}>
            <StateStrap tone={lilac.amber} label="접수됨" />
            <Text style={s.stateT}>지원서가 접수됐어요</Text>
            <Text style={s.stateD}>
              {kstDay(app.submittedAt) ? `${kstDay(app.submittedAt)}에 접수됐어요 · ` : ''}
              운영자가 확인하면 적어주신 연락처로 화상 통화 일정을 알려드려요
            </Text>
            <WithdrawBlock
              confirm={confirmWithdraw} setConfirm={setConfirmWithdraw}
              busy={withdrawing} err={withdrawErr} onWithdraw={withdraw}
            />
          </View>
        )}

        {/* under_review */}
        {appLoaded && appErr === null && app !== null && app.state === 'under_review' && !formOpen && (
          <View style={s.stateCard}>
            <StateStrap tone={lilac.accent} label="검토 중" />
            <Text style={s.stateT}>운영자가 확인하고 있어요</Text>
            <Text style={s.stateD}>
              {kstDay(app.reviewedAt ?? '') ? `${kstDay(app.reviewedAt ?? '')}부터 검토 중이에요 · ` : ''}
              적어주신 연락 가능한 시간에 맞춰 연락드릴게요
            </Text>
            <WithdrawBlock
              confirm={confirmWithdraw} setConfirm={setConfirmWithdraw}
              busy={withdrawing} err={withdrawErr} onWithdraw={withdraw}
            />
          </View>
        )}

        {/* approved — no CTA; one line bound to the REAL `online` value (approval never flips it) */}
        {appLoaded && appErr === null && app !== null && app.state === 'approved' && !formOpen && (
          <View style={s.stateCard}>
            <StateStrap tone={lilac.voltDeep} label="승인" />
            <Text style={s.stateT}>인증이 끝났어요</Text>
            <Text style={s.stateD}>운영자 확인을 마쳤어요 — 이제 요청을 받을 수 있어요</Text>
            {cert !== null && (
              <Text style={s.stateMeta}>지금 등급은 {TIER_LABEL[cert.tier] ?? cert.tier}예요 — 위 러너 레코드와 같은 값이에요</Text>
            )}
            {online !== null && (
              <View style={s.onlineLine}>
                <View style={[s.onlineDot, { backgroundColor: online ? lilac.voltDeep : lilac.dim }]} />
                <Text style={s.onlineTxt}>
                  {online
                    ? '지금 온라인 상태예요 · 요청이 오면 러너 홈에 떠요'
                    : '온라인으로 켜야 요청이 와요 · 러너 홈에서 켤 수 있어요'}
                </Text>
              </View>
            )}
          </View>
        )}

        {/* rejected — reject_reason verbatim. Hard bar is terminal; the cap is a separate fact. */}
        {appLoaded && appErr === null && app !== null && app.state === 'rejected' && !formOpen && (
          <View style={s.stateCard}>
            <StateStrap tone={lilac.coralDeep} label="미승인" />
            <Text style={s.stateT}>이번엔 승인되지 않았어요</Text>
            {app.rejectReason !== null && app.rejectReason.trim() !== '' && (
              <View style={s.reasonBox}>
                <Text style={s.reasonK}>운영자가 남긴 사유</Text>
                {/* verbatim — this is the applicant's copy of the decision, not a paraphrase */}
                <Text style={s.reasonV}>{app.rejectReason}</Text>
              </View>
            )}
            {app.isHardBar ? (
              <>
                <Text style={s.stateD}>이 계정으로는 다시 지원할 수 없어요</Text>
                <ContactCta />
              </>
            ) : app.canReapply ? (
              <>
                <Text style={s.stateD}>보완해서 다시 지원할 수 있어요 · 지원은 3번까지 할 수 있어요 (지금 {app.attemptNo}번째)</Text>
                <Pressable onPress={openForm} style={s.ctaPrimary} accessibilityRole="button" accessibilityLabel="러너 지원서 다시 작성">
                  <Text style={s.ctaPrimaryT}>다시 지원하기</Text>
                  <Text style={s.ctaPrimaryGo}>›</Text>
                </Pressable>
              </>
            ) : (
              <>
                <Text style={s.stateD}>지원은 3번까지 할 수 있어요</Text>
                <ContactCta />
              </>
            )}
          </View>
        )}

        {/* withdrawn */}
        {appLoaded && appErr === null && app !== null && app.state === 'withdrawn' && !formOpen && (
          <View style={s.stateCard}>
            <StateStrap tone={lilac.dim} label="취소됨" />
            <Text style={s.stateT}>지원을 취소했어요</Text>
            {app.canReapply ? (
              <>
                <Text style={s.stateD}>다시 지원할 수 있어요 · 지원은 3번까지 할 수 있어요 (지금 {app.attemptNo}번째)</Text>
                <Pressable onPress={openForm} style={s.ctaPrimary} accessibilityRole="button" accessibilityLabel="러너 지원서 다시 작성">
                  <Text style={s.ctaPrimaryT}>다시 지원하기</Text>
                  <Text style={s.ctaPrimaryGo}>›</Text>
                </Pressable>
              </>
            ) : (
              <>
                <Text style={s.stateD}>지원은 3번까지 할 수 있어요</Text>
                <ContactCta />
              </>
            )}
          </View>
        )}

        {/* ————— the form ————— */}
        {formOpen && (
          <View style={s.formCard}>
            <Text style={s.formT}>러너 지원서</Text>
            <Text style={s.formD}>적어주신 내용은 운영자가 심사에 쓰고, 승인되면 그대로 러너 프로필이 돼요</Text>

            <Field label="활동 지역" hint="주로 뛰는 동네를 적어주세요 (예: 성수동)">
              <TextInput
                value={district} onChangeText={setDistrict} maxLength={40}
                placeholder="성수동" placeholderTextColor={lilac.dim} style={s.input}
              />
            </Field>

            <Field label="평균 페이스" hint="1km당 걸리는 시간 · 3분 00초 ~ 15분 00초">
              <Row style={{ gap: 8, alignItems: 'center' }}>
                <TextInput
                  value={paceMin} onChangeText={setPaceMin} keyboardType="number-pad" maxLength={2}
                  placeholder="6" placeholderTextColor={lilac.dim} style={[s.input, { flex: 1 }]}
                />
                <Text style={s.unit}>분</Text>
                <TextInput
                  value={paceSec} onChangeText={setPaceSec} keyboardType="number-pad" maxLength={2}
                  placeholder="00" placeholderTextColor={lilac.dim} style={[s.input, { flex: 1 }]}
                />
                <Text style={s.unit}>초</Text>
              </Row>
            </Field>

            <Field label="감당 가능한 최대 체중" hint="이 무게까지의 아이를 맡을 수 있어요 · 1~80kg">
              <Row style={{ gap: 8, alignItems: 'center' }}>
                <TextInput
                  value={maxWeight} onChangeText={setMaxWeight} keyboardType="decimal-pad" maxLength={4}
                  placeholder="20" placeholderTextColor={lilac.dim} style={[s.input, { flex: 1 }]}
                />
                <Text style={s.unit}>kg</Text>
              </Row>
            </Field>

            <Field label="활동 반경" hint="집이나 활동 지역에서 이 거리 안까지 가요 · 0.5~20km">
              <Row style={{ gap: 8, alignItems: 'center' }}>
                <TextInput
                  value={radius} onChangeText={setRadius} keyboardType="decimal-pad" maxLength={4}
                  placeholder="3" placeholderTextColor={lilac.dim} style={[s.input, { flex: 1 }]}
                />
                <Text style={s.unit}>km</Text>
              </Row>
            </Field>

            <Field label="전문 분야" hint={`최대 ${SPECIALTY_MAX}개 · 지금 ${specialties.length}개 골랐어요`}>
              <Row style={{ flexWrap: 'wrap', gap: 7 }}>
                {SPECIALTY_OPTIONS.map((sp) => {
                  const on = specialties.includes(sp);
                  const full = !on && specialties.length >= SPECIALTY_MAX;
                  return (
                    <Pressable
                      key={sp} onPress={() => toggleSpecialty(sp)}
                      style={[s.chip, on && s.chipOn, full && s.chipFull]}
                      accessibilityRole="button"
                      accessibilityState={{ selected: on }}
                      accessibilityLabel={`전문 분야 ${sp}${on ? ' 선택 해제' : ' 선택'}`}
                    >
                      <Text style={[s.chipTxt, on && s.chipTxtOn]}>{sp}</Text>
                    </Pressable>
                  );
                })}
              </Row>
              {specialties.length >= SPECIALTY_MAX && (
                <Text style={s.fieldNote}>{SPECIALTY_MAX}개를 다 골랐어요 — 바꾸려면 하나를 눌러 해제해주세요</Text>
              )}
            </Field>

            <Field label="한 줄 소개" hint="보호자에게 보이는 소개예요 · 10~500자">
              <TextInput
                value={bio} onChangeText={setBio} maxLength={500} multiline
                placeholder="아침마다 한강을 뛰고, 대형견과 함께 뛰는 걸 좋아해요"
                placeholderTextColor={lilac.dim} style={[s.input, s.inputMulti]}
              />
            </Field>

            <Field label="러닝 경력" hint="얼마나 뛰었는지, 주에 몇 번 뛰는지 · 10~1000자">
              <TextInput
                value={runExp} onChangeText={setRunExp} maxLength={1000} multiline
                placeholder="3년째 주 4회 · 하프 2회 완주"
                placeholderTextColor={lilac.dim} style={[s.input, s.inputMulti]}
              />
            </Field>

            <Field label="반려견 경험" hint="키워봤거나 돌봐본 경험, 다룰 수 있는 크기 · 10~1000자">
              <TextInput
                value={dogExp} onChangeText={setDogExp} maxLength={1000} multiline
                placeholder="리트리버와 8년 살았고, 대형견 산책 대행 경험이 있어요"
                placeholderTextColor={lilac.dim} style={[s.input, s.inputMulti]}
              />
            </Field>

            <Field label="카카오톡 ID" hint="운영자가 여기로 연락드려요">
              <TextInput
                value={kakao} onChangeText={setKakao} maxLength={60} autoCapitalize="none"
                placeholder="kakao_id" placeholderTextColor={lilac.dim} style={s.input}
              />
            </Field>

            <Field label="연락 가능한 시간" hint="비워둬도 괜찮아요 · 200자까지">
              <TextInput
                value={contactWindow} onChangeText={setContactWindow} maxLength={200}
                placeholder="평일 저녁 7시 이후 · 주말 아무 때나"
                placeholderTextColor={lilac.dim} style={s.input}
              />
            </Field>

            {/* Personal-data notice (0062 §3.6). It names what is collected, why, and for how long,
                in the form itself — because there is no published 개인정보처리방침 to link to, and a
                consent checkbox pointing at a document that does not exist is a dead link. */}
            <View style={s.notice}>
              <Text style={s.noticeT}>개인정보 수집·이용 안내</Text>
              <Text style={s.noticeD}>
                수집 항목: 활동 지역 · 평균 페이스 · 감당 가능한 최대 체중 · 활동 반경 · 전문 분야 · 한 줄 소개 · 러닝 경력 · 반려견 경험 · 카카오톡 ID · 연락 가능한 시간{'\n'}
                이용 목적: 러너 심사와 화상 통화 일정 안내, 승인 후 러너 프로필 작성{'\n'}
                보관 기간: 파일럿이 끝날 때까지 보관해요 · 그 전이라도 설정 › 문의하기로 삭제를 요청하면 지워드려요{'\n'}
                파일럿 기간에는 휴대폰 번호를 받지 않아요 — 운영자가 카카오톡으로만 연락해요
              </Text>
            </View>

            <Check on={cTerms} set={setCTerms} label="댕런 러너로 활동하는 동안 안전 수칙을 지키고 운영자 안내를 따를게요 (필수)" />
            <Check on={cPrivacy} set={setCPrivacy} label="위 안내대로 개인정보를 수집·이용하는 데 동의해요 (필수)" />
            <Check on={cIdCheck} set={setCIdCheck} label="화상 통화에서 신분증으로 신원을 확인하는 데 동의해요 (필수)" />

            {formErr !== null && (
              <View style={[s.errBox, { marginTop: 13 }]}>
                <View style={s.errTick} />
                <View style={{ flex: 1 }}>
                  <Text style={s.errT}>지원서를 접수하지 못했어요</Text>
                  <Text style={s.errD}>{formErr}</Text>
                </View>
              </View>
            )}

            {/* Always pressable: an inert submit button would be a dead button, so validation runs on
                press and names the first field that is not ready. In flight, the label says so. */}
            <Pressable
              onPress={submit}
              style={[s.submit, submitting && s.submitBusy]}
              accessibilityRole="button"
              accessibilityState={{ busy: submitting }}
              accessibilityLabel="지원서 접수하기"
            >
              <Text style={s.submitTxt}>{submitting ? '접수 중이에요…' : '지원서 접수하기'}</Text>
            </Pressable>
            <Pressable
              onPress={() => { if (!submitting) { setFormOpen(false); setFormErr(null); } }}
              style={s.formCancel}
              accessibilityRole="button"
              accessibilityLabel="지원서 작성 그만두기"
            >
              <Text style={s.formCancelTxt}>그만두기</Text>
            </Pressable>
          </View>
        )}

        <View style={s.colophon}>
          <Text style={[s.colophonTxt, nf]}>DOGS HIGH · RUNNER CERTIFICATION</Text>
        </View>
      </ScrollView>
    </View>
  );
}

// 섹션 룰 — § 글리프(12pt 면제) + 대문자 키커 + 헤어라인 + 한글 라벨
function SecRule({ no, en, ko }: { no: string; en: string; ko: string }) {
  const nf = useNumFont();
  return (
    <Row style={s.sec}>
      <Text style={s.secNo}>{no}</Text>
      <Text style={[s.secT, nf]}>{en}</Text>
      <View style={s.rule} />
      <Text style={s.secKo}>{ko}</Text>
    </Row>
  );
}

// State strap — a small tone-coded tag above the state headline.
function StateStrap({ tone, label }: { tone: string; label: string }) {
  const nf = useNumFont();
  return (
    <Row style={{ alignItems: 'center', gap: 7, marginBottom: 8 }}>
      <View style={[s.strapDot, { backgroundColor: tone }]} />
      <Text style={[s.strapTxt, { color: tone }]}>{label}</Text>
      <View style={s.rule} />
      <Text style={[s.micro, nf]}>APPLICATION</Text>
    </Row>
  );
}

// 문의하기 — only rendered where 문의 is genuinely the next action (hard bar, attempt cap).
function ContactCta() {
  return (
    <Pressable
      onPress={() => router.push('/settings')}
      style={s.cta}
      accessibilityRole="button"
      accessibilityLabel="설정 화면의 문의하기로 이동"
    >
      <View style={{ flex: 1 }}>
        <Text style={s.ctaT}>문의하기</Text>
        <Text style={s.ctaD}>설정 › 문의하기로 이동해요</Text>
      </View>
      <Text style={s.ctaGo}>›</Text>
    </Pressable>
  );
}

// Withdraw — two taps, because withdrawing is the applicant's own irreversible-ish move, and one
// server call. The server decides whether the state is withdrawable; the screen never guesses.
function WithdrawBlock({ confirm, setConfirm, busy, err, onWithdraw }: {
  confirm: boolean; setConfirm: (v: boolean) => void; busy: boolean; err: string | null; onWithdraw: () => void;
}) {
  return (
    <View style={{ marginTop: 13 }}>
      {err !== null && (
        <View style={[s.errBox, { marginBottom: 10 }]}>
          <View style={s.errTick} />
          <View style={{ flex: 1 }}>
            <Text style={s.errT}>지원을 취소하지 못했어요</Text>
            <Text style={s.errD}>{err}</Text>
          </View>
        </View>
      )}
      {!confirm ? (
        <Pressable onPress={() => setConfirm(true)} style={s.cta} accessibilityRole="button" accessibilityLabel="지원 취소하기">
          <View style={{ flex: 1 }}>
            <Text style={s.ctaT}>지원 취소</Text>
            <Text style={s.ctaD}>취소해도 3번까지 다시 지원할 수 있어요</Text>
          </View>
          <Text style={s.ctaGo}>›</Text>
        </Pressable>
      ) : (
        <View>
          <Text style={s.confirmTxt}>지원을 취소할까요? 취소하면 운영자 대기 목록에서 빠져요</Text>
          <Row style={{ gap: 8, marginTop: 9 }}>
            <Pressable
              onPress={onWithdraw}
              style={[s.confirmYes, busy && s.submitBusy]}
              accessibilityRole="button"
              accessibilityState={{ busy }}
              accessibilityLabel="지원 취소 확정"
            >
              <Text style={s.confirmYesTxt}>{busy ? '취소 중이에요…' : '네, 취소할게요'}</Text>
            </Pressable>
            <Pressable
              onPress={() => { if (!busy) setConfirm(false); }}
              style={s.confirmNo}
              accessibilityRole="button"
              accessibilityLabel="지원 취소 그만두기"
            >
              <Text style={s.confirmNoTxt}>아니요</Text>
            </Pressable>
          </Row>
        </View>
      )}
    </View>
  );
}

function Field({ label, hint, children }: { label: string; hint?: string; children: React.ReactNode }) {
  return (
    <View style={{ marginTop: 14 }}>
      <Text style={s.fieldL}>{label}</Text>
      {hint ? <Text style={s.fieldH}>{hint}</Text> : null}
      <View style={{ marginTop: 6 }}>{children}</View>
    </View>
  );
}

function Check({ on, set, label }: { on: boolean; set: (v: boolean) => void; label: string }) {
  return (
    <Pressable
      onPress={() => set(!on)}
      style={s.check}
      accessibilityRole="checkbox"
      accessibilityState={{ checked: on }}
      accessibilityLabel={label}
    >
      <View style={[s.checkBox, on && s.checkBoxOn]}>
        {on && <Text style={s.checkMark}>✓</Text>}
      </View>
      <Text style={s.checkTxt}>{label}</Text>
    </Pressable>
  );
}

const s = StyleSheet.create({
  // ── 마스트헤드 ──
  backBtn: {
    width: 34, height: 34, borderRadius: 10, backgroundColor: lilac.card,
    alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: lilac.hair,
  },
  rule: { flex: 1, height: 1, backgroundColor: lilac.hair },
  kick: { fontSize: 12, lineHeight: 16, letterSpacing: 1.8, color: lilac.dim }, // Oswald 1.33× (BUG A)
  h1: { fontSize: 36, lineHeight: 44, fontWeight: '900', color: lilac.head, marginTop: 10 },
  lede: { fontSize: 14, lineHeight: 21, color: lilac.text, marginTop: 8 },

  // ── 섹션 룰 ──
  sec: { alignItems: 'center', gap: 8, marginTop: 20, marginBottom: 9 },
  secNo: { fontSize: 12, fontWeight: '600', color: lilac.accent }, // 글리프 전용(§) — 14pt 플로어 면제
  secT: { fontSize: 12, lineHeight: 16, letterSpacing: 1.8, color: lilac.dim }, // Oswald 1.33×
  secKo: { fontSize: 14, fontWeight: '700', color: lilac.text },

  // ── ① 러너 레코드 ──
  rec: {
    backgroundColor: lilac.card, borderWidth: 1, borderColor: lilac.hair,
    borderRadius: lilacRadius.card, overflow: 'hidden', ...lilacShadow,
  },
  recInner: { margin: 9, borderWidth: 1, borderColor: lilac.hair2, borderRadius: lilacRadius.inner, padding: 13 },
  recStrap: { justifyContent: 'space-between', alignItems: 'center', marginBottom: 12 },
  micro: { fontSize: 12, lineHeight: 16, letterSpacing: 1.6, color: lilac.dim }, // Oswald 1.33×
  srcTag: {
    borderWidth: 1, borderColor: '#DCD6F8', backgroundColor: '#F4F1FE',
    borderRadius: lilacRadius.tag, paddingVertical: 3, paddingHorizontal: 8,
  },
  srcTagTxt: { fontSize: 12, lineHeight: 16, letterSpacing: 1, color: lilac.accent }, // Oswald 1.33×
  recK: { fontSize: 14, color: lilac.dim },
  recTier: { fontSize: 28, lineHeight: 34, fontWeight: '900', color: lilac.head, marginTop: 3 },
  recNote: { fontSize: 14, lineHeight: 20, color: lilac.text, marginTop: 6 },
  grid: { alignItems: 'stretch', marginTop: 13, marginHorizontal: -13, borderTopWidth: 1, borderTopColor: lilac.hair2 },
  cell: { flex: 1, paddingTop: 10, paddingBottom: 2, paddingLeft: 13 },
  cellDiv: { borderLeftWidth: 1, borderLeftColor: lilac.hair2 },
  cellK: { fontSize: 14, lineHeight: 18, color: lilac.dim, marginBottom: 2 }, // 한글 라벨 — 14pt 플로어 준수
  cellVal: { alignItems: 'baseline', gap: 3 },
  cellV: { fontSize: 22, lineHeight: 28, color: lilac.head }, // Oswald 1.27× (BUG A)
  cellU: { fontSize: 14, lineHeight: 18, color: lilac.dim },
  recFoot: { fontSize: 14, lineHeight: 20, color: lilac.dim, paddingHorizontal: 13, paddingBottom: 12, paddingTop: 2 },

  // ── 로딩 · 빈 상태 ──
  plain: {
    backgroundColor: lilac.inset, borderWidth: 1, borderColor: lilac.hair,
    borderRadius: lilacRadius.card, padding: 14,
  },
  plainT: { fontSize: 14, lineHeight: 20, fontWeight: '700', color: lilac.head, marginBottom: 3 },
  plainTxt: { fontSize: 14, lineHeight: 20, color: lilac.text },

  // ── 실패는 실패로 ──
  errBox: {
    flexDirection: 'row', alignItems: 'flex-start', gap: 10,
    backgroundColor: lilac.card, borderWidth: 1, borderColor: lilac.hair,
    borderRadius: lilacRadius.card, padding: 13,
  },
  errTick: { width: 3, alignSelf: 'stretch', borderRadius: 2, backgroundColor: lilac.coralDeep },
  errT: { fontSize: 14, lineHeight: 20, fontWeight: '700', color: lilac.head },
  errD: { fontSize: 14, lineHeight: 20, color: lilac.dim, marginTop: 2 },
  retry: {
    alignSelf: 'flex-start', marginTop: 9, borderWidth: 1, borderColor: lilac.hair,
    backgroundColor: lilac.inset, borderRadius: lilacRadius.btn, paddingVertical: 8, paddingHorizontal: 13,
  },
  retryTxt: { fontSize: 14, lineHeight: 18, fontWeight: '800', color: lilac.head },

  // ── ② 절차 ──
  stepCard: {
    backgroundColor: lilac.card, borderWidth: 1, borderColor: lilac.hair,
    borderRadius: lilacRadius.card, paddingHorizontal: 13, paddingBottom: 4, ...lilacShadow,
  },
  stepLede: { fontSize: 14, lineHeight: 20, color: lilac.dim, paddingTop: 13, paddingBottom: 3 },
  step: { flexDirection: 'row', alignItems: 'flex-start', gap: 11, paddingVertical: 12 },
  stepDiv: { borderTopWidth: 1, borderTopColor: lilac.hair2 },
  stepNo: { fontSize: 14, lineHeight: 20, letterSpacing: 0.8, color: lilac.accent, width: 22 }, // Oswald 1.43×
  stepT: { fontSize: 15, fontWeight: '800', color: lilac.head },
  stepD: { fontSize: 14, lineHeight: 20, color: lilac.text, marginTop: 2 },
  stepFoot: {
    fontSize: 14, lineHeight: 20, color: lilac.dim,
    borderTopWidth: 1, borderTopColor: lilac.hair2, paddingTop: 11, paddingBottom: 12,
  },

  // ── ③ 지원 현황 ──
  stateCard: {
    backgroundColor: lilac.card, borderWidth: 1, borderColor: lilac.hair,
    borderRadius: lilacRadius.card, padding: 14, ...lilacShadow,
  },
  strapDot: { width: 7, height: 7, borderRadius: 4 },
  strapTxt: { fontSize: 14, lineHeight: 18, fontWeight: '800' },
  stateT: { fontSize: 18, lineHeight: 24, fontWeight: '900', color: lilac.head },
  stateD: { fontSize: 14, lineHeight: 21, color: lilac.text, marginTop: 7 },
  stateMeta: { fontSize: 14, lineHeight: 20, color: lilac.dim, marginTop: 6 },
  onlineLine: {
    flexDirection: 'row', alignItems: 'center', gap: 8, marginTop: 12,
    backgroundColor: lilac.inset, borderWidth: 1, borderColor: lilac.hair,
    borderRadius: lilacRadius.inner, paddingVertical: 11, paddingHorizontal: 12,
  },
  onlineDot: { width: 7, height: 7, borderRadius: 4 },
  onlineTxt: { flex: 1, fontSize: 14, lineHeight: 20, color: lilac.text },
  reasonBox: {
    marginTop: 11, backgroundColor: lilac.inset, borderWidth: 1, borderColor: lilac.hair,
    borderRadius: lilacRadius.inner, padding: 12,
  },
  reasonK: { fontSize: 14, lineHeight: 18, color: lilac.dim, marginBottom: 3 },
  reasonV: { fontSize: 14, lineHeight: 21, color: lilac.head },
  confirmTxt: { fontSize: 14, lineHeight: 20, color: lilac.text },
  confirmYes: {
    flex: 1.4, backgroundColor: lilac.coralDeep, borderRadius: lilacRadius.btn,
    alignItems: 'center', paddingVertical: 12,
  },
  confirmYesTxt: { fontSize: 14, lineHeight: 20, fontWeight: '900', color: '#FFFFFF' },
  confirmNo: {
    flex: 1, backgroundColor: lilac.inset, borderWidth: 1, borderColor: lilac.hair,
    borderRadius: lilacRadius.btn, alignItems: 'center', paddingVertical: 12,
  },
  confirmNoTxt: { fontSize: 14, lineHeight: 20, fontWeight: '800', color: lilac.head },

  // ── CTA ──
  cta: {
    flexDirection: 'row', alignItems: 'center', gap: 10, marginTop: 13,
    backgroundColor: lilac.inset, borderWidth: 1, borderColor: lilac.hair,
    borderRadius: lilacRadius.btn, paddingVertical: 12, paddingHorizontal: 12,
  },
  ctaT: { fontSize: 14, lineHeight: 20, fontWeight: '800', color: lilac.head },
  ctaD: { fontSize: 14, lineHeight: 20, color: lilac.dim, marginTop: 1 },
  ctaGo: { fontSize: 17, color: lilac.accent },
  ctaPrimary: {
    flexDirection: 'row', alignItems: 'center', gap: 10, marginTop: 13,
    backgroundColor: lilac.head, borderRadius: lilacRadius.btn, paddingVertical: 13, paddingHorizontal: 14,
  },
  ctaPrimaryT: { flex: 1, fontSize: 15, lineHeight: 20, fontWeight: '900', color: '#FFFFFF' },
  ctaPrimaryGo: { fontSize: 17, color: '#FFFFFF' },

  // ── 지원서 폼 ──
  formCard: {
    backgroundColor: lilac.card, borderWidth: 1, borderColor: lilac.hair,
    borderRadius: lilacRadius.card, padding: 14, ...lilacShadow,
  },
  formT: { fontSize: 18, lineHeight: 24, fontWeight: '900', color: lilac.head },
  formD: { fontSize: 14, lineHeight: 20, color: lilac.dim, marginTop: 5 },
  fieldL: { fontSize: 15, lineHeight: 20, fontWeight: '800', color: lilac.head },
  fieldH: { fontSize: 14, lineHeight: 19, color: lilac.dim, marginTop: 2 },
  fieldNote: { fontSize: 14, lineHeight: 19, color: lilac.dim, marginTop: 6 },
  input: {
    backgroundColor: lilac.inset, borderWidth: 1, borderColor: lilac.hair,
    borderRadius: lilacRadius.inner, paddingVertical: 11, paddingHorizontal: 12,
    fontSize: 15, lineHeight: 20, color: lilac.head,
  },
  inputMulti: { minHeight: 78, textAlignVertical: 'top' },
  unit: { fontSize: 14, lineHeight: 20, color: lilac.dim },
  chip: {
    borderWidth: 1, borderColor: lilac.hair, backgroundColor: lilac.inset,
    borderRadius: lilacRadius.tag, paddingVertical: 8, paddingHorizontal: 11,
  },
  chipOn: { borderColor: lilac.accent, backgroundColor: '#F4F1FE' },
  chipFull: { opacity: 0.5 },
  chipTxt: { fontSize: 14, lineHeight: 18, color: lilac.text },
  chipTxtOn: { color: lilac.accent, fontWeight: '800' },
  notice: {
    marginTop: 16, backgroundColor: lilac.inset, borderWidth: 1, borderColor: lilac.hair,
    borderRadius: lilacRadius.inner, padding: 12,
  },
  noticeT: { fontSize: 14, lineHeight: 20, fontWeight: '800', color: lilac.head, marginBottom: 4 },
  noticeD: { fontSize: 14, lineHeight: 21, color: lilac.text },
  check: { flexDirection: 'row', alignItems: 'flex-start', gap: 10, marginTop: 12 },
  checkBox: {
    width: 22, height: 22, borderRadius: lilacRadius.tag, borderWidth: 1, borderColor: lilac.hair,
    backgroundColor: lilac.inset, alignItems: 'center', justifyContent: 'center', marginTop: 1,
  },
  checkBoxOn: { borderColor: lilac.accent, backgroundColor: lilac.accent },
  checkMark: { fontSize: 14, lineHeight: 18, fontWeight: '900', color: '#FFFFFF' },
  checkTxt: { flex: 1, fontSize: 14, lineHeight: 20, color: lilac.text },
  submit: {
    marginTop: 16, backgroundColor: lilac.head, borderRadius: lilacRadius.btn,
    alignItems: 'center', paddingVertical: 14,
  },
  submitBusy: { opacity: 0.72 },
  submitTxt: { fontSize: 15, lineHeight: 20, fontWeight: '900', color: '#FFFFFF' },
  formCancel: { marginTop: 9, alignItems: 'center', paddingVertical: 10 },
  formCancelTxt: { fontSize: 14, lineHeight: 20, fontWeight: '700', color: lilac.dim },

  // ── 콜로폰 ──
  colophon: { marginTop: 20, paddingTop: 12, borderTopWidth: 1, borderTopColor: lilac.hair, alignItems: 'center' },
  colophonTxt: { fontSize: 12, lineHeight: 16, letterSpacing: 1.8, color: lilac.dim }, // Oswald 1.33×
});
