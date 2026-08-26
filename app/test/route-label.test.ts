import { routeLabel, routeNameOnly } from '../src/lib/route-label';

let pass = 0, fail = 0;
const eq = (label: string, got: unknown, want: unknown) => {
  if (got === want) { pass++; console.log('PASS ' + label); }
  else { fail++; console.log(`FAIL ${label}\n  got:  ${JSON.stringify(got)}\n  want: ${JSON.stringify(want)}`); }
};

// production 이름들 (실측 — 지어낸 예가 아니다)
eq('strips a trailing km', routeNameOnly('서울숲 숲길 3km'), '서울숲 숲길');
eq('strips a decimal km', routeNameOnly('송파 새내근린공원·온조마루근린공원 루프 1.52km'), '송파 새내근린공원·온조마루근린공원 루프');
eq('leaves a name with no km alone', routeNameOnly('반포한강공원 루프'), '반포한강공원 루프');
eq('handles no space before km', routeNameOnly('성수 서울숲 루프 6.46km'), '성수 서울숲 루프');
eq('trims a separator left behind', routeNameOnly('잠실 석촌호수 · 3km'), '잠실 석촌호수');
// ⚠ km INSIDE the name is part of the name — stripping it would damage the name
eq('does not touch a mid-name km', routeNameOnly('3km 코스 왕복'), '3km 코스 왕복');
// ⚠ a name that is ONLY a distance must not become empty
eq('never returns empty', routeNameOnly('5km'), '5km');
eq('null-safe', routeNameOnly(null), '');

eq('label appends when absent', routeLabel({ name: '반포한강공원 루프', km: 4 }), '반포한강공원 루프 4km');
eq('label leaves a baked km alone', routeLabel({ name: '서울숲 숲길 3km', km: 5 }), '서울숲 숲길 3km');

console.log(`\n${pass} pass / ${fail} fail`);
process.exit(fail === 0 ? 0 : 1);
