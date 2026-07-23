import { router, useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Pressable, ScrollView, Text, View } from 'react-native';
import { BottomNav } from '../../src/components/bottomnav';
import { Badge, Card, Monogram, Row, StatBlock, text } from '../../src/components/ui';
import { fetchRunnerInbox, OpenRequest } from '../../src/lib/api';
import { runnerStats } from '../../src/store';
import { colors } from '../../src/theme';

export default function RunnerHome() {
  const [available, setAvailable] = useState(true);
  const [inbox, setInbox] = useState<OpenRequest[]>([]);

  useFocusEffect(useCallback(() => {
    fetchRunnerInbox().then(setInbox).catch(() => {});
  }, []));

  return (
    <View style={{ flex: 1 }}>
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ padding: 22, paddingTop: 64 }}>
        <Row style={{ justifyContent: 'space-between' }}>
          <View>
            <Text style={text.dim}>러너 모드</Text>
            <Text style={[text.h1, { marginTop: 2 }]}>김민준 님</Text>
          </View>
          <Pressable
            onPress={() => setAvailable((v) => !v)}
            style={{
              width: 56, height: 32, borderRadius: 99, padding: 3,
              backgroundColor: available ? colors.voltDeep : '#d8d4c4',
              alignItems: available ? 'flex-end' : 'flex-start',
            }}
          >
            <View style={{ width: 26, height: 26, borderRadius: 13, backgroundColor: '#fff' }} />
          </Pressable>
        </Row>

        <Card dark style={{ marginTop: 18 }}>
          <Row style={{ justifyContent: 'space-around' }}>
            <StatBlock value={runnerStats.weekEarnings.toLocaleString()} label="이번 주 수익(원)" />
            <StatBlock value={String(runnerStats.weekRuns)} label="완료 러닝" />
            <StatBlock value={String(runnerStats.weekKm)} label="km" />
          </Row>
        </Card>

        {/* drop progress strip */}
        <Pressable onPress={() => router.push('/runner/rewards')} style={{
          flexDirection: 'row', alignItems: 'center', gap: 10, marginTop: 12,
          backgroundColor: '#fff', borderRadius: 14, padding: 12, borderWidth: 1.3, borderColor: '#dde8c4',
        }}>
          <Text style={{ fontSize: 13 }}>▣</Text>
          <Text style={{ flex: 1, fontSize: 12, fontWeight: '700', color: '#132117' }}>
            다음 보급 드랍까지 <Text style={{ color: '#5a7a3c', fontWeight: '900' }}>5회</Text> · 픽 드랍까지 <Text style={{ color: '#5a7a3c', fontWeight: '900' }}>5회</Text>
          </Text>
          <Text style={{ fontSize: 13, color: colors.dim }}>›</Text>
        </Pressable>

        <Row style={{ justifyContent: 'flex-end', gap: 16, marginTop: 10 }}>
          <Pressable onPress={() => router.push('/community')}>
            <Text style={[text.dim, { fontWeight: '700' }]}>커뮤니티 ›</Text>
          </Pressable>
          <Pressable onPress={() => router.push('/safety')}>
            <Text style={[text.dim, { fontWeight: '700' }]}>안심 센터 ›</Text>
          </Pressable>
          <Pressable onPress={() => router.push('/cards')}>
            <Text style={[text.dim, { fontWeight: '700' }]}>마이 카드 ›</Text>
          </Pressable>
        </Row>

        {/* 실시간 요청 요약 (탭하면 요청 탭) */}
        {inbox.length > 0 && (
          <Pressable
            onPress={() => router.push('/runner/requests')}
            style={{
              flexDirection: 'row', alignItems: 'center', gap: 10, marginTop: 14,
              backgroundColor: '#132117', borderRadius: 16, padding: 14,
            }}
          >
            <View style={{ backgroundColor: colors.volt, borderRadius: 99, paddingVertical: 3, paddingHorizontal: 8 }}>
              <Text style={{ fontSize: 9, fontWeight: '900', color: '#132117' }}>● LIVE</Text>
            </View>
            <Text style={{ flex: 1, fontSize: 13, fontWeight: '800', color: '#fff' }} numberOfLines={1}>
              새 요청 {inbox.length}건 — {inbox[0].dogName} {inbox[0].km}km{inbox[0].directed ? ' (지명!)' : ''}
            </Text>
            <Text style={{ fontSize: 13, color: colors.volt, fontWeight: '900' }}>응답 ›</Text>
          </Pressable>
        )}

        {inbox.length === 0 && (
          <View style={{ marginTop: 14, backgroundColor: '#fff', borderRadius: 16, padding: 20, alignItems: 'center', borderWidth: 1, borderColor: '#eceadf' }}>
            <Text style={{ fontSize: 13, color: colors.dim, textAlign: 'center', lineHeight: 20 }}>
              지금은 새 요청이 없어요{'\n'}온라인 상태면 요청이 오는 대로 표시돼요
            </Text>
          </View>
        )}

      </ScrollView>
      <BottomNav />
    </View>
  );
}
