# Handoff: the desktop bench's look since 11-03, for IR Capture (2026-11-09)

From the desktop bench project (repo 0x5E3/desktop-bench, branch `look`, 193rd/194th desktop chat) to the Claude working
on **IR Capture** (repo 0x5E3/IR-Capture), and to Lowell.

This follows the first handoff, `handoffs/HANDOFF-desktop-to-ircapture.md` (2026-11-03; a copy is in IR-Capture's
`preview/workshop-look` branch at `docs/design/`). Everything in it still stands except where this note says otherwise.
The bench's look has changed a lot since then. Lowell, 11-09: "I want the programs to match. So the lighting as well as
the lossless renders and quality/motion stuff ... help me help that project look as nice as this one." The work on IR
Capture's side is yours. This note is what changed, where IR Capture stands against it, and what to do.

Marked **rule** (Lowell's own words or a standing call in the bench project) or **suggestion** (Claude's, his to change).

---

## 0. In short

1. **One light colour, white, everywhere.** On the bench, the frame's warm 3200 K light was made white (11-08). IR
   Capture's own pieces were already in a white studio, but the 65 pieces it took from the bench's 11-03 kit (`frame-*`,
   `rack-*`, `audio-*`) are in the old warm light. Inside one IR Capture window, the two lights sit side by side.
2. **Lossless, every picture.** All 246 pictures in IR Capture's `Resources/SwellKit/pictures` are lossy WebP (checked
   chunk by chunk: 246 VP8, 0 VP8L). The bench has written only lossless since 11-06.
3. **Materials moved on.** The liquid hammertone replaced the porous cells. The rough, unlacquered shop wood replaced the
   lacquered oak. Polished parts mirror a workshop room. Enamel panels got back their top light. IR Capture's own
   pieces still use the 11-03/04 versions (`hammertone_fine`, `_oak_top`/`oak_material`).
4. **Screens never washed out, no domed glass.** IR Capture's own pieces use `TK.flat_faces`, so they're fine. The
   bench's NAM loader glass it borrowed was domed, and is fixed in a queued render.
5. **Motion.** The bench now moves the way real parts move: knobs and magic eyes blended between sprite frames, lamps by
   kind, VU needles with real ballistics, motors that spin up and coast down, and one power-on clock that everything warms
   from. Nothing animates while nothing changes. IR Capture has some of this (the reels' speed model is good) and lacks
   the rest (§2).

---

## 1. What changed on the bench since 11-03

### 1.1 Light: two scenes, one colour (rule)

Lowell, 11-08: "if anything looks funny like a changed light source between scenes or settings—I really don't want
that. Now, if some render scenes have a softer light source that's the same shape and location essentially—I'm guessing
that's ok." On the preview of the frame cooled against the rig warmed (11-08 17:00): **"I like the frame cooled."** And
17:01: **"Not only lossless…but the right light color too btw."**

The bench has exactly two render scenes (audited in the 179th chat, HISTORY.md "The hundred-and-seventy-ninth chat"):

- **The rig's and instruments' studio.** `rig_scene.lights` is word for word `gear_kit.stage`'s studio, and
  `toolkit.scene()` calls `gear_kit.stage` (so does every IR Capture piece). Its lights are area lights in units of
  `k = 5.6`:
  - keyL at (-24k, 24k, 30k), 12k wide, power 6000·k²·0.9;
  - topL at (-3k, 5k, 45k), 26k by 12k, 2600·k²·0.9;
  - fillL at (28k, -24k, 22k), 420·k²;
  - `over` behind;
  - reflection-only emitter cards (key, top, rim, ceil, side), seen by glossy rays only;
  - a dim world, (0.004, 0.004, 0.005) to (0.05, 0.05, 0.052).

  The light is white. AgX, look "AgX - Medium High Contrast". Exposure 0.6 on the rig (`rig_scene.EXPOSURE`) and 0.35
  in the Tools kit (`toolkit.EXPOSURE`, `TK_EXPOSURE`). Orthographic, 10 degrees down.
- **The frame's scene, `frame_camera.lights`.** Four suns, so a piece lights the same wherever on the wall it's tiled:
  - key from `KEY_FROM` (-170, 150, 260), strength 2.4, 12 degrees;
  - wash from (0, 1, 0.25), 0.9, 20 degrees;
  - fill from (190, -120, 240), 0.45, 30 degrees;
  - bounce from (0, -1, 0.35), 0.22, 60 degrees.

  **Since the 180th chat (commit 1dc6dcb, 11-08) all four are white**, each at the luminance its old colour had:
  `WARM = (0.828,)*3` (was (1.0, 0.80, 0.60)) and `COOL = (0.695,)*3` (was (0.62, 0.70, 0.86)). The world is neutral at
  0.0018 to 0.0103. `FRAME_WARM=1` brings back the old warm frame. Everything that calls `FC.lights` changes with it:
  frame_wall, rack, eqpanel, strobe, toolshelf, **shelf_gear**, shelf_wear, roller, hammer_swatch. The practical glows
  (lit keys' `kglow`/`lglow`, the nixies' `tubelight`) keep their own colours.
- **Measured on reference balls** (`tools/light_spheres.py`): the key comes from the same place in both scenes, within
  about 8 degrees. The rig's is softer. The 18 % grey ball's lit quarter read (102, 102, 102) in the rig and
  (138, 124, 108) in the old warm frame. After the change, a Solver proof held its brightness (luminance about 100
  against 111, of which 0.9 is its darker paint) and its grey enamel read its own cool blue-grey.

**For IR Capture:** your pieces from `ircapture_kit.py` and `ircapture_tape*.py` are all `TK.scene()`, the white
studio, so their light is right. The bench pieces you took on 11-03 (`frame-*` 35, `rack-*` 29, `audio-*` 2) were
rendered in the warm frame light. `rlamp-*` (36) and `namdev-*` (18) are from the rig's scene: white, but older models
(below). The `ircapture_tape.py` "well" light (`#ffe2b0`) and the cart's "throat" light (`#ffdcb0`) are practicals
inside a part. Those are fine, as on the bench, as long as they light only the inside of the part.

### 1.2 Lossless (rule)

Lowell, 11-06: "Why not 100%? Does anyone care about disk space?"; then "Ya LFS". And 11-08: "make sure every single
page, the rig, the bench, tools, all subpages etc, everything is lossless quality".

Why: lossy WebP keeps colour at half resolution at any quality. Measured on a red flake crop: q86 34 dB, q100 37 dB,
lossless exact. Lossless files are 2.5 to 5 times q86's bytes.

On the bench (HISTORY.md, 156th and 157th chats):
- **`design/render/webp_out.py`** is imported by every post script, one line after the PIL import. It wraps PIL's
  `Image.save` so every WebP written (by path or to a BytesIO) is `lossless=True, exact=True` (exact RGB under
  transparent pixels), whatever quality the script asks. `WEBP_EFFORT` is 90 (PIL's `quality` on a lossless file is
  effort) and `WEBP_METHOD` 4. Measured: 1.0 s against 7.2 s for 100/6 on 2000 × 1500, bytes within 0.2 %, and the pixels
  are exact either way. `POST_LOSSY=1` brings back the old lossy settings.
- **Pictures live in Git LFS** (`.gitattributes`: `apps/plugin/page/views/*.webp`). The build workflow's checkouts use
  `lfs: true`; the macOS job installs git-lfs if the Mac's git lacks it.
- **Derived densities:** a lossy 1x or @2x whose @3x (else @2x) is lossless and a whole multiple of its size is remade as
  a premultiplied Lanczos downsample, written lossless (`tools/derive_lossless.py`). It's left alone if it differs by
  more than 12/255 from the picture it replaces: a different render, not just compression noise.
- **Check:** walk the RIFF chunks; `VP8L` is lossless and `VP8 ` is lossy. The bench's count was 5,563 pictures, 3,333
  of them lossy on 11-08. Re-renders and re-posts are taking that to zero.
- **Density:** the bench draws at up to about 2.2 device px per picture px on Lowell's 5K iMac. Bodies get @2x, and knobs
  and switches @3x at 150 px/cm (156th chat). Lowell called the old ones "soft ... blurry ... out of focus".

### 1.3 Sharpness (rule for the rig, suggestion for you)

`rig_scene.setup` sets Cycles' pixel filter to **1.0 px** (Blender's default 1.5 px softened every sprite before the page
scaled it; `RIG_FILTER=1.5` is the old). **`gear_kit.stage` (so `toolkit.scene()`, and every IR Capture piece) does not
set it, and renders at 1.5 px.** Suggestion: set `s.cycles.filter_width = 1.0` in your scripts after `TK.scene()` (or
`TK_FILTER`), as the rig does. The bench's own Tools kit has the same 1.5 px today. That's for the bench to fix too, and
it's noted here.

### 1.4 Screens and glass: never washed out, no domes (rule)

Lowell, 11-08: "I don't want the light to wash out anything on EQ screen or the tuner screen ... it's already washing out
the IR screens and the solver screens too much. Or those screens are just domed or something ... I don't think I really
want much if any doming"; and on the Dymo labels: "Labels too domed as well, washed out".

- **Root cause found:** `gear_kit.rbox` shades every face smooth. With no `chamfer()` (or `flat_faces`) after it, a big
  flat face takes its normals from the rounded rim and shades as a dome. Fixed on the bench in `gas_disp.py` (pane
  chamfered, roughness 0.03), `namdevice.py`'s glass, and `modbox.py`'s Dymo strips (flat, roughness 0.15).
- **Screens the page lights** (EQ, strobe) render black; the page draws the light. A glass window that a studio card or
  the key softbox reflects into gets those lights light-linked away from that glass only
  (`deck_whole.unlink_cards`, 181st chat: the scope's LCD had mirrored the key at 125/255).
- **A see-through button over a picture must have no `box-shadow`.** The page's default button highlight drew a 1 px
  pale line over every Dymo label (`views/modbox.css`). In SwiftUI the same trap is an overlay or a `ButtonStyle` adding
  a highlight or stroke over a rendered window.

**For IR Capture:** your own scripts call `TK.flat_faces` after each `rbox` (case, plate, panel, cap, box), so they don't
dome. `namdev-*` (from the bench's 11-03 kit) has the domed glass. Its fix is rendered (M1 list `macbook-readouts179`)
but not yet posted into the bench's `views/`. `GlassWindow` (SwellKit.swift) draws amber text with a 0.35 glow over
`rkit-glass` plus `Swell.glass`. Keep the glass picture dark enough that it never greys the amber. The bench's own
window sheen is a 7 % white wash from the upper left, no more.

### 1.5 Reflections: the workshop room (rule)

Lowell, 11-08: "I like version 3 tuned and yes would like it applied to the other surfaces that would realistically
reflect."

- **`metal_kit.room_world(s)`:** a workshop room in the world shader for glossy rays only. Diffuse light is unchanged.
  The rig scene adds it (`RIG_ROOM=0` leaves it out). `gear_kit.stage` does not.
- **`plate_room.py`:** for flat polished parts (chrome, alu, brass, gold, gloss enamel plates), one card at 30 cm
  (`RIG_PLATE_ROOM_DIST`), gain 4, drawn in centimetres. `plate_room.mirror_card(bpy, part, pw, ph, seed, aim, dist,
  gain)` places it where the part mirrors to, light-links the studio's front cards away from the part, and hides the
  shadow-catcher floor from glossy rays. `rig_knobs.cap_room` does the same for chrome and gold knob caps (knobs182).
- **Enamel panels** keep the top light's diffuse share. `rig_amp._enamel_top_diffuse` is a diffuse-only twin of topL for
  a plate whose cards are unlinked. Before that fix, a cream plate read (171, 166, 154); after, (181, 175, 164).

**For IR Capture:** the reel deck's brushed plate and reel flanges, the chrome prongs and screws, and the nickel bezels
are in `TK.scene()`: no room, a black world with a few cards. Suggestion: call `room_world(s)` after `TK.scene()`, and
`mirror_card` on the reel deck's plate. Brushed alu reads the room as a soft horizontal streak, not a picture. That's
right for brushed metal.

### 1.6 Materials (rules unless marked)

- **Liquid hammertone** (rule for the bench: "apply that new hammer tone everywhere it's used!", 11-06; "liquid tension
  hammered finish" like his Magnecorder, 11-04, against the porous cells). `metal_kit.hammer_paint` now returns
  `hammer_liquid.liquid_paint(name, tone, k, seed, ...)`. The tones are `silver grey green blue bronze graphite`, each
  with seeded, cached maps. `HAMMER_ROUGH=1` gives the old cells. **IR Capture's `ircapture_kit.hammertone_fine()` is its
  own Voronoi cell version** (cells 2.5 times smaller), used on panel-fine, box-bronze and the reel deck's case. On
  11-03 Lowell told IR Capture "the hammertone is too busy--it could be a different surface or finer grain". The liquid
  finish answers both. Suggestion: swap to `liquid_paint(tone='bronze')` for the Cab IR side; graphite is the anodised
  NAM panel's colour, not a hammertone.
- **Shop wood** (rule for the bench's shelf, 11-04: "too smooth ... office furniture, not a workshop shelf", like his own
  pine bench edge; then "loved the new wood"). The new one is `design/render/shop_wood.py`: each board a mesh displaced
  about 1 mm, with raised grain, planer chatter or saw marks, knots with checks, a chewed grimy top edge, dents, screws
  and holes, stains, a burn, and no lacquer (`WOOD_AGE` darkens). **IR Capture's plank and trims are the lacquered fumed
  quartersawn oak** (`_oak_top`, `oak_material` on `shelf_wood.py`'s field). Suggestion: take the bench's own plank and
  trims from the white-light `frame182b` (they're the same wall) instead of rendering a different shelf. The two
  programs then share one shelf.
- **Shop wear, nothing uniform** (rule, 11-03): "each piece its own subtle shop wear and texture, slight staining /
  discoloration on some switches". IR Capture's 11-04 seeded wear already follows this.
- **Finishes on true-scale maps** (`finish_maps.py`, 156th chat): enamel orange peel, powder, wrinkle, flake, brushed
  and anodised alu at 0.05 mm lines, tolex, plus a shared chip/scratch/scuff field. Use these for any new painted or
  anodised surface rather than shader noise, which reads flat at the page's scale.
- **Colours:** red and blue plates were "too 'primary color' and probably too dark". They're now a faded brick rose
  `#b8786c` and a slate blue `#7d93aa`. The jewel and LED colours are separate and unchanged.
- **No instructional wording printed on gear** (rule, 11-05: he hates "The knobs work the band picked" on a panel).
  Legends name things. Instructions go in help text, not on the rendered faces.
- **Readability over scale** (rule, 11-01): controls and labels may be oversized rather than tiny.

### 1.7 Motion (rule: "as lovely and real-looking as the renders", 11-09; every powered thing gets "a natural start-up")

The bench's page is HTML/JS, but everything here maps onto SwiftUI. What each part does was decided by what the real
part does. Nothing gets motion a real one doesn't have, and nothing animates while nothing moves.

- **One frame loop at the display's rate** (`views/motion.js`). It runs only while something is easing.
  - `ease(cur, want, dt, tauUp, tauDown)` is a first-order lag with its own time constant each way.
  - SwiftUI: `TimelineView(.animation(paused: !moving))` with no `minimumInterval`, so ProMotion runs at 120 Hz.
    `CADisplayLink` (macOS 14+) or `CVDisplayLink` also works.
- **Knob sprites between frames.** With 36 frames over the travel, the nearest frame and its neighbour are both rotated
  to the exact angle, and the neighbour is laid over at its share. The highlight glides instead of jumping up to 10
  degrees at each frame boundary (mean change 0.33 grey levels, against 2.34 before). No inertia: a real knob doesn't lag
  the hand.
- **Magic eyes.** The frame below and the next are summed, not stacked: the upper one `plus-lighter` at w, the lower at
  1 - w, in an isolated group. Stacked, the lower showed through the upper's glow. Attack 25 ms, release 70 ms after
  the meter's peak hold. Detented selectors still snap.
- **Lamps by kind.**
  - A filament jewel: on in 90 ms, off in 240 ms with a tail.
  - A neon: 40 ms.
  - An LED: instant.
- **VU needles:** a damped spring, ω = 16.5 rad/s, ζ = 0.78 (`views/rack.js`). That gives about 300 ms to 99 % of a step
  and about 1.5 % overshoot, the standard's ballistics. Integrate in 4 sub-steps a frame. 0 VU at -18 dBFS. The LED
  ladders have a peak hold.
- **Motors.**
  - Drum, tape and oil-can echoes: up to speed in about 1 s, coasting to a stop over about 2 s, stopping where they stop
    (`tabletop.js` `SPIN_UP 0.35`, `SPIN_DOWN 0.7` s).
  - Strobe discs: first-order, `SPIN_TAU` 2 s, smearing into the blur between 40 and 200 degrees a second.
- **Nixies** change digit at once (a neon glow goes out in microseconds), with no fade.
- **Phosphor screens** (`views/phosphor.js`, WebGL2) are only for CRT-like screens: the beam deposits a Gaussian spot
  along each segment on a float buffer, decaying as exp(-dt / 32 ms) each display frame, tone-mapped with a halation
  blur. **IR Capture has no CRT, so skip it.**
- **Power-on: one clock** (`SwellMotion.power`, `END` 6 s). It starts when audio starts, and everything powered warms
  from it together.
  - Nixies and magic eyes: their glow in over 6 s.
  - Gas windows: dark 0.6 s, the keep-alive glow, every dot, a column scan, a model line, then the reading at 4.8 s.
  - The VFD: filament fade, every dot, a title, the content painted in from the left.
  - Neon 7-segment: 8.8.8.8 lamp test, one digit walked across, the reading at 3.65 s.
  - Scope beams: nothing until 2 s, then dim and soft, sharp by 5.5 s.
  - EM84: first light at 1.75 s, full at 6 s.

  A display powered later, outside the warm-up, strikes straight to its reading.

---

## 2. Where IR Capture stands (read from `preview/workshop-look` 5de6bc9, 11-04; `main` is 10-22 and has none of the look)

| | found | against the bench |
|---|---|---|
| Pictures | 246 WebP, all lossy (`ircapture_kit_post.py` and `ircapture_tape_post.py` save `quality=90, method=6`) | lossless (§1.2) |
| Bench kit pieces | frame 35, rack 29, audio 2: warm frame light; namdev 18: domed glass; rlamp 36: the jewel model the bench is replacing (its @3x sharp157a is a different bezel) | white light; re-rendered lists exist (§3 A) |
| Own pieces' light | `TK.scene()`, white | right |
| Pixel filter | 1.5 px (gear_kit.stage default) | 1.0 on the rig (§1.3) |
| Reflections | no room; black world with cards | `room_world`, plate room (§1.5) |
| Hammertone | `hammertone_fine`, Voronoi cells | liquid (§1.6) |
| Shelf wood | lacquered fumed oak | rough shop wood (§1.6) |
| Domes | `TK.flat_faces` on every big face | right |
| Reels | `TimelineView(.animation(minimumInterval: 1/60, paused: !moving))`; speed follows the sweep; coast tau 0.35 s | good; drop the 1/60 cap |
| VU needle | `.easeOut(duration: 0.3)` on each value (Gear.swift `VUMeter`, "not VU ballistics") | spring ω 16.5, ζ 0.78 (§1.7) |
| Magic eye | 56 frames, nearest only; warm-up 3 frames × 370 ms | blend two frames summed; warm on the power clock |
| Nixies | instant digits; no warm-up | instant digits right; warm on the power clock |
| Jewel and LED lamps | swap on/off pictures at once | filament 90/240 ms; LED instant (right for the NAM side's LEDs) |
| Status jewel | amber pulses `easeInOut(0.8).repeatForever` (Views.swift ~340) | a filament doesn't breathe; blink on/off with the filament's times, or hold steady |
| Counter wheels | `.easeInOut(0.22)` roll | fine (a mechanical roll) |

---

## 3. What to do, in order

**A. The bench's pieces in the white light (desktop bench side; Lowell asks there).** These lists are rendered or
rendering and not yet posted into the bench's `views/`:
- `imac-frame182a`: the rack units (monitor, counter, EQ, capture, VU, LED, blank).
- `imac-frame182b`: wall, shelf (plank, trims, cabinet, worn cases, keys, boxes, lamp, knob), the Audio and **IR
  Capture keys**, books, EQ panel, strobe, roller.
- `macbook-readouts179`: Solver, Speaker, the NAM loader with flat glass.
- `imac-knobs182`: chrome and gold caps with the room.

Once they're posted, the bench side re-runs `tools/make_ircapture_kit.py`. It copies the pictures as they are, so they
come out lossless, and rewrites `layout.json`. Rects can move by rounding: re-read them, don't assume. It ships a new
`ircapture-kit-<date>.zip`. Don't take the bench's pieces from `render-out/*` yourself: the bench's post scripts crop,
scale (rack 0.5625) and lay out the states, and `layout.json` follows those.

**B. Re-render IR Capture's own pieces** (`jobs-imac-ircapture.json`: keys, panels, plank, boxes, trims;
`jobs-imac-tape.json`: reel, cart, box) with the bench's current `design/render/` from `look` (they import parts,
gear_kit, instrument, toolkit, shelf_gear, shelf_wood, metal_kit). Before queueing:
1. Swap `hammertone_fine` for `hammer_liquid.liquid_paint` (bronze), keeping a per-piece `seed`/`offset` so pieces
   differ.
2. Use the bench's plank and trims from A, or render yours with `shop_wood.py`. Drop the lacquered oak either way.
3. Call `room_world(s)` after `TK.scene()`. Run `plate_room.mirror_card` on the reel deck's plate and the cart
   machine's face if they're polished.
4. Set the pixel filter to 1.0 (suggestion).
5. Keep `TK.flat_faces`. Check any new glass is chamfered or flat-shaded.
6. Render at @2x of the app's largest drawn size, more where the app scales up. Measure on a 5K or Retina screen: the
   bench's rule of thumb is the picture's px ≥ the device px it's drawn at.

Make a low-sample proof of one panel and the reel deck first (the bench uses 24 samples at 14 to 20 px/cm), compared
with the posted picture, and send Lowell the before and after. Then queue full quality.

**C. Lossless posting.**
1. Add `import webp_out` (copy `desktop-bench/design/render/webp_out.py` beside your post scripts, or import it from
   there) right after `from PIL import Image` in `ircapture_kit_post.py` and `ircapture_tape_post.py`. Or save with
   `lossless=True, exact=True, quality=90, method=4`. Keep premultiplied resampling (`unpremul` already exists in the
   tape post).
2. Verify: a chunk walk over `Resources/SwellKit/pictures/*.webp` with 0 `VP8 ` chunks. Add it to CI.
3. Size: expect roughly 25 to 50 MB in place of 9.7 MB. Suggestion: Git LFS for `Resources/SwellKit/pictures/*.webp`
   with `lfs: true` in build.yml's checkouts. IR-Capture is under the same account as desktop-bench, so it shares that
   account's LFS quota (10 GiB storage and 10 GiB bandwidth a month free). Plain git also works at that size, at the cost
   of history growth on every re-post.
4. NSImage decodes WebP natively on macOS 11+. Nothing changes in `SwellPictures`.

**D. Motion in SwiftUI** (§1.7 for the reasons):
1. **One power clock** in AppModel: `powerOnAt: Date?`, set when audio starts (or the level check opens). Each powered
   view reads `age = now - powerOnAt` in its `TimelineView` while `age < 6`, then stops.
   - NixieReadout: digits' opacity up over about 6 s, slightly uneven per tube.
   - MagicEye: no glow until about 1.75 s, full at 6 s (instead of 3 × 370 ms).
   - VU lamps (if lit): filament.
   - A later power-on, outside the warm-up, strikes at once.
2. **MagicEye:** draw `floor(x)` and `floor(x) + 1` with `.blendMode(.plusLighter)` at (1 - w) and w inside
   `.compositingGroup()`. Ease the closure with attack 25 ms and release 70 ms.
3. **VUMeter:** replace `.easeOut(0.3)` with the spring in a `TimelineView` (ω 16.5, ζ 0.78, 4 sub-steps a frame),
   paused once the needle is within 0.05 degrees and its speed is about 0. Keep the Reduce Motion path.
4. **Lamps:**
   - `JewelLamp` cross-fades its on and off pictures, 90 ms on and 240 ms off with a tail (ease-out).
   - `LEDLamp` and `LEDLadder` segments stay instant.
   - Replace the amber status jewel's `repeatForever` pulse with a steady lamp or a real on/off blink at filament times.
     A lamp that breathes forever is the one perpetual animation the bench avoids.
5. **Reels:** drop `minimumInterval: 1/60` so it runs at the display's rate. The coast model is already right.
6. Knob or treadle sprite sheets, if IR Capture ever gets any: two-frame blend as §1.7.

**E. Screens:** keep every lit window's picture dark under its legend (the glass greys nothing). No highlight or stroke
overlays on a rendered window. No glass dome.

**F. Queueing renders on Lowell's machines.** Two self-hosted runners render, through desktop-bench's
`.github/workflows/render.yml`:
- the iMac in Boot Camp Windows (label `render`, `"runner": "imac"`);
- the M1 MacBook (label `render-mac`, `"runner": "macbook"`, about 1.75 times the iMac's time).

They're working through about four days of bench lists. **A run waits at most 24 hours for a runner, and GitHub doesn't
start a machine's queued runs in order**, so the bench keeps ordered queues instead:
- `design/render/queue-imac.txt` and `queue-macbook.txt` on `look`: one `jobs-<list>.json` name a line.
- Each run dispatches the next itself (`queue_next.sh`).
- A list renders with look's scripts as they are when it starts.

Your 11-03/04 lists ran as push branches (`render/imac-ircapture`, `render/imac-tape`). Pushing a `render/<name>` branch
still works, but now it would sit in GitHub's queue behind a busy machine and could time out. So:
1. Put your scripts and `jobs-<machine>-ircapture-<x>.json` into desktop-bench `look`'s `design/render/` (names
   prefixed `ircapture_`, as yours already are).
2. Add the list's name to a queue file, where Lowell wants it in the order.
3. Tell Lowell, so the desktop chat knows the list is there.

Notes from the bench's runs:
- **The M1 must be plugged in with the lid open.** `caffeinate -ims` can't stop lid-close or battery sleep, and it lost
  the runner twice on 11-09.
- The iMac has a long-standing RAM fault. Open every PNG before posting (PIL `Image.open(p).load()` catches the bad
  CRCs), and re-queue failures. The bench's cloth and finish map caches now delete and rebuild an unreadable file and
  write through a temporary name (193rd chat). If you cache maps, do the same.
- A dispatched list whose render-out already exists is skipped. Re-render under a new name.

---

## What was checked, and what wasn't

- **Checked:**
  - Read from desktop-bench `look` (331bc65, 11-09): `frame_camera.py` lights and `WARM`/`COOL`, `rig_scene.py`,
    `gear_kit.stage`, `toolkit.EXPOSURE`, `hammer_liquid.TONES`, `views/rack.js` VU constants, `tabletop.js`
    `SPIN_UP`/`SPIN_DOWN`, the render queues and job notes (frame182a/b, readouts179, knobs182).
  - HISTORY.md's 156th, 157th, 175th, 179th to 182nd records; GUIDE.md's 190th to 192nd.
  - From IR-Capture `preview/workshop-look` (5de6bc9): every picture's WebP chunk (246 lossy), the post scripts' save
    calls, the render scripts' scene, materials and `flat_faces` use, and Gear.swift, SwellKit.swift, TapeDeck.swift
    and Views.swift's animation code.
- **Not checked:**
  - Nothing rendered or built here, and no proofs. Whether `liquid_paint` and `shop_wood` drop into your scripts
    without changes to their arguments.
  - The 1.0 px filter's effect on your pieces.
  - The exact lossless size of your set (the 25 to 50 MB figure is the bench's 2.5 to 5 times ratio applied, not
    measured).
  - Whether frame182b's `ircapture-keys` job matches your `ircapture-keys.json` rects. The bench post decides that; diff
    the layout after the kit rebuild.
  - Lowell hasn't been asked whether IR Capture should take the bench's shelf as is. That's a suggestion.
