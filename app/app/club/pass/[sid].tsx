import { useFocusEffect, useLocalSearchParams } from 'expo-router';
import { useCallback, useState } from 'react';
import { Alert, Pressable, ScrollView, Text, View, StyleSheet } from 'react-native';
import { Row } from '../../../src/components/ui';
import { checkinClubSession, ClubSessionDetail, fetchClubSession } from '../../../src/lib/api';
import { ClubCta, LoadGate } from '../../../src/components/club-ui';
import { useDisplayFont } from '../../../src/lib/displayFont';
import { useNumFont } from '../../../src/lib/fonts';
import { haptic } from '../../../src/lib/haptics';
import { kstCal, kstClock, kstDateLabel } from '../../../src/lib/kst';
import { goBackOrHome } from '../../../src/lib/nav';
import { colors, layout, paper } from '../../../src/theme';

// 입장권 — the pass you hold up to the host at the meetup point. Night stub ticket (D1xD2,
// Sean-ratified): ADMIT language + bib count + barcode. The check-in button lives ON the ticket,
// because showing it and stamping it are one motion. The check-in window (start -2h..+6h) is
// enforced by the server (session_checkin); this screen only says when it opens.
//
// [repaint 2026-08-27] Brought onto the laws ruled this week. Four things moved:
//  1. CHROME GOES PAPER, THE ARTIFACT STAYS DARK (DESIGN.md §2 paper-migration grammar). The
//     stage, the back door and the ticket's perforation notches are white; the ticket itself is
//     still the night world, which §2's table keeps deliberately as a ceremony object. The
//     notches read as cut-outs only if they are the colour of whatever is BEHIND the ticket, so
//     they follow the stage.
//  2. BABY WORK (§7a-bis). One display headline (the club), one structured row set
//     (DATE/MEET/TEAM), one state line. Three lines of chrome were deleted rather than shrunk —
//     see the notes at each site. Dim is now the exception: the state line is ink (white here),
//     because it is the only thing on this screen the holder must actually read to act.
//  3. PRESS GRAMMAR (§3b). The hand-rolled violet check-in button is retired for ClubCta: violet
//     was ruled club IDENTITY and not a press surface, and the hand-rolled control carried a neon
//     glow + an opacity-dim busy state — a shadow cannot have a press state, and an alpha trick
//     is not a button state. ClubCta brings the 4px lip / translateY(3) key press, the 17/800
//     label, the busy label swap and the a11y disabled/busy state.
//  4. FLOOR (§3). Korean detail text at 14 is gone; the display face is spent ONCE (the club
//     name) and the bib count joins the Oswald wave with an explicit lineHeight (BUG A).

export default function ClubPass() {
  const df = useDisplayFont();
  const nf = useNumFont();
  const { sid, clubName } = useLocalSearchParams<{ sid: string; clubName?: string }>();
  const [sess, setSess] = useState<ClubSessionDetail | null>(null);
  const [busy, setBusy] = useState(false);

  // [honesty 2026-08-11] 입장권 딥링크 실패가 백 없는 영원한 '불러오는 중...'이던 것 — LoadGate.
  const [sessErr, setSessErr] = useState(false);
  const load = useCallback(() => {
    if (!sid) return;
    setSessErr(false);
    fetchClubSession(sid).then(setSess).catch(() => setSessErr(true));
  }, [sid]);
  useFocusEffect(useCallback(() => { load(); }, [load]));

  if (!sess) {
    return (
      <LoadGate
        mode={sessErr ? 'error' : 'loading'}
        errorLabel="입장권을 불러오지 못했어요"
        onRetry={load}
        onBack={goBackOrHome}
      />
    );
  }

  const me = sess.people.find((p) => p.isMe) ?? null;
  // [0052 §2] `people` is only filled for parties to the session; the roster COUNT that is always
  // present is `peopleCount` (the idiom club/session/[sid].tsx:260 already uses). Reading the
  // array length instead printed 0 팀 to a non-participant — a real capacity beside a number the
  // server never said, which is the fabricated-datum shape, not a rounding detail.
  const teams = sess.peopleCount ?? sess.people.length;
  const d = new Date(sess.scheduledAt);
  const checked = sess.myAttendance === 'checked_in';
  const startMs = d.getTime();
  const inWindow = Date.now() >= startMs - 2 * 3600_000 && Date.now() <= startMs + 6 * 3600_000;
  // Pay for the KST arithmetic once — both DATE lines then cannot disagree with each other.
  const cal = kstCal(startMs);
  // [honesty 2026-08-27] The club name is a ROUTE PARAM the whole way down — the session screen
  // only has a param itself, and it hands this one `clubName: clubName ?? ''`, so on a deep link
  // to /club/pass/<sid> it arrives EMPTY, not undefined. The old fallback printed 하이클럽, which
  // is the PRODUCT's name and not any club's: a brand word standing in a club-name position on
  // the artifact a host inspects. ClubSessionDetail carries clubId but no name, and the client
  // has no fetch-club-by-id (club_overview takes a district, club_search takes a query), so the
  // honest move is to omit the headline. Binding it for real is a server change.
  const club = clubName?.trim() || null;

  const doCheckin = async () => {
    setBusy(true);
    try {
      await checkinClubSession(sess.id);
      haptic('success');
      load();
    } catch (e) {
      Alert.alert('체크인', (e as Error).message.includes('checkin_window') ? '체크인은 시작 2시간 전부터 가능해요' : (e as Error).message);
    } finally { setBusy(false); }
  };

  return (
    <View style={s.stage}>
      <ScrollView contentContainerStyle={{ paddingHorizontal: layout.gutter, paddingTop: 58, paddingBottom: 40, flexGrow: 1, justifyContent: 'center' }}>
        <Pressable onPress={goBackOrHome} style={s.backBtn} accessibilityRole="button" accessibilityLabel="뒤로"><Text style={{ fontSize: 20.5, color: paper.ink }}>‹</Text></Pressable>

        <View style={s.ticket}>
          <View style={s.neonEdge} />

          {/* 상단 — ADMIT + 빕.
              [baby work] The kicker used to carry the party size too, which the TEAM row two
              blocks down already spells out by name — the same fact twice, once in latin
              micro-caps. Kicker keeps the one word that is not repeated anywhere.
              [honesty] The dim host line under the club name asserted a verification tier that
              no field on ClubSessionDetail backs (the type carries hostName and nothing about
              vetting), so it was an unearned badge; and the holder does not need the host's name
              to hold up a ticket TO the host. Deleted whole rather than trimmed. */}
          <View style={s.top}>
            <View style={{ flex: 1 }}>
              <Text style={s.kicker}>ADMIT</Text>
              {club && (
                /* the screen's ONE display face (§3) — lineHeight 31 = 1.24x (BUG A) */
                <Text style={[{ fontSize: 25, lineHeight: 31, fontWeight: '900', color: '#fff', marginTop: 5 }, df]} numberOfLines={1}>
                  {club}
                </Text>
              )}
            </View>
            <View style={s.bibBox}>
              <Text style={{ fontSize: 8.5, letterSpacing: 2, fontWeight: '700', color: colors.nightDim }}>TEAMS</Text>
              {/* Oswald + explicit lineHeight 27 = ceil(21x1.24) — BigNumRow's value, same reason */}
              <Text style={[{ fontSize: 21, lineHeight: 27, fontWeight: '600', color: colors.neon, fontVariant: ['tabular-nums'] }, nf]}>
                {teams}<Text style={{ fontSize: 15, color: colors.nightDim }}>/{sess.capacity}</Text>
              </Text>
            </View>
          </View>

          {/* 절취선 + 다이아 노치 */}
          <View style={s.perf}>
            <View style={[s.notch, { left: -7 }]} />
            <View style={s.dash} />
            <View style={[s.notch, { right: -7 }]} />
          </View>

          {/* 메타 그리드 (D2) */}
          <Row style={s.grid}>
            <View style={[s.cell, { borderRightWidth: 1 }]}>
              <Text style={s.cellK}>DATE</Text>
              {/* [KST 2026-08-27] This cell read the DEVICE clock — getDay/getHours/getMinutes are
                  local-timezone, so a phone outside Asia/Seoul printed the wrong weekday AND the
                  wrong time on the one artifact a holder physically shows a host. Now fixed to +9
                  via kst.ts. (startMs/inWindow above are epoch math and were already correct.)
                  TWO lines, not one. The cell is half the grid: ~127pt of content box on a 375pt
                  screen (375 - 2*15 gutter - 2*16 grid margin - borders, halved, - 2*11 padding).
                  ESTIMATED from generic glyph advances — there is no fontFamily here, so this
                  renders in the platform system font and the figure is not a measured layout —
                  「8월 26일 (화) 19:00」 comes out around 130pt on one line, i.e. NOT safely inside
                  the box. The estimate does not have to be right for the decision to be: one line
                  is marginal at the 15pt floor, and the only ways to buy width are dropping the
                  date or going under the floor. A ticket whose DATE cell omits the date is worse
                  than one that is a line taller, so it splits. Split, the widest realistic value
                  「12월 28일 (수)」 is ~96pt and clears with room to spare; it is pinned in
                  test/kst.test.cjs so the string this was sized against cannot silently grow. */}
              <Text style={s.cellV}>{kstDateLabel(cal)}</Text>
              <Text style={s.cellVSub}>{kstClock(cal)}</Text>
            </View>
            <View style={s.cell}>
              <Text style={s.cellK}>MEET</Text>
              <Text style={s.cellV} numberOfLines={1}>{sess.meetupPoint}</Text>
            </View>
          </Row>

          {/* 홀더 — 내 팀.
              §3 spends Black Han Sans ONCE per screen and the club name above is the headline, so
              this row is plain 800. It is a data value, not a title — the weight law reserves 900
              for numbers and screen titles.
              The non-participant case is a data dash here: the sentence that says why lives in
              the state slot below, and printing it in both places was the same words twice. */}
          <View style={{ paddingHorizontal: 16, paddingTop: 13 }}>
            <Text style={s.cellK}>TEAM</Text>
            <Text style={{ fontSize: 22, lineHeight: 28, fontWeight: '800', color: '#fff', marginTop: 3 }} numberOfLines={1}>
              {me ? `${me.name}${me.dogName ? ` + ${me.dogName}` : ''}` : '—'}
            </Text>
          </View>

          {/* 상태 — 도장 / 액션 / 한 줄.
              §7a-bis: exactly one of these three renders, and each is one thing. The stamp's
              second line was reassurance under a word that already says it; the pre-window line
              lost its latin reservation prefix, which restated the fact that you are holding a pass.
              What survives is ink, not dim — this is the line the holder must read to act, and
              dim is reserved for the consent class. */}
          <View style={{ paddingHorizontal: 16, paddingTop: 12, paddingBottom: 4, minHeight: 74, justifyContent: 'center' }}>
            {checked ? (
              <View style={s.checkedStamp}>
                <Text style={{ fontSize: 17, fontWeight: '900', letterSpacing: 3, color: colors.volt }}>CHECKED</Text>
              </View>
            ) : me ? (
              inWindow ? (
                // ClubCta = §3b's filled-key press (4px lip at rest, translateY(3) + 1px pressed,
                // no scale, no shadow) + busy label swap. marginTop is zeroed because the slot
                // already owns the space above it.
                <ClubCta label="집결지 도착 체크인" onPress={doCheckin} busy={busy} style={{ marginTop: 0 }} />
              ) : (
                <Text style={s.stateLine}>체크인은 시작 2시간 전부터 열려요</Text>
              )
            ) : (
              <Text style={s.stateLine}>이 세션의 참가자가 아니에요</Text>
            )}
          </View>

          {/* 바코드 */}
          <Row style={s.bars}>
            {Array.from({ length: 32 }).map((_, i) => (
              <View key={i} style={{ width: i % 3 === 0 ? 3.5 : 2, height: i % 4 === 0 ? '58%' : '100%', backgroundColor: colors.nightDim }} />
            ))}
          </Row>
          <Text style={s.serial}>DOGS HIGH · {sess.id.slice(0, 8).toUpperCase()}</Text>
        </View>
        {/* [baby work] A dim instruction line used to sit here, telling the holder to show the
            ticket to the host. It is the ADMIT ticket's whole form, and the row that opens this
            screen (club/session/[sid].tsx) already says it in the tap itself — so it was a third
            statement of a fact stated twice. Deleted, not shrunk. */}
      </ScrollView>
    </View>
  );
}

const s = StyleSheet.create({
  // §2 paper-migration grammar: the chrome around a dark artifact goes paper. The stage is the
  // chrome; the ticket below is the artifact and keeps the night world.
  stage: { flex: 1, backgroundColor: paper.canvas },
  // The back door is the app's standard square: 40x40, canvas face, 1px coral, radius 0
  // (runner/meetup circleBtn). It sits on the white stage, so it is a paper control.
  backBtn: { position: 'absolute', top: 56, left: layout.gutter, width: 40, height: 40, borderRadius: 0, backgroundColor: paper.canvas, borderWidth: 1, borderColor: paper.line, alignItems: 'center', justifyContent: 'center', zIndex: 2 },
  // §3b: radius 0 everywhere including the club card — the club's standing exception is its side
  // margins, never its corners.
  ticket: { backgroundColor: colors.nightCard, borderRadius: 0, borderWidth: 1, borderColor: colors.nightEdge, overflow: 'hidden', paddingBottom: 14 },
  neonEdge: { position: 'absolute', left: 0, top: 0, bottom: 0, width: 3, backgroundColor: colors.neon, zIndex: 2 },
  top: { flexDirection: 'row', gap: 12, padding: 16, paddingLeft: 19, alignItems: 'flex-start' },
  kicker: { fontSize: 9.5, fontWeight: '700', letterSpacing: 3, color: colors.neon },
  bibBox: { borderWidth: 1, borderColor: colors.nightEdge, borderRadius: 0, paddingVertical: 6, paddingHorizontal: 12, alignItems: 'center', backgroundColor: '#1B1536' },
  perf: { flexDirection: 'row', alignItems: 'center', height: 14, marginVertical: 2 },
  dash: { flex: 1, borderTopWidth: 1, borderStyle: 'dashed', borderColor: '#3A3168', marginHorizontal: 10 },
  notch: { position: 'absolute', width: 14, height: 14, backgroundColor: paper.canvas, transform: [{ rotate: '45deg' }] },
  grid: { marginHorizontal: 16, borderWidth: 1, borderColor: colors.nightEdge, marginTop: 8, alignItems: 'stretch' },
  cell: { flex: 1, paddingVertical: 9, paddingHorizontal: 11, borderColor: colors.nightEdge },
  cellK: { fontSize: 8.5, letterSpacing: 2, fontWeight: '700', color: colors.nightDim },
  cellV: { fontSize: 15, fontWeight: '800', color: '#fff', marginTop: 3 },
  cellVSub: { fontSize: 15, fontWeight: '800', color: '#fff', marginTop: 1, fontVariant: ['tabular-nums'] },
  // §3 floor 15 + §7a-bis ink-by-default: white on nightCard measures 18.5:1. lineHeight 21 = 1.31x.
  stateLine: { fontSize: 16, lineHeight: 21, fontWeight: '700', color: '#fff', textAlign: 'center' },
  checkedStamp: { alignSelf: 'center', borderWidth: 2.5, borderColor: colors.volt, borderRadius: 0, paddingVertical: 8, paddingHorizontal: 18, transform: [{ rotate: '-7deg' }], alignItems: 'center', backgroundColor: 'rgba(198,245,66,.06)' },
  bars: { gap: 2, alignItems: 'flex-end', height: 26, marginTop: 10, marginHorizontal: 16, opacity: 0.75 },
  serial: { fontSize: 8.5, letterSpacing: 2.5, fontWeight: '700', color: colors.nightDim, marginTop: 6, marginLeft: 16 },
});
