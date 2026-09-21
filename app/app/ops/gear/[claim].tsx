import { useLocalSearchParams } from 'expo-router';
import { useCallback, useEffect, useState } from 'react';
import {
  Alert, KeyboardAvoidingView, Platform, Pressable, ScrollView, StyleSheet, Text, TextInput, View,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { StatusBarCover } from '../../../src/components/status-bar-cover';
import { Row } from '../../../src/components/ui';
import { fetchOpsGearClaimsPending, OpsGearClaim, opsMarkGearShipped } from '../../../src/lib/api';
import { haptic } from '../../../src/lib/haptics';
import { kstCal, kstMonthDay } from '../../../src/lib/kst';
import { goBackOrHome } from '../../../src/lib/nav';
import { colors, paper } from '../../../src/theme';

// 발송 처리 — one gear claim's delivery snapshot and the tracking number that closes it. 0195 §C/§D.
//
// ⚠ **THE DELIVERY FIELDS ARE READ-ONLY HERE, AND THAT IS THE SERVER'S SHAPE RATHER THAN A UI
//   CHOICE.** 0195 §B froze the five fields onto `gear_claims.delivery` as a SNAPSHOT when the
//   runner claimed, and there is no RPC that edits them — deliberately, because the box is being
//   sent to the address the runner confirmed. Rendering them as inputs would draw a door that does
//   not exist, which is this house's dead-button law in its exact original form.
//
// ⚠ **THERE IS NO `ops_gear_claim(id)` AND THIS SCREEN DOES NOT PRETEND OTHERWISE.** 0195 ships
//   one ops read — the pending LIST — so this screen reads the list and picks its row out of it.
//   That is honest and it has a consequence worth stating: a claim that is no longer `claimed`
//   (someone else posted it) is simply NOT IN THE LIST, and the screen says 「목록에 없어요」 with a
//   reason rather than an empty form. Adding a per-id read would be a second ops surface for a
//   fact the list already carries, which is the trade 0192 §0 ① argues against.
//
// ⚠ 「발송」 means POSTED, not DELIVERED (0195 §D's own sentence). Nothing here says 도착.

type Phase = 'loading' | 'error' | 'missing' | 'ready' | 'done';

export default function OpsGearClaimScreen() {
  const insets = useSafeAreaInsets();
  const params = useLocalSearchParams<{ claim?: string }>();
  const claimId = typeof params.claim === 'string' ? params.claim : '';

  const [phase, setPhase] = useState<Phase>('loading');
  const [claim, setClaim] = useState<OpsGearClaim | null>(null);
  const [carrier, setCarrier] = useState('');
  const [tracking, setTracking] = useState('');
  const [saving, setSaving] = useState(false);
  const [loadErr, setLoadErr] = useState<string | null>(null);
  const [formErr, setFormErr] = useState<string | null>(null);
  const [shipped, setShipped] = useState<{ carrier: string | null; tracking: string | null } | null>(null);

  const load = useCallback(() => {
    if (claimId === '') { setLoadErr('해당 수령 신청을 찾을 수 없어요'); setPhase('error'); return; }
    setPhase('loading');
    setLoadErr(null);
    fetchOpsGearClaimsPending()
      .then((rows) => {
        const found = rows.find((r) => r.claimId === claimId) ?? null;
        setClaim(found);
        setPhase(found === null ? 'missing' : 'ready');
      })
      .catch((e) => {
        console.warn('[ops/gear] load:', (e as Error)?.message ?? e);
        setLoadErr((e as Error)?.message || '수령 신청을 불러오지 못했어요');
        setPhase('error');
      });
  }, [claimId]);
  useEffect(() => { load(); }, [load]);

  const submit = useCallback(() => {
    if (saving) return;
    // The server refuses an empty carrier or tracking BY NAME (`bad_carrier` / `bad_tracking`);
    // these two lines are the same rule restated so the operator learns it from the button.
    const c = carrier.trim();
    const t = tracking.trim();
    if (c === '') { setFormErr('택배사를 입력해주세요'); haptic('light'); return; }
    if (t === '') { setFormErr('송장번호를 입력해주세요'); haptic('light'); return; }

    Alert.alert(
      '발송 처리할까요?',
      `${c} · ${t}\n송장번호는 나중에 덮어쓸 수 없어요 — 실제로 부친 번호가 맞는지 확인해주세요`,
      [
        { text: '취소', style: 'cancel' },
        {
          text: '발송 처리',
          onPress: () => {
            setFormErr(null);
            setSaving(true);
            opsMarkGearShipped({ claimId, carrier: c, tracking: t })
              .then((res) => {
                // Draw what the SERVER kept, not what we sent — the same law as 0194's save.
                setShipped({ carrier: res.carrier, tracking: res.tracking });
                setPhase('done');
              })
              .catch((e) => setFormErr((e as Error)?.message || '발송 처리를 하지 못했어요'))
              .finally(() => setSaving(false));
          },
        },
      ],
    );
  }, [carrier, tracking, claimId, saving]);

  return (
    <>
      <KeyboardAvoidingView style={{ flex: 1 }} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
        <ScrollView
          style={{ flex: 1, backgroundColor: colors.cream }}
          contentContainerStyle={{ paddingHorizontal: 11, paddingTop: insets.top, paddingBottom: insets.bottom + 40 }}
          keyboardShouldPersistTaps="handled"
        >
          <Row style={{ justifyContent: 'space-between' }}>
            <Pressable onPress={goBackOrHome} style={s.backBtn} accessibilityRole="button" accessibilityLabel="뒤로">
              <Text style={{ fontSize: 20.5 }}>‹</Text>
            </Pressable>
            <Text style={{ fontSize: 23, fontWeight: '900', color: paper.ink }}>발송 처리</Text>
            <View style={{ width: 40 }} />
          </Row>

          {phase === 'loading' && <Text style={s.loading}>수령 신청을 불러오는 중이에요…</Text>}

          {phase === 'error' && (
            <View style={s.failStrip}>
              <Text style={s.failText}>{loadErr}</Text>
              <Pressable onPress={load} accessibilityRole="button" style={s.retryBtn}>
                <Text style={s.retryLabel}>다시 시도</Text>
              </Pressable>
            </View>
          )}

          {phase === 'missing' && (
            <View style={[s.card, { marginTop: 14, paddingVertical: 18 }]}>
              <Text style={s.emptyText}>배송 대기 목록에 없어요</Text>
              <Text style={s.emptySub}>
                이미 발송 처리됐거나 수령 신청이 취소된 항목이에요 · 목록으로 돌아가면 최신 상태가 보여요
              </Text>
              <Pressable
                onPress={goBackOrHome}
                accessibilityRole="button"
                style={({ pressed }) => [s.secondary, pressed && s.secondaryPressed]}
              >
                <Text style={s.secondaryLabel}>목록으로</Text>
              </Pressable>
            </View>
          )}

          {phase === 'done' && shipped !== null && (
            <>
              <View style={s.doneStrip}>
                <Text style={s.doneText}>발송 처리했어요</Text>
                <Text style={s.doneSub}>
                  {shipped.carrier ?? '택배사 미상'} · {shipped.tracking ?? '송장번호 미상'}
                </Text>
                <Text style={s.doneSub}>「발송」은 부쳤다는 뜻이고 도착했다는 뜻은 아니에요</Text>
              </View>
              <Pressable
                onPress={goBackOrHome}
                accessibilityRole="button"
                style={({ pressed }) => [s.primary, pressed && s.primaryPressed]}
              >
                <Text style={s.primaryLabel}>목록으로</Text>
              </Pressable>
            </>
          )}

          {phase === 'ready' && claim !== null && (
            <>
              <View style={[s.card, { marginTop: 14, paddingVertical: 15 }]}>
                <Text style={s.kicker}>보낼 것</Text>
                <Text style={s.itemName}>{claim.item}</Text>
                <Text style={s.itemHint}>
                  {claim.milestone}회 달성
                  {claim.claimedAt ? ` · ${kstMonthDay(kstCal(Date.parse(claim.claimedAt)))} 신청` : ''}
                </Text>
              </View>

              {/* ⚠ READ-ONLY. There is no RPC that edits these — 0195 §B froze them as a snapshot
                  at claim time, and a text input here would be a door that does not exist. */}
              <View style={[s.card, { marginTop: 10, paddingVertical: 15 }]}>
                <Text style={s.kicker}>배송지</Text>
                <Text style={s.addrLine}>{claim.recipient ?? '받는사람 미상'}</Text>
                <Text style={s.addrLine}>{claim.phone ?? '전화번호 미상'}</Text>
                <Text style={s.addrLine}>
                  {claim.address1 ?? '주소 미상'}
                  {claim.address2 != null && claim.address2 !== '' ? ` ${claim.address2}` : ''}
                </Text>
                <Text style={s.addrLine}>{claim.postal ?? '우편번호 미상'}</Text>
                <Text style={s.addrNote}>러너가 신청할 때 확정한 주소예요 · 여기서는 고칠 수 없어요</Text>
              </View>

              <Text style={s.fieldLabel}>택배사</Text>
              <TextInput
                value={carrier}
                onChangeText={(v) => { setCarrier(v); setFormErr(null); }}
                editable={!saving}
                placeholder="CJ대한통운 · 롯데택배 · 우체국 …"
                placeholderTextColor={paper.dim}
                autoCorrect={false}
                style={s.input}
                accessibilityLabel="택배사"
              />

              <Text style={s.fieldLabel}>송장번호</Text>
              <TextInput
                value={tracking}
                onChangeText={(v) => { setTracking(v); setFormErr(null); }}
                editable={!saving}
                placeholder="부친 뒤 받은 번호 그대로"
                placeholderTextColor={paper.dim}
                autoCapitalize="characters"
                autoCorrect={false}
                style={s.input}
                accessibilityLabel="송장번호"
              />
              <Text style={s.warnNote}>
                한 번 적으면 덮어쓸 수 없어요 — 두 번째 기록은 서버가 거절해요
              </Text>

              {formErr !== null && (
                <View style={s.failStrip}>
                  <Text style={s.failText}>{formErr}</Text>
                </View>
              )}

              <Pressable
                onPress={submit}
                disabled={saving}
                accessibilityRole="button"
                accessibilityState={{ disabled: saving, busy: saving }}
                style={({ pressed }) => [s.primary, saving ? s.flatDisabled : (pressed && s.primaryPressed)]}
              >
                <Text style={[s.primaryLabel, saving && s.flatDisabledLabel]}>
                  {saving ? '처리 중…' : '발송 처리'}
                </Text>
              </Pressable>
            </>
          )}
        </ScrollView>
      </KeyboardAvoidingView>
      <StatusBarCover color={colors.cream} />
    </>
  );
}

// 15pt floor (DESIGN.md:145) — no Korean below 15 on this screen, and no latin kicker to exempt.
const s = StyleSheet.create({
  backBtn: { width: 40, height: 40, borderRadius: 20, backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: colors.line },
  card: { backgroundColor: '#fff', borderRadius: 16, paddingHorizontal: 15, borderWidth: 1, borderColor: colors.line },
  kicker: { fontSize: 15, fontWeight: '700', color: paper.dim },
  itemName: { fontSize: 19, fontWeight: '800', color: paper.ink, marginTop: 4 },
  itemHint: { fontSize: 15, lineHeight: 21, color: paper.dim, marginTop: 3 },
  addrLine: { fontSize: 17, lineHeight: 24, fontWeight: '700', color: paper.ink, marginTop: 3 },
  addrNote: { fontSize: 15, lineHeight: 21, color: paper.dim, marginTop: 8 },
  loading: { fontSize: 15.5, lineHeight: 22, color: paper.dim, paddingVertical: 16 },
  fieldLabel: { fontSize: 15, fontWeight: '700', color: paper.ink, marginTop: 18, marginBottom: 6 },
  input: { fontSize: 17, color: paper.ink, backgroundColor: '#fff', borderRadius: 12, borderWidth: 1, borderColor: colors.line, paddingHorizontal: 14, minHeight: 52 },
  warnNote: { fontSize: 15, lineHeight: 21, color: paper.dim, marginTop: 8 },
  primary: {
    marginTop: 20, minHeight: 56, borderRadius: 0, backgroundColor: paper.ink,
    borderBottomWidth: 4, borderBottomColor: paper.inkPressed,
    alignItems: 'center', justifyContent: 'center',
  },
  primaryPressed: { transform: [{ translateY: 3 }], borderBottomWidth: 1 },
  primaryLabel: { fontSize: 17, fontWeight: '800', color: '#FFFFFF' },
  flatDisabled: { borderBottomWidth: 1, backgroundColor: paper.disabledFill },
  flatDisabledLabel: { color: paper.faint },
  secondary: {
    marginTop: 14, minHeight: 48, borderRadius: 0, backgroundColor: colors.cream,
    borderWidth: 1, borderColor: paper.ink, alignItems: 'center', justifyContent: 'center',
  },
  secondaryPressed: { backgroundColor: paper.disabledFill, transform: [{ scale: 0.97 }] },
  secondaryLabel: { fontSize: 16, fontWeight: '800', color: paper.ink },
  emptyText: { fontSize: 17, fontWeight: '800', color: paper.ink },
  emptySub: { fontSize: 15, lineHeight: 21, color: paper.dim, marginTop: 5 },
  failStrip: { backgroundColor: paper.criticalWash, borderRadius: 16, padding: 13, marginTop: 12 },
  failText: { fontSize: 15, lineHeight: 21, fontWeight: '800', color: paper.critical },
  retryBtn: { alignSelf: 'flex-start', marginTop: 8, minHeight: 44, justifyContent: 'center' },
  retryLabel: { fontSize: 16, fontWeight: '800', color: paper.critical, textDecorationLine: 'underline' },
  doneStrip: { backgroundColor: '#EDF4EE', borderRadius: 16, padding: 15, marginTop: 14 },
  doneText: { fontSize: 17, fontWeight: '900', color: paper.ink },
  doneSub: { fontSize: 15, lineHeight: 21, color: paper.dim, marginTop: 5 },
});
