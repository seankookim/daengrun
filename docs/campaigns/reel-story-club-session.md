# 도그스하이 — REEL story spec: **오늘 밤, 우리 / TONIGHT, US** (10s, 12 shots)

*Written 2026-08-25 after Sean's note: no transitions, no film treatment, no audio, clips too slow,
and — the real one — **no story**. "We are not an Asian MNet." This spec replaces the montage reels
with one narrative, one crew, one night, one protagonist.*

## 1. The story

A club session, dusk to night, told through one runner — the woman with the golden retriever.
**Beginning:** the crew gathers under a bridge at last light; she arrives late.
**Middle:** they roll out, cross the Han bridge as the sun dies, dive into the neon streets, and
hit the hard middle where nobody is smiling — then attack a stair climb and break out onto an
overlook above the whole city.
**End:** they arrive at a subway station entrance, spent; hands slap, leashes go slack, the crew
peels off down the stairs. She is last, at the station mouth, wrecked and grinning, her dog leaning
into her — and the mark rises over her as the picture falls to black.

That is the culture: not a stunt, not a jump cut of joy — **a session, and the walk home from it.**

## 2. Continuity contract (this is what makes it a film and not a montage)

| element | locked value |
|---|---|
| Time | one continuous evening: dusk (s01–s04) → full night (s05–s12) |
| Place | Seoul: bridge plaza → Han bridge → streets → stairs → overlook → subway entrance |
| Crew | the same six Korean runners in plain unbranded kit, muted tones |
| Protagonist | young Korean woman, dark hair coming loose and wet, light blue tank under a black vest |
| Her dog | golden retriever, always at her side, always facing her direction of travel |
| Other dogs | shepherd mix, white Jindo, Border Collie — same four dogs all night |
| Light | cold blue ambience cut by warm sodium/neon pools; practicals bloom into halation |
| Camera | tracking and handheld only — the camera runs WITH them, never watches from a tripod |

**Character consistency is bought with reference images, not description.** Attaching a locked
reference of her to a shot clones her identity exactly — the "cloning" failure from the poster
rounds is precisely the tool a story needs. ⚠ Measured caveat: a selfie reference also drags
selfie *framing* and her smile into the shot, so **use her reference only for the shots where she
faces camera (s02, s12); for tracking and effort shots, describe her in words instead** — that is
why s02/s05/s07 were re-rolled.

## 3. Shot list — fast cuts, 0.5–1.2s (the whole point is pace)

| # | t | shot | cut out on |
|---|---|---|---|
| s01 | 0.0–0.8 | Under-bridge plaza at last light, crew converging, leashes clipping, a dog shakes | flash |
| s02 | 0.8–1.5 | Tracking alongside: she jogs in late to join them, hand half-raised | whip left |
| s03 | 1.5–2.2 | Ground-level reverse tracking — a forest of shoes and paws moving out | hard cut |
| s04 | 2.2–3.1 | Wide tracking: the pack crossing the Han bridge, last orange band behind | flash |
| s05 | 3.1–3.7 | Hip-height tracking, no faces: her legs and the retriever's paws in matched rhythm | whip right |
| s06 | 3.7–4.4 | Handheld dive into neon streets, bodies passing close to the lens | hard cut |
| s07 | 4.4–5.2 | Her face in profile mid-effort, no smile, breath clouding | slow dissolve 4f |
| s08 | 5.2–5.8 | Low side angle: the retriever at full drive, leash under load | flash |
| s09 | 5.8–6.6 | The crew attacking a stair flight, dogs surging ahead | hard cut |
| s10 | 6.6–7.5 | Overlook: arms up, doubled over, city glittering below — **the release** | whip up |
| s11 | 7.5–8.4 | Subway entrance: hands slapping, leashes slack, two peel off down the stairs | hard cut |
| s12 | 8.4–10.0 | Her at the station mouth, wrecked and grinning, dog leaning in; train light washes over | logo → black |

**Slogan card** at 7.0s over the release: **오늘 밤, 우리.** with `TONIGHT, US.` beneath in red.
**End treatment** (unchanged law): mark stamps in centred over the live s12 frame at 9.2s
(103%→100%, 0.2s), picture fades to black beneath it 9.45–10.0s, mark holds full white alone.

## 4. Post-treatment — the house film look (this was missing entirely)

Applied to every shot in the edit, proven in `reels/R3/R3-SAME-ENERGY-10s-v2.mp4`:

- **Halation glow** — duplicate, `gblur sigma≈26`, curve the lowlights out, screen back at ~34%.
  Practicals and wet asphalt bloom the way real anamorphic night footage does.
- **35mm grain** — `noise=alls=9:allf=t+u`, temporal so it moves.
- **Chromatic bleed** — `rgbashift rh=-2 bh=2 rv=1 bv=-1`.
- **Gate weave** — crop 8px and drift the window on `sin(n/7)`/`cos(n/9)`; the frame breathes like film.
- **Vignette** `PI/4.4` and a contrast/saturation lift of 1.10/1.06.
- **Transitions** — 2-frame white **flash frames** on the hard beats (s01→s02, s04→s05, s08→s09),
  **whip blur** on the pans, one 4-frame dissolve into the effort shot. Never a plain cut all the way through.
- **Speed ramps** — 1.15–1.3× on the connective shots, 1.0× on the emotional ones (s07, s12).

## 5. Sound (there was none — that was a miss)

Generated instrumental bed (`sonilo_music`, 0.75 cr per 12s — effectively free): 150 BPM, filtered
kick and city hiss alone under s01–s03, industrial snare enters on the bridge, distorted sub-bass
through the streets, peak at the overlook release, **one final hit and abrupt silence** as the mark
lands. Foley on top: leash clips, paw-strikes on wet asphalt, breath, a train's rush under s12.
Music must stop dead at the stamp — the last half second is silence.

## 6. Production route (free)

Stills are already generated at 9:16 and de-branded with the garment mark: `higgsfield-out/story/final/`.
Animate each in the **web console** — Seedance 2.0 Mini (UNLIMITED), 4s, aspect **Auto** (frames are
already 9:16 so they will not letterbox), audio **Off** — then cut to the table above and apply §4 and §5.
