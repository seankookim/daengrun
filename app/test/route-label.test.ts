import { bookingKmLabel, nameCarriesKm, routeLabel } from '../src/lib/route-label';

let pass = 0, fail = 0;
const eq = (label: string, got: unknown, want: unknown) => {
  if (got === want) { pass++; console.log('PASS ' + label); }
  else { fail++; console.log(`FAIL ${label}\n  got:  ${JSON.stringify(got)}\n  want: ${JSON.stringify(want)}`); }
};

// 🔴 THE REGRESSION THIS FILE EXISTS FOR. Production carries three 몽마르뜨 loops and two 서래섬
// loops whose ONLY distinguishing text is the trailing km (0100's header says so explicitly).
// The first version of this module stripped that token, collapsing five courses into two
// indistinguishable names. Nothing here may ever return a name with the token removed.
const MONT = ['몽마르뜨 언덕 루프', '몽마르뜨 언덕 루프 4.79km', '몽마르뜨 언덕 루프 5.4km'];
eq('identifying tokens survive — three distinct loops stay distinct',
   new Set(MONT.map((n) => routeLabel({ name: n, km: 5 }))).size, 3);
eq('a bare name still gets its distance appended',
   routeLabel({ name: '몽마르뜨 언덕 루프', km: 1.6 }), '몽마르뜨 언덕 루프 1.6km');
eq('a name that already carries one is left exactly alone',
   routeLabel({ name: '몽마르뜨 언덕 루프 4.79km', km: 5 }), '몽마르뜨 언덕 루프 4.79km');

eq('detects a trailing km', nameCarriesKm('서울숲 숲길 3km'), true);
eq('detects a decimal', nameCarriesKm('성수 서울숲 루프 6.46km'), true);
eq('no false positive on a plain name', nameCarriesKm('반포한강공원 루프'), false);
eq('a mid-name km is not a trailing one', nameCarriesKm('3km 코스 왕복'), false);
eq('null-safe', nameCarriesKm(null), false);

// the booking distance is LABELLED so it cannot be confused with the one inside the name
eq('booking label names itself', bookingKmLabel(5), '예약 5km');
eq('booking label is empty when unknown — no 0km invented', bookingKmLabel(null), '');

console.log(`\n${pass} pass / ${fail} fail`);
process.exit(fail === 0 ? 0 : 1);
