# 도그스하이 — Reel storyboards for Higgsfield (5 × 10s, 31 shots)

*Written 2026-08-25. Image-to-video ONLY — every shot animates an approved plate as its start frame.*

## How to run a shot

```bash
higgsfield generate create <model> --start-image <plate.png> \
  --prompt "<PROMPT>  NEGATIVE: <per-shot negative + global negative>" \
  --duration <n> --aspect-ratio 9:16 --json
```

Generate the full clip, cut to timecode in edit; the surplus seconds are handles.

## The end treatment (identical in all five, done in edit — the logo is NEVER generated)

The final shot plays live. At that shot's midpoint the white running-dog mark + 도그스하이 + red DOG'S HIGH
stamps in centred over the moving image (103%→100% over 8 frames, ~0.25s). ~0.6s before the out, the picture
falls to black beneath the mark while the mark holds full white; the last beat is logo alone on black.
Slogan cards clear before the mark arrives so the two never share the frame. Preview frames per reel:
`higgsfield-out/reels/endtreatment/<R#>-a|b|c.jpg` (clean → mark over scene → black).

## Credits — measured 2026-08-25 via `higgsfield generate cost` (9:16)

| model | clip | credits | per second | use for |
|---|---|---|---|---|
| veo3_1_lite | 4s / 6s / 8s | 4 / 6 / 8 | 1.0 | quiet holds, macros, selfies |
| grok_video | fixed | 7.5 | — | cheap alternates |
| kling3_0 std | 5s | 10 | 2.0 | hero motion, pans, handoffs |
| kling3_0 pro | 5s | 12.5 | 2.5 | upgrading a keeper |
| veo3_1 fast | 4s / 8s | 11 / 22 | 2.75 | hardest natural motion |
| seedance_2_5 720p | 5s | 32.5 | 6.5 | water, steam, crowds |
| seedance_2_5 1080p | 5s | 45 | 9.0 | final-grade physics |

**There is no flat per-10-seconds rate** — a reel costs the sum of its shots. As specced: **397 cr for all five**
(~79/reel). All-veo3_1_lite budget build: **124 cr for all five** (24/reel). Retries run 1.5–2×.
Recommended: lite draft of the whole reel, then re-shoot the 2–3 load-bearing shots on kling3_0 → **~55–75 cr per finished reel**.

## Global motion negative (append to every prompt)

no morphing limbs, no changing paw count, no gait transitions or foot-skating, no floating or detaching leash, no leash passing through a body, no duplicated tail, no eye glow or tapetum shine, no face drift or identity change, no new text, no signage, no logos or brand marks appearing, no watermark, no subtitles, no extra people entering frame, no camera shake beyond what is specified, no zoom unless specified, no slow-motion unless specified, no scene cut inside the clip, no colour shift away from the start frame's grade

QC at 0.25×: paw count, gait continuity, leash attachment both ends, tail count, face identity, no text/mark appeared,
dog facing and travelling the same direction as its runner.

## R1 — EVERY DAMN DAWN. (새벽 리추얼 · culture)

The ritual, compressed into ten seconds: the window, the click, the door, the crew, the handoff, the hold. Nothing is won in this ad — it is simply that they went, again.

**Slogan card** at 6.9s: “EVERY DAMN DAWN.” · **Sound:** 0–3.6s no music at all, only foley. Harness CLICK at 2.05s is the downbeat that starts a 152 BPM breakbeat. Music cuts dead at 6.4s to raw breath. Two heartbeat thumps under the logo.

**End treatment:** Final shot runs 7.2–10.0s. The hug plays clean for 1.4s; at 8.6s the white mark stamps in centred over the live frame (103%→100% over 8 frames, 0.25s); from 9.2s the image falls to black beneath it over 0.6s while the mark holds at full white; 9.8–10.0s pure black, mark and wordmark alone.

**Cost:** 80 cr as specced · 28 cr budget build

**References to send with the script:** characters: `FW-B1-doorburst.png`, `FW-S73-leashhandoff.png`, `FW-B9-finishhug.png` · dogs: `FW-S54-bucklemacro.png`, `FW-S83-mistcool.png` · wardrobe / garment mark: `FW-A1-crosswave.png` · logo (overlay only, never generated): `logo-alpha.png`

### R1-1 · 0.0–1.2s · veo3_1_lite 4s · 4cr
- **Start frame:** `docs/campaigns/higgsfield-out/batch6/FW-S32-windowwipe.png`
- **Prompt:** Locked-off interior shot at dawn, no camera movement whatsoever. A human hand, already mid-gesture, completes one slow horizontal wipe across the condensation-fogged window pane, dragging a clean arc of clarity through the fog; individual water droplets run down inside the wiped band and collect at the bottom edge. Through the clearing arc the cold blue pre-dawn street outside resolves into focus over roughly one second. Simultaneously the dog standing in the dark interior turns its head toward the window — a single, calm, deliberate head turn of about 30 degrees, ears lifting once — and holds, looking out. Its body stays planted; only the head moves. Fog begins to creep back at the edges of the wiped arc by the end of the clip. Interior stays in deep shadow, exterior stays cold blue; the contrast between them is the whole image. 35mm film grain breathes gently.
- **Negative (+ global):** no reflection of a camera or crew in the glass, no additional hands, no fog clearing on its own, no dog stepping forward
- **Sound:** glass squeak, faint street hum

### R1-2 · 1.2–2.2s · kling3_0 5s · 10cr
- **Start frame:** `docs/campaigns/higgsfield-out/batch6/FW-S54-bucklemacro.png`
- **Prompt:** Extreme macro, camera absolutely static, shallow depth of field. Two hands hold the harness buckle at the dog's chest and press it closed: the male tab slides into the female housing and seats with a decisive snap, the plastic flexing minutely at the moment of engagement. Immediately after the click the fingers release and withdraw a few centimetres, leaving the buckle alone and sharp in the centre of frame. The webbing pulls taut for a beat and settles. Behind the buckle, out of focus, the dog's chest rises once with a single breath and its fur shifts with it. Individual fibres in the strap and single guard hairs stay crisp. Do not move the camera, do not rack focus, do not widen out — the entire performance is the buckle closing and the hands leaving.
- **Negative (+ global):** no third hand, no re-opening of the buckle, no dog standing up, no camera push, no focus rack
- **Sound:** one loud CLICK, isolated, no music yet

### R1-3 · 2.2–3.6s · kling3_0 5s · 10cr
- **Start frame:** `docs/campaigns/higgsfield-out/batch12/FW-B1-doorburst.png`
- **Prompt:** Handheld camera at chest height with a slow, controlled push forward of about ten percent over the clip. The doorway's bright interior light spills onto the night pavement; the runner and both dogs come through the opening directly toward the lens and take one full stride each into the street, the dogs slightly ahead and pulling, leashes going taut and staying taut with visible load. Fabric moves correctly with the stride, the runner's shoulders drop into the first pace, and the light on their bodies falls off sharply as they clear the door frame and enter the cooler street light. Everything behind the doorway stays dark. The strides are real strides — full extension, correct footfall order for both human and dogs, no hovering.
- **Negative (+ global):** no door closing behind them, no additional runners, no dog looking back, no leash slack
- **Sound:** door bang, first footfalls on wet pavement

### R1-4 · 3.6–5.0s · seedance_2_5 5s · 32.5cr
- **Start frame:** `docs/campaigns/higgsfield-out/batch12/FW-A1-crosswave.png`
- **Prompt:** Camera pans smoothly left to right, matching the crew's speed so the runners stay roughly centred while the crosswalk stripes and the sunlit buildings sweep through frame behind them. The crew runs as a loose pack across the wide crossing; the front runner's raised arm completes its wave — a genuine, loose, mid-run wave, not a hold — and comes back down into arm swing. The two dogs at the front of the pack keep their pace, tongues out, ears moving with each footfall. Sun is hard and high: shadows race across the painted stripes beneath everyone, and highlights flare on shoulders and shoe uppers. Bodies bounce naturally in the vertical axis; nobody glides. Warm sun-drenched grade with heavy contrast holds constant.
- **Negative (+ global):** no runner stopping, no dog crossing in front of the pack, no traffic entering, no crowd on the sidewalk changing
- **Sound:** music enters hard on the downbeat, 152 BPM

### R1-5 · 5.0–6.4s · kling3_0 5s · 10cr
- **Start frame:** `docs/campaigns/higgsfield-out/batch8/FW-S73-leashhandoff.png`
- **Prompt:** Tracking shot moving alongside the pair at their running speed, camera locked to their pace so the background streaks past horizontally while the two runners stay stable in frame. The leash handle passes from the first runner's hand to the second runner's hand in one continuous motion, like a relay baton: fingers open, the loop transfers, the receiving hand closes around it and takes the load. The leash never goes slack and never touches the ground; the dog out front never breaks stride or turns its head — it simply keeps running, unbothered, which is the entire point of the shot. Both runners stay in full stride throughout the exchange; their eyes go to the handle at the moment of transfer, then forward again. Golden hour side-light rims both bodies.
- **Negative (+ global):** no dog slowing, no leash slack or drop, no runner stopping, no third hand entering
- **Sound:** music continues, footfalls layered in

### R1-6 · 6.4–7.2s · veo3_1_lite 4s · 4cr
- **Start frame:** `docs/campaigns/higgsfield-out/batch8/FW-S83-mistcool.png`
- **Prompt:** Very slow-motion macro, camera static. A fine mist of water drifts across the dog's face from frame left; individual droplets catch the low backlight and hang, glittering, before settling on the fur and muzzle. The dog blinks once — a slow, heavy, contented blink — and its tongue moves slightly. Nothing else in the frame changes. Backlit droplets form a soft glowing halo around the head. The dog does not turn, does not step, does not shake.
- **Negative (+ global):** no shaking off, no head turn, no hand entering frame, no speed ramp to real time
- **Sound:** music cuts dead here — only a soft hiss of water

### R1-7 · 7.2–10.0s · kling3_0 5s · 10cr
- **Start frame:** `docs/campaigns/higgsfield-out/batch12/FW-B9-finishhug.png`
- **Prompt:** Camera static, slight handheld breathing only. The runner is already on both knees; they pull the panting dog in against their chest and hold. The dog leans its full weight into them and its tail moves once, low and slow. The runner's eyes close and their head tips down until their forehead rests against the dog's skull; both chests visibly rise and fall out of sync, hard, from real effort. Nothing dramatic happens — the entire shot is the hold, the breathing, and the stillness after work. Hard flash light falls off fast into black at the frame edges, so the two of them sit in a pocket of light with darkness all around. Hold the composition dead centre and do not move in — the logo will occupy the centre of this frame in the edit.
- **Negative (+ global):** no standing up, no dog licking the face, no camera push, no additional people, no cut
- **Sound:** music silent; breath, panting, distant wind; two heartbeat thumps under the logo

## R2 — CHASE THAT HIGH. (스피드 · culture)

Six shots of pure velocity, every one travelling left to right so the cuts read as one continuous sprint. The heritage line delivered as an adrenaline spike.

**Slogan card** at 6.6s: “CHASE THAT HIGH.” · **Sound:** 140 BPM phonk with a riser that never resolves until 7.0s; sub-bass drop at 1.4s; hard silence at 8.6s; one thump under the logo.

**End treatment:** Final shot runs 7.2–10.0s. Silhouette sprint plays 1.4s at half speed; at 8.6s the mark stamps in over the flare; from 9.2s the frame falls to black beneath it over 0.6s; 9.8–10.0s black, mark alone. The dip-to-black here doubles as the music's hard stop.

**Cost:** 105 cr as specced · 24 cr budget build

**References to send with the script:** characters: `FW-G6R.png`, `FW-G9R.png` · dogs: `G10-twodogs.png`, `FW-S47-puddlesheet.png` · wardrobe / garment mark: `FW-G4R.png` · logo (overlay only, never generated): `logo-alpha.png`

### R2-1 · 0.0–1.4s · kling3_0 5s · 10cr
- **Start frame:** `docs/campaigns/higgsfield-out/batch15/FW-G6R.png`
- **Prompt:** Slow-shutter panning shot travelling left to right, and the motion smear intensifies progressively across the clip. Runner and dog explode out of the dark underpass mouth into blazing gold light: for the first third they are still partly in shadow, then the light hits them fully and blows out the highlights on shoulders, arms and the dog's coat. The tunnel walls and everything behind them stretch into long horizontal amber streaks; the pair stays half-sharp at the centre — legible bodies inside a melting world. Both are in genuine full extension, the dog slightly ahead, leash under real load and streaking with them. Warm amber palette, heavy 35mm grain, exposure lifting as they emerge.
- **Negative (+ global):** no camera stopping, no dog behind the runner, no clean sharp background, no exposure crush
- **Sound:** riser begins under a low sub rumble

### R2-2 · 1.4–2.8s · kling3_0 5s · 10cr
- **Start frame:** `docs/campaigns/higgsfield-out/batch15/FW-G4R.png`
- **Prompt:** Hard left-to-right pan at high speed, camera locked to the running pair. The glowing stone wall behind them dissolves into pure horizontal streaks of gold and ochre; individual stones are unreadable, only bands of light remain. The runner and dog hold half-sharp in the centre of frame in full stride, the dog's ears pinned back by the airstream, the runner's clothing pressed flat against the body by speed. Their feet strike and leave the ground in correct rhythm; the dust they throw smears with them. Nothing in the frame is static except the pair's relative position. Grain heavy, palette locked to warm amber.
- **Negative (+ global):** no background resolving into focus, no gait change, no dog turning its head
- **Sound:** bass drops on the first frame

### R2-3 · 2.8–4.2s · seedance_2_5 5s · 32.5cr
- **Start frame:** `docs/campaigns/higgsfield-out/batch6/FW-S47-puddlesheet.png`
- **Prompt:** Begin in extreme slow motion, then ramp to full speed at roughly the halfway point. The runner and the black retriever strike a wide puddle at full speed; a sheet of water fans upward and outward from the impact, and in slow motion every individual droplet is legible, backlit to silver, hanging in the air with visible surface tension. As the ramp hits real time the sheet collapses, the water breaks apart, and the pair exits frame right, leaving the disturbed puddle rocking and the reflection shattering into fragments. The dog's coat is visibly soaked and heavy on the exit. Physics must be real water physics — a sheet from a strike, not a splash effect.
- **Negative (+ global):** no cartoon splash, no water frozen through the whole clip, no dog stopping to shake, no repeat impact
- **Sound:** water crash accented, drums continue underneath

### R2-4 · 4.2–5.6s · kling3_0 5s · 10cr
- **Start frame:** `docs/campaigns/higgsfield-out/batch15/FW-G9R.png`
- **Prompt:** Panning shot following the pair through a hard street corner; the lean angle deepens visibly across the clip as they carve the turn. Background whips past in long diagonal streaks that rotate with the corner, giving the frame a sense of centrifugal drag. The runner's inside shoulder drops, the outside arm swings wide for balance; the dog leans into the same arc, its inside legs reaching further under its body. Both stay half-sharp inside the blur. Warm amber grade, heavy grain, the horizon tilting a few degrees with the lean.
- **Negative (+ global):** no upright posture through the turn, no dog leaning the opposite way, no background stabilising
- **Sound:** tyre-squeal-like whoosh layered over the beat

### R2-5 · 5.6–7.0s · seedance_2_5 5s · 32.5cr
- **Start frame:** `docs/campaigns/higgsfield-out/batch13/G10-twodogs.png`
- **Prompt:** High-speed pan travelling with one runner and two dogs on a double lead, all three at full extension. Both leads stay taut and parallel, never crossing and never touching the ground. The dogs' gaits are offset from each other by half a stride so the frame has internal rhythm; the runner's arm absorbs the pull with a visible flex. Background is a continuous smear of gold. All three bodies stay half-sharp and correctly proportioned relative to one another. Coats ripple in the airstream; ears pinned.
- **Negative (+ global):** no leads crossing or tangling, no dog dropping behind, no third dog appearing, no leads slackening
- **Sound:** double kick pattern, riser tightening

### R2-6 · 7.2–10.0s · kling3_0 5s · 10cr
- **Start frame:** `docs/campaigns/higgsfield-out/batch15/FW-G8R.png`
- **Prompt:** Half speed throughout, camera panning slowly with the pair. Sunset silhouette sprint along the levee crest: runner and dog rendered as near-black shapes rimmed in molten orange, running against a smeared amber sky. Lens flare blooms gradually across the frame from the sun behind them, growing brighter through the clip until it nearly veils the centre. Grass in the foreground streaks past as dark bands. Both bodies stay in clean, readable stride silhouette — the shapes are the subject, so their outlines must never blur into each other or into the background. Compose with the pair low and the sky open above them; the centre of frame stays clear for the logo in the edit.
- **Negative (+ global):** no faces resolving out of silhouette, no flare covering the runners entirely, no camera stopping, no cut
- **Sound:** music peaks then cuts to hard silence at the dip

## R3 — SAME ENERGY. (같은 텐션 · culture · ends on the blue selfie girl)

Joy escalation, shot on phones: nose in the lens, tongues out, the crew airborne, the ear-lick, the groufie — and the blue selfie girl as the train blasts through. Her nine-frame set is the character pack that keeps her face identical across takes.

**Slogan card** at 6.0s: “SAME ENERGY.” · **Sound:** Bright 128 BPM house from frame one; vinyl-stop at 6.2s straight into the train's roar; music returns soft and warm under the logo.

**End treatment:** Final shot runs 6.4–10.0s (3.6s, the longest hold in the set — she carries the ending). Her laugh and the train play clean for 1.8s; at 8.2s the mark stamps in centred over her; from 9.2s the frame falls to black beneath it over 0.7s as the train roar decays; 9.9–10.0s black, mark alone.

**Cost:** 64 cr as specced · 24 cr budget build

**References to send with the script:** characters (blue-girl consistency pack): `E2-gateselfie.png`, `E4-afterrain.png`, `E1-riverselfie.png`, `E9-steamselfie.png`, `E8-tunnelgold.png` · dogs: `FW-C4-nosecam.png` · wardrobe / garment mark: `FW-C5-groufie.png` · logo (overlay only, never generated): `logo-alpha.png`

### R3-1 · 0.0–1.2s · veo3_1_lite 4s · 4cr
- **Start frame:** `docs/campaigns/higgsfield-out/batch12/FW-C4-nosecam.png`
- **Prompt:** Phone front-camera framing with a natural handheld wobble. The golden retriever pushes its nose the last few centimetres into the lens until the nose fills a third of the frame and goes soft with proximity; the nostrils flare twice as it actually sniffs the phone, and a light fog of breath blooms on the glass and clears. Behind the dog the runner's face cracks from a grin into an open laugh, head tipping back slightly. Warm golden backlight rims both heads. The wobble is a real hand holding a phone, not a camera move.
- **Negative (+ global):** no lens flare artifacts, no dog licking the lens, no phone visible, no other people entering
- **Sound:** sniff, glass tap, laugh

### R3-2 · 1.2–2.4s · veo3_1_lite 4s · 4cr
- **Start frame:** `docs/campaigns/higgsfield-out/batch12/FW-C8-tonguematch.png`
- **Prompt:** Arm's-length selfie framing, slight wide-angle distortion, gentle handheld drift. Runner and dog are cheek to cheek, both with tongues out in matching goofy expressions; they hold the pose for about half the clip, then the dog breaks first and turns to lick the runner's cheek in one quick motion, and the runner scrunches their face and laughs. Golden evening light, warm skin tones, both faces stay fully legible throughout.
- **Negative (+ global):** no face swap or drift, no dog leaving frame, no second dog, no zoom
- **Sound:** beat continues, laugh on the lick

### R3-3 · 2.4–3.8s · seedance_2_5 5s · 32.5cr
- **Start frame:** `docs/campaigns/higgsfield-out/batch12/FW-A7-groupjump.png`
- **Prompt:** Camera static, low angle against blue sky. The crew and both dogs are already airborne at the start of the clip; hold them in the air in slight slow motion for roughly the first third — arms up, knees tucked, the dogs fully extended mid-leap — then resume normal speed and let everyone land together, knees flexing to absorb, dust and grass kicking up at the feet, everyone laughing on the landing. The landing must be physically correct: heaviest bodies land first, the dogs land on their forelegs and rebound. Hard noon sun, deep blue sky, hard shadows snapping back under each body as they touch down.
- **Negative (+ global):** no floating, no landing out of frame, no dog landing on a person, no additional jumpers
- **Sound:** whoosh into a landing thump

### R3-4 · 3.8–5.0s · kling3_0 5s · 10cr
- **Start frame:** `docs/campaigns/higgsfield-out/batch13/W5-stepslick.png`
- **Prompt:** Static camera with warm lens flare drifting through the frame from the low sun. The dog's tongue reaches the runner's ear and the runner immediately doubles over laughing, shoulders shaking, one hand coming up to fend the dog off without any real conviction; the friend beside them cracks up in reaction. The flare pulses brighter as a body shifts in front of the sun. Everything is warm, hazy and sun-bleached; movement is loose and unchoreographed. Keep both faces readable through the flare.
- **Negative (+ global):** no flare washing out the whole frame, no dog jumping onto a lap, no camera move
- **Sound:** close laughter, mic-close and warm

### R3-5 · 5.0–6.4s · veo3_1_lite 4s · 4cr
- **Start frame:** `docs/campaigns/higgsfield-out/batch12/FW-C5-groufie.png`
- **Prompt:** Arm's-length group selfie, handheld, the frame jostling as bodies press in. Five faces crowd toward the lens and two dog snouts push in from the sides; over the clip one dog shoves further into frame and becomes momentarily the largest thing in it, forcing a face to lean out of the way, and everyone laughs at the intrusion. Hard flash-lit at night with motion ghosting at the frame edges. The jostle is the performance — nobody holds a pose.
- **Negative (+ global):** no face count change, no dog leaving frame, no static held pose, no new person
- **Sound:** crowd giggle, shuffle

### R3-6 · 6.4–10.0s · kling3_0 5s · 10cr
- **Start frame:** `docs/campaigns/higgsfield-out/batch13/E2-gateselfie.png`
- **Prompt:** Arm's-length selfie framing with an authentic handheld wobble, camera never repositions. The blue train behind her accelerates through the platform and becomes a continuous horizontal streak of blue and steel; the draft it drags hits her, and her wet hair whips across her face — she does not brush it away. Her laugh peaks: eyes crease shut, head tips back a few degrees, then comes forward again toward the lens. The golden retriever beside her leans further into her shoulder and its tongue lolls; its ears lift once as the train noise peaks. Warm golden backlight against the cool blue train gives the frame its two-temperature look. Hold her and the dog dead centre with clean space above them — the logo lands over this frame in the edit.
- **Negative (+ global):** no train stopping, no doors opening, no readable text on the train or platform, no second person, no camera reposition, no cut
- **Sound:** vinyl stop into full train roar, decaying under the logo

## R4 — 인계. THE HANDOFF. (앱 스토리 — 못 뛰는 날에도, 얘는 뛴다)

The app ad, told without a single screen. You cannot run today; someone who can, will. Balcony hesitation, the click, the handoff mid-stride, full flight, the cool-down, carried home.

**Slogan card** at 6.2s: “믿고 맡기는 러닝.” · **Sound:** Sparse piano pulse from 0s; one sub-bass hit on the handoff at 2.6s; strings swell to 7.2s then release into warm near-silence; a single piano note under the logo.

**End treatment:** Final shot runs 7.2–10.0s. The carry plays 1.4s; at 8.6s the mark stamps in centred over the walking figure; from 9.2s the street falls to black beneath it over 0.6s; 9.8–10.0s black. Korean slogan card clears before the mark arrives so the two never share the frame.

**Cost:** 48 cr as specced · 24 cr budget build

**References to send with the script:** characters: `FW-S44R-seedream.png`, `FW-S73-leashhandoff.png`, `FW-S88-carryhome.png` · dogs: `FW-S83-mistcool.png`, `G1-riverpan.png` · wardrobe / garment mark: `FW-S73-leashhandoff.png` · logo (overlay only, never generated): `logo-alpha.png`

### R4-1 · 0.0–1.4s · veo3_1_lite 4s · 4cr
- **Start frame:** `docs/campaigns/higgsfield-out/batch8/FW-S44R-seedream.png`
- **Prompt:** Locked-off telephoto from across the street at blue hour; no camera movement. On the narrow balcony the owner lifts a mug and takes one slow sip, steam curling up and drifting sideways in the cold air. Beside them the dog, forepaws up on the low rail, tracks something in the waking city below — one small head turn, ears pricking. Neither of them is going anywhere: the whole shot is hesitation. City lights behind them twinkle faintly and a distant window lights up. Cold blue exterior against the one warm interior glow of the balcony.
- **Negative (+ global):** no leash appearing, no person leaving the balcony, no camera push, no dog barking
- **Sound:** low city hum, a single piano note

### R4-2 · 1.4–2.6s · kling3_0 5s · 10cr
- **Start frame:** `docs/campaigns/higgsfield-out/batch8/FIX3-S38-awning.png`
- **Prompt:** Slow, gentle push-in of about eight percent. Under the fluorescent spill of the awning the dog drinks from the collapsible bowl on the ground — tongue lapping in a real rhythm, water surface rippling with each lap, a few drops falling from its muzzle. Partway through the clip a runner's hand enters frame from the right and closes around the leash handle lying beside the bowl, lifting it deliberately. The dog keeps drinking; it does not look up. That gesture — a stranger's hand taking the leash while the dog stays calm — is the whole product, so it must read clearly and unhurriedly.
- **Negative (+ global):** no face entering frame, no dog reacting with alarm, no bowl tipping, no fast movement
- **Sound:** water lapping, a sub-bass hit on the hand closing

### R4-3 · 2.6–4.2s · kling3_0 5s · 10cr
- **Start frame:** `docs/campaigns/higgsfield-out/batch8/FW-S73-leashhandoff.png`
- **Prompt:** Tracking shot moving alongside the pair at running speed; background streaks horizontally, the runners stay stable in frame. The leash handle transfers from one runner's hand to the other's in a single continuous relay-baton motion: fingers open, the loop passes, the receiving hand closes and takes the load. The leash stays taut throughout and never touches the ground. The dog out front never breaks stride, never slows, never looks back — its rhythm is completely undisturbed by the change of human, which is the emotional claim of the entire advertisement. Both runners remain in full stride; eyes flick to the handle at the moment of transfer, then forward. Golden side-light rims both bodies.
- **Negative (+ global):** no dog slowing or turning, no leash slack or drop, no runner stopping, no stumble
- **Sound:** strings enter on the transfer

### R4-4 · 4.2–5.8s · kling3_0 5s · 10cr
- **Start frame:** `docs/campaigns/higgsfield-out/batch13/G1-riverpan.png`
- **Prompt:** Slow-shutter pan at golden hour, camera matched to their speed. The black retriever runs in full extension along the river path, slightly ahead of the runner, leash under honest load. The far bank and the water dissolve into long horizontal bands of gold and green; the pair stays half-sharp. The dog's stride is powerful and loose — this is the animal doing what it was built for, and the shot should feel like relief after the restraint of the first two. Ears streaming back, coat rippling.
- **Negative (+ global):** no background resolving, no dog behind the runner, no other runners entering, no gait change
- **Sound:** strings building

### R4-5 · 5.8–7.2s · veo3_1_lite 4s · 4cr
- **Start frame:** `docs/campaigns/higgsfield-out/batch8/FW-S83-mistcool.png`
- **Prompt:** Extreme slow motion, static macro. A fine mist of water drifts across the dog's face; droplets catch the low backlight and hang glittering before settling into the fur. The dog blinks once — slow, heavy, contented — and its breathing visibly slows. The halo of lit droplets around its head is the light of the shot. Absolutely nothing else moves.
- **Negative (+ global):** no shaking off, no hand entering, no head turn, no ramp to real time
- **Sound:** strings peak and release into near-silence

### R4-6 · 7.2–10.0s · kling3_0 5s · 10cr
- **Start frame:** `docs/campaigns/higgsfield-out/batch8/FW-S88-carryhome.png`
- **Prompt:** Camera static at street level, slight handheld breathing. Dusk. The runner walks toward and past the lamppost carrying the spent dog draped across both shoulders like a lamb; the dog is completely relaxed, eyes half closed, one paw swinging gently with each step. The runner takes two or three slow, heavy steps across the clip — the walk of someone at the end of something — their expression content and wrecked. Streetlight rims both of them; the road behind falls off into darkness. Keep the walking figure centred with headroom above; the logo occupies that space in the edit.
- **Negative (+ global):** no dog struggling or being put down, no camera following, no additional pedestrians, no cut
- **Sound:** footsteps, warm silence, one piano note under the logo

## R5 — NO OFF SEASON. (사계절 · culture)

Weather as opponent: rain, wind, steam, water — and then the empty six-lane dawn expressway that belongs to whoever actually showed up.

**Slogan card** at 6.6s: “NO OFF SEASON.” · **Sound:** Four weather beds crossfading under one steady 145 BPM kick; every bed drops away at 7.2s leaving the kick alone; the kick stops dead on the logo stamp.

**End treatment:** Final shot runs 7.2–10.0s. The expressway wide plays 1.4s with a slow forward push; at 8.6s the mark stamps in over the vanishing point; from 9.2s the road falls to black beneath it over 0.6s; 9.8–10.0s black, mark alone. The kick stops on the stamp — silence carries the last half second.

**Cost:** 99 cr as specced · 24 cr budget build

**References to send with the script:** characters: `FW-C3-rainhood.png`, `FW-S69-steamvent.png` · dogs: `FW-S66-sprinklers.png`, `FW-S40-busstoprain.png` · wardrobe / garment mark: `FW-S45-flagwind.png` · logo (overlay only, never generated): `logo-alpha.png`

### R5-1 · 0.0–1.4s · kling3_0 5s · 10cr
- **Start frame:** `docs/campaigns/higgsfield-out/batch6/FW-S40-busstoprain.png`
- **Prompt:** Static camera shooting from outside through the rain-runneled glass wall of the bus shelter. Rain runs down the pane in continuous rivulets, distorting what is behind them. Inside the lit shelter the dog shakes hard — a full body shake starting at the head and travelling to the tail — throwing a halo of water droplets that catch the shelter's fluorescent light; the runner beside it flinches away and grins. The glass keeps the shake slightly abstracted and beautiful. Cool blue night outside, warm fluorescent inside.
- **Negative (+ global):** no camera entering the shelter, no readable signage, no bus arriving, no other passengers
- **Sound:** rain bed, shake, laugh

### R5-2 · 1.4–2.8s · veo3_1_lite 4s · 4cr
- **Start frame:** `docs/campaigns/higgsfield-out/batch12/FW-C3-rainhood.png`
- **Prompt:** Handheld selfie framing in a downpour, with real rain landing on the lens and blurring parts of the frame. The runner grins into the front camera, water streaming off the hood brim in a continuous curtain; they blink water out of their eyes. Behind them the dog shakes and throws a spiral of water that catches the streetlight. Everything is soaked; the joy is completely unbothered by it.
- **Negative (+ global):** no umbrella, no rain stopping, no clean dry lens, no additional people
- **Sound:** rain on the mic, laughter

### R5-3 · 2.8–4.2s · kling3_0 5s · 10cr
- **Start frame:** `docs/campaigns/higgsfield-out/batch6/FW-S45-flagwind.png`
- **Prompt:** Static camera on a long lens. The line of flags overhead cracks and snaps, pulled fully horizontal by the gust and rippling violently along their length. Beneath them the runner leans harder into the wind and gains one visible stride, clothing pressed flat against the body and fluttering behind; the dog runs low with its ears pinned completely back, body angled into the same wind. Dust and grit blow past horizontally through the frame. The wind is the antagonist and must be visible in every element — flags, fabric, fur, debris.
- **Negative (+ global):** no calm moment, no flags going slack, no runner straightening up, no camera move
- **Sound:** wind bed dominant, kick underneath

### R5-4 · 4.2–5.6s · seedance_2_5 5s · 32.5cr
- **Start frame:** `docs/campaigns/higgsfield-out/batch8/FW-S69-steamvent.png`
- **Prompt:** Static camera, night. A thick white steam cloud billows up from the street vent and fills the lower half of frame; the runner and the black retriever burst out of it directly toward the lens, the cloud parting around their bodies and swirling in their wake before it reseals behind them. Volumetric steam, lit hard from the front so it glows against the black street. The pair emerges from soft to sharp over about half a second. Real fluid behaviour in the steam — it must curl and eddy, not drift as a flat sheet.
- **Negative (+ global):** no steam disappearing instantly, no runner obscured for the whole clip, no colour cast change
- **Sound:** steam hiss, kick continues

### R5-5 · 5.6–7.2s · seedance_2_5 5s · 32.5cr
- **Start frame:** `docs/campaigns/higgsfield-out/batch8/FW-S66-sprinklers.png`
- **Prompt:** Camera pans slowly right to left as the sprinkler arcs sweep across the frame. Two dogs snap at the water mid-stride, jaws closing on the spray and missing, and the runners run straight through the arcs, soaked and laughing. Individual droplets flare in the backlight; the arcs cross and overlap, making shifting rainbows in the light. Grass is dark and wet underfoot and kicks up with each footfall. Everything moves — water, bodies, light — and the shot should feel like the most fun anyone has had all week.
- **Negative (+ global):** no dog stopping to drink, no sprinklers switching off, no slow motion, no static frame
- **Sound:** sprinkler patter, all beds at once

### R5-6 · 7.2–10.0s · kling3_0 5s · 10cr
- **Start frame:** `docs/campaigns/higgsfield-out/batch8/FW-S90-expressway.png`
- **Prompt:** Very slow forward push, about five percent across the clip, giving an aerial-like drift down the centre line. Six empty lanes of urban expressway at dawn stretch to a vanishing point where the sun is coming up; the lane markings converge toward it. Tiny in the middle distance, one runner and one dog run dead centre down the middle lane, away from camera, made small by the scale of the road. Heat and morning haze shimmer faintly near the horizon; the light warms perceptibly across the clip as the sun clears. The road is completely empty otherwise — the emptiness is the point. Compose so the vanishing point sits centre frame; the logo lands exactly there in the edit.
- **Negative (+ global):** no vehicles entering, no other runners, no camera turning, no lens flare spam, no cut
- **Sound:** all weather beds drop away; kick alone, then silence

