// green-filter.mjs — ONE definition of "is this a usable route destination?".
//
// WHY THIS FILE EXISTS. The rule lived in coverage-gaps.mjs and screened the FIRST
// destination only. infill-gaps.mjs's secondGreen() picked the second destination
// from an unfiltered list, so the same rejected names (실로암, 초화원(임시운영))
// walked straight back in through the B slot on the very next run after being
// filtered out of the A slot.
//
// That is this project's most-repeated finding, now on its fourth instance:
// FIXING ONE COPY ONLY MOVES THE FAILURE. Both callers import this. If the rule
// changes, it changes here, once.

// Categories that can be a destination at all. A street or a crossing never is.
export const GREEN_CATEGORIES = ['stream', 'river', 'lake', 'park', 'forest'];

// Not destinations, whatever their category says:
//   배수지          fenced water-treatment reservoirs, mis-tagged as lakes
//   실로암/기도원    religious-institution grounds, not a public dog route
//   어린이공원      pocket playgrounds — and its ENGLISH form, which slipped past
//                   a Korean-only pattern ("Dokseodang Children's Park")
//   테니스장/체육관  sports facilities, not open green
//   물이 고여있는    a features.json name that is a SENTENCE
//   임시운영/철거    temporary or demolished installations
// 어린이\s*공원 — NOT 어린이공원. "국회단지 어린이 공원" has a SPACE and walked
// straight past the tight pattern. Same for the English form.
// 체육시설/운동시설 as well as 체육관 — "녹천교 체육시설" got through on the gap.
// 인공/폭포/내  — "아이파크 내 인공 폭포" is a water feature inside a private
//                 apartment estate, not a public green.
const SKIP = /주차|공장|터미널|역$|배수지|어린이\s*공원|놀이터|실로암|기도원|물이\s*고여|임시운영|철거|테니스장|체육\s*(관|시설)|운동\s*시설|인공|폭포|주민센터|children'?s\s*park|playground/i;

// An underscore in a name is a data artifact, never part of a real place name
// ("정원으로 교감하는 경계_울").
const ARTIFACT = /_/;

// Four or more whitespace-separated tokens is a DESCRIPTION, not a name. Three is
// still allowed because real parks use it ("초안산 숲속 공원", "목동 파리공원").
const MAX_TOKENS = 3;

// A bare generic name makes an unusable ROUTE name — "강남 근린공원 루프" tells an
// owner nothing, and a name that could be anywhere is anywhere.
const GENERIC = /^(근린|문화|체육|생태|시민|평화|호수|가족|중앙|어울림)?\s*(공원|광장|마당)$/;

// Streets misfiled under a green category. "전농로5길" came through as a park.
const STREETISH = /(로|길)\s*\d*(가|나|다|라|마)?길$|^[가-힣]+대?로$/;

// A parenthesised annotation carries operating notes or dates, not an identity —
// it truncates into nonsense inside a route name.
const ANNOTATED = /[（(]/;

// A name long enough to be a sentence is a description, not a place. Measured:
// "정원으로 교감하는 경계_울" and "물이 고여있는 연못(건물뒤편)" both landed in
// route names and had to be withdrawn.
const MAX_NAME = 16;

export function isUsableGreen(f) {
  if (!f || !f.lat || !f.lng) return false;
  const category = f.category || f.kind;
  if (!GREEN_CATEGORIES.includes(category)) return false;
  const name = (f.name || '').trim();
  if (!name) return false;                 // an unnamed green cannot name a route
  if (name.length > MAX_NAME) return false;
  if (SKIP.test(name)) return false;
  if (ARTIFACT.test(name)) return false;
  if (name.split(/\s+/).filter(Boolean).length > MAX_TOKENS) return false;
  if (GENERIC.test(name)) return false;
  if (STREETISH.test(name)) return false;
  if (ANNOTATED.test(name)) return false;
  return true;
}
