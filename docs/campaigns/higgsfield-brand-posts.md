# 도그스하이 — Higgsfield brand-post campaign (poster season v4)

*Written 2026-08-24. Companion to `docs/campaigns/generation-prompts.md` (v3.1) and
`docs/instagram/prompt-library.md` (§0 gates unchanged and still binding). This file exists because
Sean picked six finished posts as the reference set for the next drop — the "poster" look — and asked
for a creative recreation generated through the **Higgsfield MCP**.*

**Status of the tooling:** the official Higgsfield MCP is registered at user scope
(`claude mcp add --transport http --scope user higgsfield https://mcp.higgsfield.ai/mcp`, done
2026-08-24). It authenticates by browser OAuth — **one-time, Sean, via `/mcp` in an interactive
session** — after which any session can call `generate_image` (Soul, GPT Image, Flux, Nano Banana
et al.) and `generate_video` directly. Until that OAuth happens, every prompt below is also
paste-ready on higgsfield.ai by hand.

---

## 0. The six reference posts, codified

The reference set (Sean, 2026-08-24: "attached images are some of the posts that i think are nice"):

| Ref | Look | Type voice |
|---|---|---|
| BORN TO RUN | dusk-ridge silhouette, one clean sky field, violet trace + pace block | editorial serif, white, masthead |
| CHASE THAT HIGH. | street doc, raking light on stone, compressed profile | condensed grotesque italic, stacked, white + red pay-off word |
| RUN THAT LIFE. | on-camera flash on film, post-run candid, wet dog | condensed stacked, red + white alternating |
| Two Hearts. One Race. | overcast editorial calm, muted film grade | quiet serif + tiny red kicker |
| 도그스하이 (yellow) | panning motion blur, night street crew | Korean graffiti display, volt-yellow, + yellow route outline |
| YOUR FASTEST FRIEND. / MY RUN MATE | sprinkler chaos wide · direct-flash portrait | condensed heavy, white with one red word |

What the set actually does — this is the v4 system:

1. **Three type voices, three temperatures.** Editorial serif (calm, filmic) · condensed grotesque,
   often italic (loud, sport) · Korean graffiti display (street, crew). One voice per frame, never
   mixed.
2. **Red is the pay-off.** One word (or one line) of the stack flips to brand red `#E8352A`; the
   rest stays white/cream. Red never appears as an object in frame.
3. **The violet route trace survives from v3.1** and its law is UNCHANGED: vector, plotted from a
   real GPX, with readouts only from that same file. §2.2 of `generation-prompts.md` governs.
4. **The wordmark + running-dog logo are vector overlays.** Never generated — generators drift the
   letterforms and the mark (prompt-library §0.1). Source: `docs/brand/dogshigh-icon-a-1024.png` +
   the 도그스하이 lockup.
5. **English display lines join the system.** 2–4 words, athlete's verb, period. Korean carries the
   caption and the graffiti colorway. (v3.1 was Korean-display-first; the six refs Sean picked are
   English-display-first. Codified here, flagged in §5-A.)

⚠ **Deltas from v3.1's accent law, stated honestly rather than papered over:** the reference posts
do not wear volt on the dog (harnesses are peach/olive/black), and volt-yellow appears as a *type
colorway* in the 도그스하이 post. v4 as written follows the refs: gear color is quiet and free,
volt is the Korean-graffiti colorway only, red owns the pay-off, violet owns the trace. If Sean
wants the volt-on-dog law back, that is §5-A option B and only the PROMPT blocks change.

**Unchanged and still absolute** (from prompt-library §0.2 + generation-prompts §2.2):
- Honesty gate — every post below is brand-world/concept and captions as such (컨셉/예고). No
  implied customer, no implied delivered run. AI event imagery expires the day the real event runs.
- **No generated GPS lines, no generated numbers, ever.** Trace + pace/km blocks go on in post,
  from a real GPX or not at all.
- No real athlete or celebrity, no sportswear logos, inspect at 100% before trusting any frame
  (logo contamination is invisible at thumbnail scale — measured, §2.6 of generation-prompts.md).

---

## 1. Higgsfield operating notes

- **Default model: Soul** — it is the reason to use Higgsfield at all; its stylized-realism grades
  (film flash, editorial muted, motion pan) map 1:1 onto the six refs. Use **GPT Image (via
  Higgsfield)** only when type must be generated in-frame (route 1), because Soul, like MJ/Flux,
  breaks Hangul. **Flux** for the two macro/texture frames.
- **Aspect:** 4:5 feed · 9:16 story. Generate 4:5 masters; recrop, don't regenerate, for story.
- **Per-frame call shape (once OAuth is done):** `generate_image` with model + the full paste block
  below (SCENE + DNA v4 + NEGATIVE) + aspect. Batch all ten, contact-sheet them, Sean picks by
  number — he picks by looking.
- **Type route per frame** is marked R1 (generated in-frame, GPT Image, exact string quoted) or
  R2 (set in post — Figma, real fonts). English display survives R1 well; Korean display defaults
  to R2 unless marked; the wordmark/logo/numbers are ALWAYS R2 vector (law).
- Every SCENE block already reserves negative space for its type. Do not crop it away.

### 1.1 DNA v4 (paste into every prompt)

```
BASE DNA — DOGS HIGH v4 (poster season):
GRADE: one of three locked looks per frame, named in the scene block —
 (a) FILM FLASH: on-camera direct flash on 35mm color film, hard shadow edge,
     slightly lifted blacks, honest skin;
 (b) EDITORIAL MUTE: overcast soft light, desaturated film grade, unhurried;
 (c) MOTION PAN: slow-shutter panning blur, subject half-sharp, street at night.
COLOUR: restrained, one disciplined colour field per frame. No HDR, no orange-teal,
no busy multi-hue frame. Gear on dog and human stays quiet/neutral.
BODIES: genuine full athletic stride, anatomically correct running gait. The dog is
the athlete, never the pet — no sitting pretty, no head tilt, no costume, working
mouth-open effort. Leash geometry physically correct, under real load or truly slack.
ENERGY: candid documentary, mid-effort or just-after-effort. Nobody performs for
the camera. Sweat, breath, wet fur are wanted.
CASTING: Korean runners, 20s–30s, real athletic builds, no fashion-model faces.
Mid-size Korean dogs — Jindo mix, Border Collie, Welsh Corgi, retriever, shepherd mix.
TEXTURE: 35mm editorial grain, honest optical imperfection, no plastic skin, no
beauty retouch, no digital over-cleanliness.
TYPE SPACE: hold clean uncluttered negative space exactly where the scene block says.
ANIMAL EYES: any dog toward the lens has natural dark wet eyes with a single small
specular catchlight — no eye glow, no tapetum eyeshine.
```

### 1.2 Global negative (paste into every prompt; for R1 frames delete the first clause only)

```
NEGATIVE: no text anywhere in the image, no lettering, no signage, no logos, no
watermarks, no brand marks on apparel or shoes, no swoosh or any sportswear logo,
no invented shop signs; no real athlete, celebrity, or recognisable public figure;
no extra or missing limbs, no six-legged dogs, no duplicated tails, no fused paws,
no floating or detached leash, no leash passing through a body; no eye glow, no
retroreflective eyeshine; no cartoon, no illustration, no 3D render, no CGI look,
no plastic skin, no beauty retouch, no HDR, no orange-teal grade; no costumes, no
clothing on the dog beyond a bandana or harness; no sitting pretty, no begging, no
tongue-out cuteness pose; no GPS lines, no map overlays, no route graphics, no app
screens, no data readouts, no numbers; no stock-photo smiling; no crowds of onlookers.
```

---

## 2. THE TEN POSTS

Format: **ROLE** · **IDEA** · **MODEL/AR/GRADE** · **SCENE** (paste + DNA v4 + NEGATIVE) ·
**TYPE** (voice · route · exact copy) · **OVERLAY** (vector, post) · **GATE**.

### H1 — 능선의 실루엣 · the masthead poster
**ROLE** drop hero, pinned post. **IDEA** The pair as one silhouette against one clean sky — the
viewer's own mornings, projected. **MODEL** Soul · 4:5 · grade (b).
```
EDITORIAL MUTE. Low hilltop trail against a vast clean dawn sky in a single cold
blue-grey gradient, horizon low in the frame. A Korean runner in plain dark running
kit and a mid-size Jindo-mix dog, both in full silhouette on the ridge line, caught
in a walking recovery stride, the dog two paces ahead and looking back at the runner.
Dry grass and one bare branch silhouetted at the frame edge. The upper two thirds of
the sky held completely empty and clean. Long-lens compression, 35mm grain.
```
**TYPE** editorial serif, white, tracking wide, masthead across the top: `RUN BEFORE SUNRISE` (R1
via GPT Image or R2 — serif masthead survives both). **OVERLAY** violet trace + PACE/KM block mid-right
IF a real GPX exists for a dawn run; otherwise nothing (law §0). Logo + 도그스하이 lower-left.
**GATE** CONCEPT-ONLY.

### H2 — 스트리트 페이스 · the sport poster
**ROLE** grid tile 2, the loud one. **IDEA** City light falls on the pair like it falls on any
athlete at work. **MODEL** Soul · 4:5 · raking daylight (grade b, hard variant).
```
Compressed long-lens side profile on a Seoul street: one hard blade of morning sun
raking across a monumental grey stone facade, the rest of the wall in soft shadow.
A Korean woman running left-to-right through the light blade, mid-stride, crossbody
leash line to a Border Collie trotting exactly at her knee, both fully lit for one
step. Plain white tee, neutral shorts, olive harness on the dog. Wide clean shadow
field upper-left held empty. Documentary street photography, 35mm grain.
```
**TYPE** condensed grotesque italic, stacked upper-left: `EARN` / `THAT` / `HIGH.` — first two lines
white, last line red `#E8352A` (R1 via GPT Image, English survives; else R2). **OVERLAY** white logo
mark upper-right, large, à la the CHASE ref. No trace on this frame.
**GATE** CONCEPT-ONLY.

### H3 — 플래시 필름 · after the run
**ROLE** the emotional tile; pairs with H8. **IDEA** The high is what's on their faces when it's
over. **MODEL** Soul · 4:5 · grade (a).
```
FILM FLASH. Dusk in a Han River park, direct on-camera flash: two Korean runners in
their 20s crouched on the grass toweling down a soaking-wet shepherd-mix dog that is
mid-shake, water flying, tongue loose, everyone lit hard against a darkening tree
line. Genuine laughter mid-effort, not posed. Wet grass detail in flash falloff.
Right third of frame held clear of bodies for type. 35mm color film look.
```
**TYPE** condensed stacked, right third: `RUN` / `THAT` / `LIFE.` alternating red/white (R2 — this
lockup exists from the ref post; reuse it). **OVERLAY** violet trace + readout upper-right from a
real GPX or omit. Logo + 도그스하이 bottom-center.
**GATE** CONCEPT-ONLY.

### H4 — 세리프의 정적 · the quiet one
**ROLE** pace-breaker between loud tiles; carries the platform line. **IDEA** After the effort,
before the words. **MODEL** Soul · 2:3 or 4:5 · grade (b).
```
EDITORIAL MUTE. Overcast flat sky, muted film grade. A Korean man in his 30s in plain
dark running kit leans on a weathered Han River railing, one hand resting on the head
of a black retriever-mix dog sitting square beside him, both looking out at the grey
water, breath settled. Wide calm negative space in the sky across the top third.
Quiet, unhurried, nothing performing. 35mm grain, soft contrast.
```
**TYPE** quiet serif, white, centered top: `Two Hearts. One Pace.` with the tiny red kicker line
`DOG'S HIGH / 도그스하이` centered beneath it (R2 — serif + kicker is a lockup). **OVERLAY** small
logo bottom-right only. No trace.
**GATE** CONCEPT-ONLY.

### H5 — 한글 콜로웨이 · the street drop
**ROLE** the Korean-type statement tile; crew recruitment energy. **IDEA** The brand name IS the
image; the city supplies the rest. **MODEL** Soul · 9:16 master · grade (c).
```
MOTION PAN. Night street in Seoul, slow-shutter panning shot: a small crew of Korean
runners sweeps left-to-right past closed metal shutters, bodies half-sharp with
motion trails, and low in the foreground a Jindo-mix dog in full sprint extension,
sharper than the humans, collar only, no leash in this frame reading as loose
off-lead chaos — keep one runner's hand and a slack lead visibly connected to the
dog. Sodium and shutter greys, one muted red-white striped pole blurring past.
Upper-left third held as shutter-grey emptiness for large type.
```
**TYPE** Korean graffiti display, volt-yellow `#EDF356`, tilted, huge, upper-left: `도그스하이`
(R2 ONLY — Hangul display never generated). Small italic kicker bottom-left: `RUN 06 / SEOUL`
(R2; the run number is a real series index, not invented data). **OVERLAY** the yellow route
outline in the same volt — SAME LAW as violet: real GPX or nothing. White logo bottom-center.
**GATE** CONCEPT-ONLY.

### H6 — 팩 애니멀 · the chaos tile
**ROLE** reach post; the shareable one. **IDEA** Joy at pack scale — what the feed stops scrolling
for. **MODEL** Soul · 4:5 · grade (a) daylight-flash variant.
```
FILM FLASH, fill-flash against late dusk sky. Low wide-angle inside a fenced dog run:
five dogs of mixed Korean breeds — shepherd mix, black retriever, Border Collie,
Jindo mix, one Corgi — caught mid-leap and mid-shake under a sprinkler arc, water
crown backlit, grass flying, every face pointed up at the spray in working joy, not
posed cuteness. Deep blue evening sky across the top half of frame held clean for
stacked type. Hard flash catchlights, natural dark wet eyes, 35mm grain.
```
**TYPE** condensed heavy, stacked across the sky: `YOUR` / `FASTEST` / `FRIEND.` — middle word red
(R2; this lockup exists from the ref). Small `도그스하이` beneath the stack. **OVERLAY** logo
bottom-right. No trace — group frames never carry data.
**GATE** CONCEPT-ONLY.

### H7 — 플래시 포트레이트 · my pacer
**ROLE** the intimate tile; profile-picture energy. **IDEA** Dog-first portrait — the athlete gets
the hero crop, the human is furniture. **MODEL** Soul · 2:3 · grade (a).
```
FILM FLASH. Narrow apartment entryway at night, direct hard flash: a brown-and-white
Jindo-mix dog stands square between its seated owner's sneakered feet, facing the
camera dead-on with calm working eyes, single catchlight, leash clipped and slack.
The owner's legs and running shoes frame the dog; the human's face is out of frame
entirely. Textured doormat, hard flash shadows on the door behind. Top fifth of
frame held for one display word. 35mm color film.
```
**TYPE** condensed heavy white across the top: `MY` / `PACER` (R1 via GPT Image or R2). 도그스하이 +
logo small, left, under the headline. **OVERLAY** violet trace bottom-right corner IF real GPX
(the ref post carries exactly this placement); readout only from the same file.
**GATE** CONCEPT-ONLY.

### H8 — 다 쓴 개 · the result
**ROLE** conversion tile; what the customer is buying. **IDEA** A spent dog is the product shot.
**MODEL** Flux (texture) or Soul · 4:5 · grade (b) warm-interior variant.
```
Locked-off frame at floor level in a Korean apartment living room at night, one warm
practical lamp: a shepherd-mix dog lies flat out on its side on the wood floor,
utterly spent, chest mid-breath, one paw extended, eyes half closed — the dignity of
an athlete after the session, not a sad dog. A slack leash and harness dropped in
soft focus behind. Everything else minimal. Left third held in lamp-warm emptiness.
```
**TYPE** quiet serif OR condensed light, cream, left third: `GOOD KIND` / `OF TIRED.` (R2).
**OVERLAY** none. This is the frame that needs nothing.
**GATE** CONCEPT-ONLY.

### H9 — 다리 아래 · the monument
**ROLE** scale tile; the one that says Seoul without a landmark. **IDEA** Two small figures, one
huge honest city. **MODEL** Soul · 4:5 · grade (b) pre-dawn variant.
```
EDITORIAL MUTE, pre-dawn blue hour. Ultra-wide from low under a massive concrete Han
River bridge deck, rhythmic pillars receding, the river steel-grey: tiny in the
middle distance, one Korean runner and one mid-size dog run in step along the empty
riverside path, the only motion in the frame. Monumental negative space across the
concrete deck above holds clean for a masthead. Cold restraint, 35mm grain.
```
**TYPE** editorial serif white masthead on the bridge deck: `FIRST LIGHT CLUB` (R1/R2). **OVERLAY**
violet trace along the lower edge if a real GPX exists; logo bottom-left.
**GATE** CONCEPT-ONLY.

### H10 — 우천 결행 · all-weather animal
**ROLE** the values tile — we publish our own no-run thresholds, and below them, we run. **IDEA**
Rain is not a cancellation; it's a grade. **MODEL** Soul · 4:5 · grade (a) night-rain variant.
```
FILM FLASH at night in light rain: a Korean runner and a Border Collie mid-stride
through a crosswalk, flash freezing the raindrops into bright streaks, wet asphalt
mirroring the pair, dog's coat slicked and dark, both mouths open working, leash
under honest load. Background city bokeh crushed dark. Bottom quarter of the wet
asphalt reflection zone held for type.
```
**TYPE** condensed italic across the bottom: `ALL-WEATHER` / `ANIMAL.` second line red (R2).
Caption carries the honesty hook: the real 기상 threshold table link — 우천 결행은 기준 이하일 때만.
**OVERLAY** none.
**GATE** CONCEPT-ONLY. Caption must state the real no-run thresholds exist and where they live.

---

## 3. Rollout & captions

Suggested order (loud–quiet alternation, hero first): **H1 → H2 → H6 → H4 → H5 → H3 → H7 → H10 →
H9 → H8.** Every caption reads as 컨셉/예고 (honesty gate): the service line is "곧, 반포에서" — no
implied customers, no implied completed runs. Korean captions; English display stays in the image.

Story crops: H1, H5 (native 9:16), H2, H10. The trace/readout, when a GPX exists, goes on the story
crop too — same file, same numbers.

## 4. Production checklist (per frame, before it may publish)

1. 100% zoom sweep: glyphs (if R1), logos on apparel/shoes, limb/paw count, leash continuity, eyes.
2. Type: real fonts for R2; R1 only for English display, proofread letterforms.
3. Wordmark + running-dog logo overlaid as vector, never generated.
4. Trace/readout: from a real GPX or absent. No exceptions, including "plausible" numbers.
5. Caption gated: 컨셉/예고 framing present.
6. File into the campaign folder with its H-number; Sean picks by number.

## 5. Decisions — RULED (Sean, 2026-08-24)

Sean: "the purple color is fine. both korean and english is fine. no need for real runs."
[end of his words]

- **A → v4 codified as written.** Violet trace stands; volt-on-dog law is not restored for this
  season.
- **B → both.** English and Korean display both in the system, per frame as specced.
- **C → no real runs required.** ⚠ This knowingly relaxes generation-prompts.md §2.2 for THIS
  CAMPAIGN: the trace and pace/km blocks may be designed rather than plotted from a GPX. They are
  still vector overlays set in post (never generated in-frame — generators draw mush), and every
  post still captions as 컨셉/예고 under the honesty gate. Product surfaces (app screens, 체력나이,
  earnings) remain under the absolute no-fabrication rule — this ruling covers brand posters only.
- **D → done differently and better.** Sean routed setup through the official CLI instead of the
  MCP: `@higgsfield/cli` installed globally (bin at `/Users/sean/.local/node/bin/higgsfield`; that
  dir may be off a session's PATH — use the absolute path), OAuth completed 2026-08-24, workspace
  `5af4abde` (Private, plus plan) selected, and the 8 `higgsfield-*` companion skills installed into
  `.agents/skills/` + `.claude/skills/`. The MCP registration from earlier today also stands.

## 6. Smoke test findings (H2, Soul 2.0, 2026-08-24 — job 38e635eb)

Result: `higgsfield-out/H2-smoke-test.png`. The grade, light blade, compression, gait and harness
all landed first try. Measured facts for the batch run:

1. **Soul ignores logo bans in the negative block.** The smoke frame put a Nike swoosh on BOTH
   shoes despite `no swoosh or any sportswear logo` in the prompt. Fix: state it POSITIVELY in
   every scene block with visible feet/apparel — `plain unbranded running shoes and apparel, blank
   logo-free gear` — and keep the 100%-zoom sweep (§4.1) as the real gate. An edit-model pass
   (Flux Kontext / Nano Banana) can de-logo a keeper frame.
2. **Soul has no 4:5.** Options: 1:1, 16:9, 9:16, 4:3, 3:4, 3:2, 2:3. Use **3:4** for feed masters,
   9:16 for story natives; crop 3:4 → 4:5 in post.
3. **Cost: 0.12 credits per Soul frame at 2k.** The whole ten-post set with variants is ~₩0-scale
   against the 1,210-credit balance.
4. CLI shape that works: `higgsfield generate create text2image_soul_v2 --prompt "<scene + DNA +
   negative>" --aspect-ratio 3:4 --json`, then `generate wait <id>` and curl `result_url`.

## 7. Batch 1 (28 frames, 2026-08-24) — measured findings

Sean's direction for the batch: "be extremely creative with angles, context, aesthetic, but they
all must be trendy and deliver the same core nike hard effort wannabe culture" [end of his words].
14 concepts (B01–B14) × 2 variants, Soul 2.0, 3:4, ~3.4 credits. Frames in
`higgsfield-out/batch1/`; prompts archived in the session scratchpad and re-derivable from §2's
scene blocks. Contact sheet artifact:
<https://claude.ai/code/artifact/7b378c23-a4c1-4212-b6c9-ad64a7b657d6>

1. **Soul's prior is marathon-culture-coded, and "hard effort" language amplifies it.** Asking for
   grind/race energy pulls race bibs WITH invented text, swooshes on caps/shoes/shorts — one frame
   painted a giant swoosh on a tunnel wall — and clothing on dogs. Negatives do not stop it;
   positive "plain unbranded" language reduces but does not eliminate it.
2. **The pipeline therefore has a mandatory de-branding stage:** pick → edit-model pass (Nano
   Banana Pro / Flux Kontext: remove logos, bib text, dog clothing; ~0.1–0.2 credits) → the §4
   100%-zoom sweep → type/wordmark/trace in post. No batch-1 frame publishes raw.
3. Plus-plan concurrency is **8 jobs**; a submit loop must throttle and also survive transient
   `Not authenticated` CLI errors (token-refresh race under parallel calls — retry succeeds).
4. Operational limits (2026-08-24): `plus` plan, 1,210 credits at start; a 28-frame batch ran
   end-to-end in ~15 minutes including throttling.

## 8. Round 2 (2026-08-24) — picks, finished posters, model verdict

**Sean's picks from batch 1** (in B01–B14 order): "1, 2, none, none (dog is facing the other way),
2, both, 2 (but remove the logos), both, 1, either( remove logos), 1, none (stairs dont make
sense), 1, none. be more creative, different lenses, story, add slogans, add the route traces for
some ... is this the best image model? also, make sure not to have logos and be more creative in
the posters." [end of his words] Plus mid-round: "trace is too small. ill add the brand logo
manually" [end of his words].

**What ran:** 12 picked plates de-branded via `nano_banana_pro` image edit (2 credits each —
removed every swoosh/bib/dog-vest while holding faces, poses, light; verified on contact). Then a
local deterministic finishing pass (PIL + real Anton/Oswald/Black Han Sans/Playfair from Google
Fonts) composited slogans and violet street-style route traces + pace blocks — **no logo overlays,
per Sean's ruling; he places the mark manually.** Finished posters:
`higgsfield-out/posters/P-*.jpg`. Slogan ledger: B01 RUN BEFORE SUNRISE · B02 EARN THAT HIGH. ·
B05 OUT OF THE DARK. · B06 diptych NOBODY'S WATCHING. → GOOD. · B07 오늘도, 간다 · B08 LEFT IT ALL
OUT. / ASK THE DOG WHO WON. · B09 PACK ANIMALS. · B10 ALL-WEATHER ANIMAL. · B11 FIRST LIGHT CLUB ·
B13 GOOD KIND OF TIRED.

**New concepts** (batch2, replacing rejected B03/B04/B12/B14): N1 fisheye vault · N2 drone
crosswalk · N3 long-exposure ghosts · N4 convenience-store window · N5 elevator mirror · N6 palace
wall · B04R stair reshoot (direction fixed). Findings: **N3 failed twice** — Soul cannot render
translucent long-exposure motion ghosts, it produces panned runners instead; the marathon prior
still injects bibs/logos into new frames despite v4.2's positive language, so the de-brand stage
stays mandatory for every pick.

## 8-bis. Round 3 (2026-08-24) — garment logos, trace v3, 30 more

Sean's round-3 rulings (paraphrased; full text in session): smoother traces, clear of subjects,
Strava-style DISTANCE/PACE cards (B06B fixed at 5.4 km · 8:12, his numbers); **the 도그스하이 mark
is now painted realistically onto runners' clothing in-image** — done via `nano_banana_pro` with
`app/assets/logo.png` passed as an `--image-references` second input ("print this exact logo,
white on dark garments, black on light"), which held the mark's shape across 17 edits including
all four crew shirts in one pass; PACK ANIMALS. → **EVERY DAMN DAWN.** and ALL-WEATHER ANIMAL. →
**RUN THE RAIN.**; B11 rebuilt (backpack removed, dog swapped to a golden retriever in gallop —
one semantic edit, worked first try); N1-v2 eye and Seedream-N1 anatomy repaired by targeted edits.

Trace v3: irregular polygon + one spur, corners softened with two Chaikin passes + white start
dot — reads as streets, not spikes, not blobs. Strava card: DISTANCE/PACE small-cap labels,
Oswald numerals, violet pace.

30 new concepts (S01–S30) generated; **four misfired as collages (S12 eye-macro, S13 curb-edge,
S18 bus-window, S22 ice-bath) — Soul collages multi-panel when a prompt describes two disjoint
scales/framings in one image.** Marathon-prior contamination persists on raw frames; the de-brand
stage remains mandatory per pick. Credits after three rounds + edits: 822 of 1,210 remain.

**Model verdict (measured, not vibes):** For this campaign's flash/editorial sport look, **Soul
2.0 is the right primary** — its grain, flash falloff and body dynamics carry the whole aesthetic
at 0.12 credits/frame. **Seedream 5 Pro** (2 credits) is the strong second: cleaner and calmer,
and it *won* the N4 store-window A/B (moodier interior, better window story) while losing N1
(less dynamic dog). Use Seedream for quiet cinematic frames, Soul for everything kinetic,
**Nano Banana Pro** for edits/de-branding, GPT Image for type-in-frame. No single model wins all
three jobs; the pipeline is the answer.
