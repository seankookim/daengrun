# 도그스하이 — Reel storyboards for Higgsfield (5 × 10s)

*Written 2026-08-25. Image-to-video ONLY: every shot animates an approved plate from
`docs/campaigns/higgsfield-out/` as the start frame. Slogan cards + end card are edit overlays with
real fonts, never generated. End card: `higgsfield-out/reels/endcard-9x16.png` (logo + 도그스하이 +
DOG'S HIGH red kicker), stamped 103%→100% in the final ~1.5s of every reel, Nike-style.*

Per-shot handoff to Higgsfield: start frame = the plate file · prompt = the motion line · model =
Kling 3.0 (punchy cuts) / Seedance 2.5 (water, crowds) / Veo 3.1 (natural motion) · generate 2–3s,
cut to timecode in edit · output 9:16 via reframe or center-crop from 3:4 (headroom noted per shot).

Shared motion NEGATIVE: no morphing limbs, no paw-count change, no gait transitions, no floating or
detaching leash, no duplicated tail, no eye glow, no new text or logos. Reject at 0.25× on paw
morph, leash detach, face drift. The blue-selfie-girl character pack (R3) is batch13's E-set — the
reference-clone accident repurposed as the consistency asset.

## R1 — EVERY DAMN DAWN. (새벽 리추얼)

The ritual, compressed: wipe the window, click the harness, out the door, into the crew, pass the leash, hold the dog. Culture ad — the dawn people.

**Music/SD:** Silence + SFX until 3.6s, then 152 BPM breakbeat. Cut music dead at 6.4s; end on two heartbeat thumps.

| t | plate (start frame) | motion prompt | sound |
|---|---|---|---|
| 0.0–1.2s | `docs/campaigns/higgsfield-out/batch6/FW-S32-windowwipe.png` | Hand finishes wiping the fogged pane; the wiped arc clears, the dog's silhouette turns its head to the window. Slight handheld drift. | glass squeak |
| 1.2–2.2s | `docs/campaigns/higgsfield-out/batch6/FW-S54-bucklemacro.png` | The harness buckle clicks shut; fingers release; the dog's chest rises once. Macro, static camera. | one loud CLICK — this is the beat |
| 2.2–3.6s | `docs/campaigns/higgsfield-out/batch12/FW-B1-doorburst.png` | Runner and dogs burst through the doorway toward camera, one stride each, flash-lit; slight push-in. | door bang + first footfalls |
| 3.6–5.0s | `docs/campaigns/higgsfield-out/batch12/FW-A1-crosswave.png` | The crew sweeps left-to-right across the crosswalk; the front runner's wave completes; dogs lead the pack. Camera pans with them. | music kicks — 152 BPM |
| 5.0–6.4s | `docs/campaigns/higgsfield-out/batch8/FW-S73-leashhandoff.png` | The leash handle passes hand to hand mid-stride like a relay baton; the dog surges ahead unbroken. Tracking shot. | music continues |
| 6.4–8.2s | `docs/campaigns/higgsfield-out/batch12/FW-B9-finishhug.png` | The runner drops to both knees and pulls the panting dog in; the dog leans its whole weight in; eyes close. Music dead — breath only. | breath + wind |
| 8.2–10.0s | `docs/campaigns/higgsfield-out/reels/endcard-9x16.png` | END CARD: hold. Logo stamps in at 103%→100% over 8 frames. | two heartbeat thumps |

**Slogan card** at 7.6s: “EVERY DAMN DAWN.” · **References** — characters: `FW-B1-doorburst.png`, `FW-S73-leashhandoff.png` · dogs: `FW-B9-finishhug.png` · logo: `logo-alpha.png`, `endcard-9x16.png` · clothes: `FW-A1-crosswave.png`

## R2 — CHASE THAT HIGH. (스피드)

Six shots of pure velocity, all motion left-to-right, every cut a whip. The heritage line as an adrenaline shot.

**Music/SD:** 140 BPM phonk/drum roll from frame one, rising the whole way; hard cut to silence at 8.4s.

| t | plate (start frame) | motion prompt | sound |
|---|---|---|---|
| 0.0–1.4s | `docs/campaigns/higgsfield-out/batch15/FW-G6R.png` | Runner and dog explode from the dark underpass into blazing gold; motion smear intensifies through the shot. | riser starts |
| 1.4–2.8s | `docs/campaigns/higgsfield-out/batch15/FW-G4R.png` | Full-tilt pan past the glowing wall; wall texture streaks harder; the pair stays half-sharp. | bass drops |
| 2.8–4.2s | `docs/campaigns/higgsfield-out/batch6/FW-S47-puddlesheet.png` | The water sheet erupts in slow-motion for 20 frames, then snaps to full speed as they exit frame right. | water crash accented |
| 4.2–5.6s | `docs/campaigns/higgsfield-out/batch15/FW-G9R.png` | The cornering pair carves through the bend, lean deepening, background whipping. | tire-squeal-like whoosh |
| 5.6–7.0s | `docs/campaigns/higgsfield-out/batch13/G10-twodogs.png` | One runner, two dogs, three bodies at full extension inside the smear; camera races them. | double kick pattern |
| 7.0–8.4s | `docs/campaigns/higgsfield-out/batch15/FW-G8R.png` | Sunset silhouette sprint along the ridge, 50% slow-motion, flare blooming across the lens. | music peaks |
| 8.4–10.0s | `docs/campaigns/higgsfield-out/reels/endcard-9x16.png` | END CARD: hard cut from peak brightness to black; logo stamp. | silence, then one thump |

**Slogan card** at 8.0s: “CHASE THAT HIGH.” · **References** — characters: `FW-G6R.png`, `FW-G9R.png` · dogs: `G10-twodogs.png` · logo: `logo-alpha.png`, `endcard-9x16.png` · clothes: `FW-G4R.png`

## R3 — SAME ENERGY. (같은 텐션 · ends on the blue selfie girl)

Joy escalation: nose in lens → tongues out → crew airborne → ear-lick laughter → groufie → and the blue-girl selfie as the train blasts past. Her nine-frame batch13 set is the character pack.

**Music/SD:** Bright 128 BPM house from 0s; vinyl-stop at 6.2s into train rumble; music returns soft under end card.

| t | plate (start frame) | motion prompt | sound |
|---|---|---|---|
| 0.0–1.2s | `docs/campaigns/higgsfield-out/batch12/FW-C4-nosecam.png` | The golden's nose smashes into the lens, fogging it; the runner cracks up behind. Phone-cam wobble. | sniff + laugh |
| 1.2–2.4s | `docs/campaigns/higgsfield-out/batch12/FW-C8-tonguematch.png` | Cheek to cheek, both tongues out; the dog breaks first and licks the runner's cheek. | beat continues |
| 2.4–3.8s | `docs/campaigns/higgsfield-out/batch12/FW-A7-groupjump.png` | The whole crew and both dogs hang mid-air for 12 slow frames, then land laughing. | whoosh + landing thump |
| 3.8–5.0s | `docs/campaigns/higgsfield-out/batch13/W5-stepslick.png` | The ear-lick lands; the runner doubles over laughing; warm flare pulses. | laughter up-close |
| 5.0–6.2s | `docs/campaigns/higgsfield-out/batch12/FW-C5-groufie.png` | Five faces and two snouts jostle for the frame; one dog snout pushes in bigger. | crowd giggle |
| 6.2–8.2s | `docs/campaigns/higgsfield-out/batch13/E2-gateselfie.png` | THE BLUE SELFIE GIRL: her laugh peaks as the blue train blasts through behind her, hair whipped by the draft; the husky leans in. | vinyl stop → train roar |
| 8.2–10.0s | `docs/campaigns/higgsfield-out/reels/endcard-9x16.png` | END CARD over the train's fading rumble. | soft music returns |

**Slogan card** at 7.8s: “SAME ENERGY.” · **References** — characters: `E2-gateselfie.png`, `E4-afterrain.png`, `E8-tunnelgold.png`, `E9-steamselfie.png`, `E1-riverselfie.png` · dogs: `FW-C4-nosecam.png` · logo: `logo-alpha.png`, `endcard-9x16.png` · clothes: `E2-gateselfie.png`

## R4 — 인계. THE HANDOFF. (앱 스토리 — 못 뛰는 날에도, 얘는 뛴다)

The app ad. You can't run today — someone who can, will. Balcony hesitation → the click → the handoff → full flight → cool-down → carried home. Product told without a single UI screen.

**Music/SD:** Quiet piano pulse from 0s; one sub-bass hit at the 2.6s handoff; strings swell to 7.2s; warm silence for the carry.

| t | plate (start frame) | motion prompt | sound |
|---|---|---|---|
| 0.0–1.4s | `docs/campaigns/higgsfield-out/batch8/FW-S44R-seedream.png` | Blue hour. On the balcony the owner sips; the dog's ears prick at the waking city; a beat of stillness. | city hum, distant |
| 1.4–2.6s | `docs/campaigns/higgsfield-out/batch8/FIX3-S38-awning.png` | Cut to street level: the dog drinks; a runner's hand enters and takes the leash handle. Gentle push-in. | water lap + sub-bass hit |
| 2.6–4.2s | `docs/campaigns/higgsfield-out/batch8/FW-S73-leashhandoff.png` | The leash passes runner to runner mid-stride; the dog never breaks rhythm. The whole ad in one shot. | strings enter |
| 4.2–5.8s | `docs/campaigns/higgsfield-out/batch13/G1-riverpan.png` | Full flight along the river at golden hour; the black retriever stretches out; pan blur sings. | strings build |
| 5.8–7.2s | `docs/campaigns/higgsfield-out/batch8/FW-S83-mistcool.png` | The water mist drifts over the dog's face in slow-motion; eyes blink slow; backlit droplets hang. | strings peak, then release |
| 7.2–8.6s | `docs/campaigns/higgsfield-out/batch8/FW-S88-carryhome.png` | Dusk. The runner carries the spent, happy dog over both shoulders past the lamppost; two slow steps. | footsteps + warm silence |
| 8.6–10.0s | `docs/campaigns/higgsfield-out/reels/endcard-9x16.png` | END CARD with the Korean line first, brand after. | single piano note |

**Slogan card** at 8.2s: “믿고 맡기는 러닝. — THE HANDOFF.” · **References** — characters: `FW-S44R-seedream.png`, `FW-S73-leashhandoff.png` · dogs: `FW-S83-mistcool.png`, `FW-S88-carryhome.png` · logo: `logo-alpha.png`, `endcard-9x16.png` · clothes: `FW-S73-leashhandoff.png`

## R5 — NO OFF SEASON. (사계절)

Weather montage: rain, wind, steam, water, and the empty dawn expressway that belongs to the ones who showed up anyway.

**Music/SD:** Four weather beds crossfaded (rain → wind → steam-hiss → sprinkler patter) under one steady 145 BPM kick; kick alone survives to the end card.

| t | plate (start frame) | motion prompt | sound |
|---|---|---|---|
| 0.0–1.4s | `docs/campaigns/higgsfield-out/batch6/FW-S40-busstoprain.png` | Inside the bus stop the dog shakes a halo of rain; the runner grins through the streaked glass; rain runs down the pane. | rain bed |
| 1.4–2.8s | `docs/campaigns/higgsfield-out/batch12/FW-C3-rainhood.png` | Selfie in the downpour; the hood drips; behind, the dog mid-shake throws a spiral of water. | rain + laugh |
| 2.8–4.2s | `docs/campaigns/higgsfield-out/batch6/FW-S45-flagwind.png` | The flags crack fully horizontal; the pair leans harder into the gust and gains one stride. | wind bed |
| 4.2–5.6s | `docs/campaigns/higgsfield-out/batch8/FW-S69-steamvent.png` | They burst through the steam wall toward camera; the cloud swirls and reseals behind them. | steam hiss |
| 5.6–7.2s | `docs/campaigns/higgsfield-out/batch8/FW-S66-sprinklers.png` | Sprinkler arcs sweep across; both dogs snap at the water mid-stride; droplets flare in backlight. | sprinkler patter |
| 7.2–8.4s | `docs/campaigns/higgsfield-out/batch8/FW-S90-expressway.png` | The wide: six empty lanes at dawn, the tiny pair dead center, running at the sunrise. Slow aerial-feel push forward. | all beds fade; kick alone |
| 8.4–10.0s | `docs/campaigns/higgsfield-out/reels/endcard-9x16.png` | END CARD. | kick stops on the stamp |

**Slogan card** at 8.0s: “NO OFF SEASON.” · **References** — characters: `FW-C3-rainhood.png` · dogs: `FW-S66-sprinklers.png` · logo: `logo-alpha.png`, `endcard-9x16.png` · clothes: `FW-S45-flagwind.png`

