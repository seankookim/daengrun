# 도그스하이 — 이미지·영상 생성 프롬프트 (사전예약 캠페인)

*Written 2026-08-20. Extends `docs/instagram/prompt-library.md` (§0 gates, §1 style system, §2
negatives — all still binding) and `docs/instagram/reel-scripts.md` (R1–R8 shot lists). This file adds
what those two do not have: **a video prompt library**, and an image set recut to the shipped palette.*

**Sean's ruling 2026-08-20: the violet GPS trace stands.** Base DNA is updated accordingly in §2.

---

## 0. The brief, before any prompt

A running brand does not sell a service. It hands the athlete a verb and gets out of the way. Our
athlete has four legs and has never once been treated as one — that gap *is* the campaign, and every
frame below exists to close it.

Four rules decide whether a generated frame is campaign material or content:

1. **One idea per frame.** If you need a second sentence to explain the picture, you have a mood
   board, not a campaign.
2. **The dog is the athlete, never the pet.** No sitting pretty, no head tilt, no costume, no
   cuteness. Mid-stride, mouth open, working.
3. **Recognisable cropped to 10%.** Locked light, locked two-lens kit, one accent colour worn by the
   dog. If a stranger can't tell two of our frames came from the same shoot, the system has failed.
4. **The truth is the creative.** We publish our own thresholds, our own no-run days, our own pay
   table. Competitors sell convenience; nobody can copy a brand that shows its own floor.

And the constraint that makes all of it cheap: **we own a concept, we do not rent a person.** No real
athlete's or celebrity's name, likeness, career, or signature gesture — in copy, in a visual, or in a
prompt. Publicity-rights exposure = 0, casting budget = 0, and the idea survives anyone's bad week.

---

## 1. What is different in this campaign

| | Old (`prompt-library.md` v3) | This campaign |
|---|---|---|
| Accent | volt on gear, single accent | **three colours, three jobs** — §2.1 |
| Signature device | volt/white pulse rail | **violet GPS route trace** (ruled 2026-08-20) |
| Type colour | volt / cream | **coral-red `#FF5C3D`** headline, cream body |
| Route trace | n/a | **vector only, drawn from a real GPX** — §2.2 |

Everything else in `prompt-library.md` §0 (type policy, honesty gate, one-photographer rule),
§1.2 (treatments T1–T8), §2 (negatives), §2.2 (breed tokens) and §2.3 (locations) is unchanged and
still governs. Do not re-derive it here.

## 2. BASE DNA v3.1 — paste into every image prompt

### 2.1 The accent law (three colours, three jobs, never swapped)

```
ACCENT LAW — DOGS HIGH:
volt yellow-green #C6F542 — WORN BY THE DOG ONLY (bandana, harness, leash webbing).
  The single saturated in-camera element. Never on the coat, never on the human.
coral-red #FF5C3D — TYPE ONLY. Set in post, never generated, never on an object in frame.
violet #7B6CDF / #9F8FFF — THE ROUTE TRACE ONLY. Vector, never generated.
Everything else is restrained: crushed near-blacks at #0F1D13, or one disciplined
colour field. Never a busy multi-hue frame, never HDR, never orange-teal blockbuster.
```

Why it is a law and not a palette: three saturated colours with three fixed jobs is a system a viewer
learns in two posts. The same three used interchangeably is just a mood.

### 2.2 The trace law — the device that makes us honest instead of decorative

**The violet route trace is never generated and never invented. It is a vector path drawn from a real
GPX file, and any pace/distance readout beside it comes from that same file.**

This is the single highest-leverage rule in the document. A drawn squiggle with an invented
`8:34/km · 5.3km` beside it is a fabricated data display — it walks straight into the honesty gate
that bans generated GPS trails. The identical graphic, plotted from the founder's own recorded run,
is *proof*: the line is true, the number is true, and the device stops being decoration and starts
being the argument.

- Source: the founder's own runs (Strava export → GPX). Route geometry tooling already exists in
  this repo — see the `route-geometry` skill.
- **No GPX for that frame → no trace and no readout on that frame.** Not a rounded number, not a
  plausible one. Nothing.
- The trace never crosses a dog's or a person's face, and never appears on a trust surface (safety
  protocol, price, certification criteria, handoff) — those carry type and hairline only.
- A generator asked for "a glowing route line" will produce a fake one. Keep it out of the prompt
  entirely; it goes on in Figma.

### 2.3 The DNA block

```
BASE DNA — DOGS HIGH v3.1:
ACCENT: exactly one saturated in-camera accent — volt yellow-green #C6F542 — worn by
the dog as a bandana, harness or leash webbing. Never on the coat. Never two accents.
COLOUR: crushed deep blacks at #0F1D13, or ONE disciplined colour field. No HDR,
no orange-teal grade, no busy multi-hue frame.
BODIES: genuine full athletic stride, anatomically correct running gait, mid-air
moments prized. The dog moves like a teammate, not a pet — no sitting pretty, no
begging, no cuteness, no costume. Leash geometry physically correct and under real
load or genuinely slack, never floating.
ENERGY: candid documentary, mid-effort — open mouths breathing, sweat, breath vapor.
Nobody performs for the camera.
CASTING: Korean runners, 20s–30s, real athletic builds, no fashion-model faces.
Mid-size Korean dogs — Jindo mix, Border Collie, Welsh Corgi, retriever, shepherd mix.
TEXTURE: 35mm editorial grain, honest optical imperfection, no plastic skin, no
beauty retouching, no digital over-cleanliness.
LENS KIT: only two focal lengths exist in this campaign — a 20mm-equivalent wide used
low and close, and an 85–135mm long lens used compressed. Nothing in between.
TYPE SPACE: hold clean negative space where the entry's 타이포 스펙 says.
ANIMAL EYES: any dog toward the lens has natural dark wet eyes with a single small
specular catchlight — no eye glow, no tapetum eyeshine, no glowing pupils.
```

### 2.4 Global negative

```
NEGATIVE: no text anywhere in the image, no lettering, no signage, no logos, no
watermarks, no brand marks on apparel or shoes, no swoosh or any sportswear logo,
no invented shop signs; no real athlete, celebrity, or recognisable public figure;
no extra or missing limbs, no six-legged dogs, no duplicated tails, no fused paws,
no floating or detached leash, no leash passing through a body; no eye glow, no
retroreflective eyeshine; no cartoon, no illustration, no 3D render, no CGI look,
no plastic skin, no beauty retouch, no HDR, no orange-teal grade, no lens flare
spam; no costumes, no clothing on the dog beyond a bandana or harness; no sitting
pretty, no head tilt, no begging, no tongue-out cuteness pose; no GPS lines, no
map overlays, no route graphics, no app screens, no data readouts, no numbers;
no stock-photo smiling, no pointing at camera; no crowds of onlookers.
```

**Two lines in that block are honesty rules wearing a negative-prompt costume.** `no swoosh or any
sportswear logo` exists because several existing assets have one and it makes them unpublishable.
`no GPS lines / no numbers` exists because §2.2 says those arrive from a real GPX in post — a
generator inventing them is the exact failure the gate bans.

### 2.5 Per-tool dials

| Tool | Use it for | Dial |
|---|---|---|
| **Midjourney** | the photographic hero frames; best grain and light | `--ar 4:5` (feed) / `--ar 9:16` (story) · `--style raw` · `--stylize 100–250` (higher invents anatomy) · `--sref <locked style ref>` on every frame of a set · `--cref` to hold one dog across frames |
| **GPT-4o image** | anything needing Korean type generated in-frame, and precise instruction-following | Conversational; give placement and treatment in words. Proofread every 받침 at 100%. |
| **Imagen** | clean daylight, wide landscape, crowd/lineup geometry | Prompt in plain descriptive prose; it resists dense comma-stacking |
| **Flux** | macro texture — paw pads, leash fibre, wet asphalt | Photoreal by default; keep the prompt short and physical |

Locking `--sref` to one reference across the whole campaign is what buys the one-photographer rule.
Pick it once, write the ID into this file, never change it mid-season.

---

## 3. IMAGE PROMPTS

Format per entry: **ROLE** · **IDEA** · **PROMPT** (paste + BASE DNA + negative) · **TYPE** (set in
post) · **GATE**.

### P1 — 두 개의 그림자 · the one image
**ROLE** campaign master. **IDEA** Take the bodies out of the ad and the viewer fills the frame with
their own dog.
```
Aerial top-down view from a Han River bridge walkway at low dawn sun, camera looking
straight down at an empty riverside path. The bodies are OUT OF FRAME entirely — only
two long cast shadows run side by side across rhythmic bridge-shadow stripes on the
concrete: one human shadow, one mid-size dog shadow, both mid-stride, legs extended.
Cold blue concrete, one warm raking light from the left. Wet patches holding specular
highlights. Absolute stillness except the two shadows. Editorial 35mm grain.
```
**TYPE** bottom third, `한 번의 러닝, 두 개의 심박.` cream on the concrete. **GATE** CONCEPT-ONLY.

### P2 / P3 — 접지 다이프틱 · the pair that must be shot as one
**ROLE** grid tiles 2 and 3; R1 cuts 1 and 2. **IDEA** Two strikes, same beat, one of them isn't human.
```
P2: Extreme macro at ground level, lens 3cm above wet asphalt, a dog's front paw
striking the surface at full extension, water spraying outward in a crown, pad texture
and asphalt aggregate equally sharp, volt bandana edge just clipping the top of frame,
hard directional light raking across the wet surface, background fallen to near-black.

P3: THE IDENTICAL FRAME — same 3cm height, same focal length, same crop, same light,
same asphalt — with a running shoe striking the same spot at full extension, the same
crown of water.
```
**TYPE** none — they are a diptych and type would break the rhyme. **GATE** CONCEPT-ONLY.
⚠ Generate P3 as a variation *of P2's own output*, not from a fresh prompt. If the crop drifts, the
idea dies.

### P4 / P5 — 매치컷 얼굴 · the argument, settled by two faces
**ROLE** R1 cuts 6 and 7; the category claim. **IDEA** The state a human meets at 5km, on a dog's face.
```
P4: Extreme close-up on a mid-size Korean dog's face at kilometre four, long lens
compression, tongue out, jaw loose, eyes gone soft and far — the unmistakable look of
an animal deep in effort, not a pet posing. Breath vapor. Volt bandana whipping at the
edge of frame. Shallow depth, background dissolved.

P5: THE IDENTICAL LENS, LIGHT AND CROP on a Korean runner's face at kilometre five,
jaw loose, gaze soft and far in exactly the same way, sweat at the temple, breath
vapor. Same eye height in frame, same headroom.
```
**TYPE** P4 `개는 러너스 하이를 모른 채로 산다` · P5 `사람은 5km쯤에서 그걸 만난다`. **GATE** CONCEPT-ONLY.

### P6 — 목줄 텐션 · the most accurate picture of what we sell
**ROLE** the product, drawn without the product. **IDEA** A taut leash means the run hasn't happened yet.
```
Extreme macro, very shallow depth of field, on a taut nylon leash under real load —
individual fibres visible, dawn backlight rimming the cord, tiny fibre ends catching
the sun, everything else dissolved to bokeh. The tension is legible in the material.
```
Second frame, same setup, cord gone slack and falling into a soft J-curve, one dust mote drifting off it.
**TYPE** frame 1 `팽팽함 = 아직 안 뛴 에너지` · frame 2 `느슨함`.
**GATE** **shoot this for real.** A phone and a leash. Nothing here needs a generator, and one honest
macro is what stops the whole account reading as a render farm.

### P7 — 크루 라인업 · the team photo nobody has taken
**ROLE** runner recruitment identity. **IDEA** Compose it like a football club, not a pet meetup.
```
Backlit dawn line-up shot from a low ground angle on a long lens: five Korean runners
in plain volt bibs standing shoulder to shoulder across the frame on a Han River path,
one mid-size dog sitting squarely beside each of them, river mist behind, sun flaring
between the bodies. Composed with the flat symmetry and eye-line discipline of a
professional squad photograph. Nobody smiling for the camera.
```
**TYPE** lower left, `출근 말고, 출주`. **GATE** REPLACE-WHEN-REAL — the day 1기 is certified this
becomes a real photograph, and the AI version is deleted, not archived.

### P8 — 문 앞에 남는 심장 · the frame every owner already owns
**ROLE** guilt → relief. **IDEA** Shoot at dog-eye height and it stops being an ad.
```
Locked-off shot at 40cm off the floor, from inside a Korean apartment entryway at 6am.
The front door closing to a narrowing vertical slit of stairwell light; a dog's face
held in that slit, ears up, completely still. Cold blue interior, one warm sliver from
outside. Nothing else in frame.
```
Second frame: the identical setup reversed — slit widening, a volt leash entering.
**TYPE** frame 1 `매일 아침, 문 앞에 남는 심장이 있다` · frame 2 `오늘은 아니고요`.
**GATE** CONCEPT-ONLY. **Never publish frame 1 without frame 2.** Sadness that doesn't resolve is
emotional extraction, and it is beneath the brand.

### P9 — 다 쓴 개 · the result, stated plainly
**ROLE** the promise, as a noun. **IDEA** What the customer is actually buying is a sleeping dog.
```
Minimal studio, seamless mid-grey backdrop, one large soft key from high left. A
mid-size Korean dog lying flat out on its side on a clean floor, utterly spent, chest
mid-breath, one paw extended, eyes half closed. Volt bandana loose at the neck. No
props, no styling, no set dressing. The dignity of an athlete after the session.
```
**TYPE** `지친 개, 조용한 저녁.` **GATE** CONCEPT-ONLY.

### P10 — 터널 스프린트 · night flash home base
**ROLE** the recurring look. **IDEA** 9pm on a wet street, not golden hour on a lawn.
```
Direct hard on-camera flash at night inside a ribbed concrete underpass. A Korean
runner and a mid-size dog sprinting straight at the lens, both crisp and a half-stop
hot against a background fallen to near-black, wet floor behaving like a mirror,
rear-curtain drag smearing the limbs while the torsos stay frozen, flash falloff
vignetting the frame edges. Volt bandana burning out of the dark. 20mm, low, close.
```
**TYPE** none, or `산책 말고, 러닝.` **GATE** CONCEPT-ONLY.

### P11 — 뒤집힌 배번호 · scarcity as policy
**ROLE** the threshold post. **IDEA** Show the people who didn't make it.
```
Top-down on a cream concrete floor: a grid of race bibs laid out in rows, most face
down and blank, a few flipped face up. One stopwatch resting on the corner of a
face-up bib. Hard morning side light, long bib shadows. Nothing else in frame.
```
**TYPE** `통과 기준 4` + the four criteria. **GATE** CONCEPT-ONLY.
⚠ Bib numbers are vector-set in post — a hallucinated digit on a certification asset is exactly the
kind of small lie that costs the whole position. And **no pass-rate figure until 1기 actually ends.**

### P12 — 바닥 온도 · the trust surface
**ROLE** the post that costs us revenue. **IDEA** Advertise the rule that cancels the booking.
```
Extreme macro at ground level: a dog's bare paw pad hovering one centimetre above
sun-blasted asphalt, heat shimmer distorting the background, pad texture and tarmac
aggregate equally sharp. Harsh midday overhead light. No bandana, no styling, no
accent colour anywhere. Documentary, not designed.
```
**TYPE** cream card, hairline only: `손등으로 5초. 못 버티면, 안 뜁니다.`
**GATE** **shoot for real, AI forbidden.** Trust surfaces are the one place a render is a lie about
the thing being asserted. No volt, no trace, no red.

---

## 4. VIDEO PROMPTS

### 4.1 The production law: image-to-video, always

**Never text-to-video for a campaign frame.** Generate the still first, approve it, then animate that
exact still. Three reasons, all practical:

1. **Casting continuity.** Text-to-video recasts the dog every clip. Image-to-video cannot.
2. **The grade holds.** Light and colour are decided once, in the still, where they are cheap to fix.
3. **You reject early.** A bad still costs seconds; a bad clip costs a render.

Consequence: every §3 image is also a video source plate, and the prompts below describe **motion
applied to an approved plate** — never a new scene.

### 4.2 The rejection checklist (dog motion breaks in specific, predictable ways)

Play every clip at 0.25× before it goes anywhere near an edit. Reject on any one of these:

| Tell | Why it happens |
|---|---|
| Paw count changes mid-stride, or a leg appears/vanishes on a fast cut | occlusion during the gait cycle |
| The gait morphs — trot melting into a canter without a transition | no physical model of quadruped gait |
| The leash detaches, floats, passes through a limb, or changes length | leashes are thin and get resampled per frame |
| A second tail, or the tail crossing the body impossibly | |
| Eye glow / retroreflective shine appears in low light | model priors from flash pet photography |
| The dog's face drifts toward a human expression on a long hold | keep dog holds under 2s |
| The volt bandana changes colour, side, or disappears | one accent, re-check it every clip |

**Keep every clip at or under 3 seconds.** R1's longest cut is 3.0s and most are 1.5–2.5s. That is
not only rhythm — it is under the horizon where generated quadruped motion falls apart.

### 4.3 R1 「두 개의 심장」 30초 마스터 — per-cut motion prompts

Shot list, on-screen Korean, and sound are already locked in `reel-scripts.md` §1. This adds only the
generation instruction per cut. Source plate in brackets.

| # | s | Plate | Motion prompt |
|---|---|---|---|
| 1 | 1.5 | P2 | `Locked-off macro. The paw completes its strike and the water crown expands outward in slow motion, droplets separating. Camera does not move. No other motion in frame.` |
| 2 | 1.5 | P3 | `Identical locked-off macro, identical timing. The shoe strikes and the same crown expands. Match the first clip's water beat exactly.` |
| 3 | 2.0 | new plate | `Camera tracks laterally at running speed, 5cm off the ground, held level. Human legs and dog legs cross through frame in alternating rhythm. Motion blur on the background only; the near legs stay readable.` |
| 4 | 2.0 | new plate | `Static low camera between a runner's legs. The dog enters frame from behind and passes through the gap toward the lens. Shallow depth holds focus on the dog as it arrives.` |
| 5 | 2.5 | P1 | `Locked top-down. Only the two shadows move, sliding across the bridge stripes at a constant cadence. Absolutely nothing else in frame changes.` |
| 6 | 2.0 | P4 | `Long lens, near-locked. The dog's jaw works with the panting rhythm, breath vapor pulses, the bandana edge flutters. Under two seconds of hold.` |
| 7 | 2.0 | P5 | `Identical lens and framing. The runner exhales once, a sweat bead moves at the temple. Match cut to the previous clip's rhythm.` |
| 8 | 1.5 | P6-taut | `Extreme macro, static. The nylon fibres vibrate under load, the cord flexes minutely. No camera move.` |
| 9 | 2.0 | P10 | `Low tracking, slight dutch tilt, moving with the pair. Bandana snapping in the airflow. Background streaks; the two subjects stay locked.` |
| 10 | 2.0 | P10 alt | `Whip pan in the opposite direction resolving onto the same two bodies from the far side. The whip is the transition.` |
| 11 | 2.5 | new plate | `Backlit silhouette long shot across haze on the water. The pair crosses frame left to right, small in a wide field. Slow, steady, no camera move.` |
| 12 | 2.5 | P1 | `Same locked top-down as cut 5. The two shadows converge and overlap at frame centre, then hold. Freeze the motion on the overlap for 0.4 seconds.` |
| 13 | 3.0 | P6-slack | `240fps slow motion macro. The cord goes slack and falls into a soft J-curve. One dust mote drifts off it. Nothing else moves.` |
| 14 | — | vector | **Not generated.** Wordmark card, built in After Effects. |

**Sound is designed, never generated.** Brand signature = human exhale + dog panting, two layers, and
breath always precedes music. Music specified by energy and BPM only (176 BPM, minimal 4/4, no
melody), sourced from a royalty-free subscription — **mandatory for anything that will be boosted**,
since a trending track strips out at ad delivery and ships a silent ad.

### 4.4 Six standalone clips

Each is a full brief. 9:16, 1080×1920, ≤3s per generated shot, safe area top 120px / bottom 320px.

**V1 · 느슨해지는 줄** (보호자 · 8s · the one to make first)
Plate P6. Two clips: taut macro (2s) → slack fall in slow motion (3s) → cream type card (3s).
`Extreme macro, static camera, shallow depth. Clip A: nylon fibres under tension, minute flex, backlight rimming the cord. Clip B: the cord releases and falls into a soft curve at 240fps, a single dust particle lifting off it.`
On-screen: `줄이 팽팽한 건, 아직 안 뛰었다는 뜻입니다.` **Shoot it for real.** Phone, leash, five minutes.

**V2 · 두 개의 그림자** (양 · 6s)
Plate P1. `Locked top-down aerial. Two long shadows — one human, one dog — run side by side across bridge-shadow stripes, converge at frame centre, and hold overlapped. No camera movement whatsoever.`
On-screen: `보폭은 달라도, 박자는 같다.`

**V3 · 매치컷** (보호자 · 6s)
Plates P4 → P5. `Two clips, identical lens and crop. A: a dog's face deep in effort, jaw loose, breath vapor, 2s hold. B: a runner's face in the same state, same framing, 2s hold. Cut on the eye line.`
On-screen: `개는 평생 못 만난다` → `어제까진.`

**V4 · 문** (보호자 · 8s)
Plates P8 a/b. `Locked-off at 40cm floor height. Clip A: the door closes to a narrowing slit of light with a dog's face held in it, the slit thinning to nothing. Clip B: identical frame reversed, the slit widening, a volt leash entering.`
On-screen: `매일 아침, 문 앞에 남는 심장이 있다` → `오늘은 아니고요`. **Never ship A without B.**

**V5 · 라인업** (러너 · 5s)
Plate P7. `Near-static long lens. The line of runners and dogs holds; only mist drifts, bibs flutter, and one dog shifts its weight. The stillness is the point.`
On-screen: `출근 말고, 출주.` No earnings copy in this one — identity and money in the same frame makes it a job ad.

**V6 · 터널** (양 · 6s)
Plate P10. `Hard-flash night look. The pair sprints straight at the lens through a ribbed underpass, wet floor mirroring, rear-curtain drag smearing limbs while the torsos stay frozen. Camera static, low, 20mm.`
On-screen: `산책 말고, 러닝.`

### 4.5 What must never be generated, in motion or still

| | Why |
|---|---|
| **바디캠 POV footage** | The dead centre of the line. Shoot it with a real action cam on a consenting owner's dog, harness mount only. |
| **GPS trails, route lines, map overlays** | §2.2 — vector from a real GPX, or absent. |
| **App screens, 체력나이 cards, any number** | Real capture or a vector mockup labelled as one. |
| **Customer dogs, testimonials, finisher photos, certified-runner portraits** | Zero customers. These exist the day they exist. |
| **Real athletes or celebrities** | We own a concept; we do not rent a person. |
| **Trust surfaces** (노면 온도, 안전 기준, 가격, 인증 기준, 인계) | A render asserting a safety rule is a lie about the rule. |

---

## 5. Production order

Nothing here needs a budget; it needs a sequence.

1. **V1 목줄 텐션, shot for real.** Zero AI, one phone, today. It is what makes everything after it
   believable — nine generated tiles with no real footage anywhere reads as a render farm.
2. **P1 + P2/P3 + R1.** The campaign's definition. P1 alone explains the whole idea, and every other
   asset is a footnote to that film.
3. **P7 + P11 + V5.** Supply is the bottleneck. The recruitment set is the only one that changes a
   number that matters in the next 30 days.
4. **P12 바닥 온도, shot for real.** The post that costs us revenue is the one that earns the trust.

Everything else is optional this season. A frame nobody has time to make is not a frame.
