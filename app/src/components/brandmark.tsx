// 도그스하이 brandmark — the running-dog mark (Sean-supplied asset, app/assets/logo.png).
//
// The source art is an elongated leaping hound in ink with a single coral speed streak.
// It ships as the PNG Sean provided (1619×971, aspect 1.667) rather than a hand-trace —
// the asset is the truth. `resizeMode="contain"` keeps the aspect at any height.
//
// Sizing: pass `height`; width follows the source aspect. Used at 40 in the owner-home
// masthead lockup; legible down to ~22.
import { Image } from 'react-native';

const ASPECT = 1619 / 971; // source asset

// [2026-08-11] `logo-alpha.png` — the same art with the baked white background keyed out.
// The original ships as RGB with NO alpha channel (verified: hasAlpha=no, colorType=2), so on any
// non-white surface it rendered as a white rectangle. That made it unusable on a coloured button
// or a dark artifact. The alpha version is correct on every background, so it is now the only
// source; `tint` recolours the opaque pixels (the streak goes mono under tint — accepted for
// small in-button marks, where a two-colour mark would not read anyway).
export function BrandMark({ height = 40, tint }: { height?: number; tint?: string }) {
  return (
    <Image
      source={require('../../assets/logo-alpha.png')}
      style={{ width: height * ASPECT, height, ...(tint ? { tintColor: tint } : null) }}
      resizeMode="contain"
      accessibilityRole="image"
      accessibilityLabel="도그스하이"
    />
  );
}

// [2026-08-20 Sean] `BrandLockup` (마크 + 도그스하이 워드마크 + DOGS HIGH) 은퇴.
// 유일한 소비자였던 보호자 홈이 마크만 쓰도록 바뀌었다 — "글자 로고를 빼라"가 지시였고, 쓰이지
// 않는 채로 남겨두면 지우라던 바로 그것을 파일이 계속 들고 있게 된다. 두 홈 모두 이제 `BrandMark`다.
// 되살릴 일이 있으면 git history에 있다 (이 커밋의 부모).
//
// 부수적으로 고쳐진 법: 락업의 워드마크도 디스플레이 서체였으므로 보호자 홈엔 Black Han Sans가
// 두 번(워드마크 + 그리팅) 찍히고 있었다. 이제 그리팅 하나 — '화면당 1회'가 지켜진다.
