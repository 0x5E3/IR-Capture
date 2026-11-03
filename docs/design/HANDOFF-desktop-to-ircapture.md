# Handoff: the desktop bench's look, for IR Capture (2026-11-03)

From the desktop bench project (repo 0x5E3/desktop-bench, branch `irkit`, 127th desktop chat, helper "irkit") to the
Claude working on **IR Capture** (repo 0x5E3/IR-Capture, the SwiftUI Mac app), and to Lowell.

Lowell wants the two programs to look like "program buddies": IR Capture dressed in the desktop bench's rendered
workshop look, reusing the bench's rendering work. This note is everything you need, since you can't see the bench's
chats. The kit is beside it: `handoffs/ircapture-kit/` (also zipped as `handoffs/ircapture-kit-2026-11-03.zip`):

| | what |
|---|---|
| `pictures/` | 114 rendered pieces (WebP), 1x and @2x where the bench has both |
| `fonts/` | 9 TTFs (Barlow, Barlow Semi Condensed, B612 Mono, Nixie One) and their three OFL licences |
| `layout.json` | every picture's pixel size, points, cap insets, sprite rects, the rack units' element maps, the colours |
| `contact.jpg` | every picture, labelled with its file name and size |
| `SwellKit.swift` | a starter: font registration, picture loading, 9-slice panels, the key ButtonStyle, glass window, lamps |

Everything is marked **rule** (Lowell's, or standing in the bench project; keep it) or **suggestion** (Claude's
proposal: his to change). The rules come from the bench's GUIDE.md "Decisions" and the chats since the 102nd (the
rendered-look proof, 10-30) to the 127th (today).

---

## A. The look, in words

**What it is.** A warm, tube-era workshop at night. The window is a charcoal pegboard wall with a stained, quartersawn
oak shelf across the top; the shelf carries small homemade hammertone-steel boxes holding the controls: illuminated
pushbutton keys (ivory resin caps in black cast bezels, an amber lamp behind them when lit), smoked-glass windows with
warm amber lettering, a jewel pilot lamp. Under the shelf, the work sits in an opening set into the wall with a moulding
round it, a dark stage cloth behind. Gear on the right is rack units (black crinkle panels, cream engraved legends,
magic eyes, VU meters, nixie tubes) on the front rails of a cabinet. Lowell picked this ("concept C", 11-02): "i love the
workshop wall with the top shelf idea. i like how it's 3D. should be some wear and texture on everything of course. not
obtrusive just enough to look real. love the lighted push buttons."

**Rules** (Lowell's, standing):

1. **Warm, real, tube-era gear; classy.** His first decision (10-06): "warm, natural, draftsman style, with the musical,
   tube-warmth side of it. Not neon, not jagged letters, not fake LEDs." Reference: tube-era lab gear. Lettering as
   engraved panel capitals.
2. **Everything rendered in one scene and one light.** Every piece is a Blender (Cycles) render under the same lights,
   not a CSS/SwiftUI gradient imitating metal. Shadows fall the same way on everything (key light up and to the left).
   The frame has one architectural camera (`frame_camera.py`: eye at the window's centre, so the shelf is seen slightly
   from below, rack units flush with a sliver of side); devices on the bench's stage are seen 10 degrees from above.
   A new piece for IR Capture is rendered the same way (section E), not drawn.
3. **Wear and texture perceivable, never obtrusive.** "Some wear and texture on everything of course. not obtrusive just
   enough to look real." Pieces come in wears (clean / played / beat on some).
4. **Readability over true scale.** Controls and legends may be oversized against real hardware (the 11-02 rack units:
   "nixies and magic eyes should be loud and proud, labels readable"). Never shrink a legend to be faithful.
5. **No neon, no fake LEDs, no fake chrome, no flat "plugin" look.** No glowing outlines, no flat web buttons, no SF
   Symbols in the gear itself, no gradients pretending to be metal. (Rendered metal and rendered jewel lamps are fine:
   they're the real thing in the scene.)
6. **No inoperable controls, and no inoperable power switches.** Anything that looks like a switch, key or knob does
   something. A rack unit with a POWER toggle only appears where that toggle works.
7. **Lowell's name is never user-facing.** No "Lowell", no "Hunt" in the interface, pictures, file names users see,
   or metadata. (The company is Swell Amplification LLC; that's fine where IR Capture already uses it.)
8. **No brands on gear.** Bodies are "style" names, never a trademark (the bench's rule for amps; keep it for any
   rendered piece IR Capture adds).
9. **Keep every function.** The look changes the dress, not what the app does (his 10-06 rule for the bench:
   "consolidate and simplify where it doesn't remove a function"). IR Capture's steps, checks, errors, notes and
   automation hooks (`--demo`, `--nam-demo`, `--render-diagrams`, `--help-page` ...) all stay.
10. **Help text off the face of the gear.** The bench moved its paragraphs off the main view (10-30: "help text off the
    main view"). In IR Capture the step instructions are the product's core, so they stay, but as printed notes (paper
    tags / cards), not text floating on metal. (This is a suggestion for IR Capture; the rule is the bench's.)

**The type** (rule: the bench's three faces, `apps/plugin/page/index.html` `:root`):

- **Barlow Semi Condensed** 600/700, capitals, tracked 0.14 to 0.3 em: every legend engraved on gear, key legends, the
  values in glass windows (`--cap`).
- **Barlow** 400/600: running text, notes, checklists (`--body`).
- **B612 Mono** 400/700: figures in tables (`--mono`).
- **Nixie One**: only inside a rendered nixie tube.

**The colours actually used** (from the bench's CSS; in `layout.json` "colours" and `SwellKit.swift` `Swell`):

| use | hex | where in the bench |
|---|---|---|
| digits on smoked glass | `#F2C46D` (glow: same at 35 %, 3 px) | index.html `--amber`, rkit.css |
| the shelf windows' lettering | `#F1C983` (glow rgba(255,170,70,.28), 6 px) | frame.css `--ink-win` |
| nixie glow | `#FF9A4A` | `--nixie` |
| a warning in words | `#FF8A6A` | `--warn` |
| key legend, unlit / lit | `#1D150B` / `#2A1506` | rkit.css |
| legends engraved light on the bronze panel | `#E6E1D4` (labels `#D9D2C2`), shadow 0 1 0 rgba(0,0,0,.85) | rkit.css |
| the rack's cream lettering on crinkle / its sub-text | `#D8D0BD` / `#9D968A` | audiopage.css |
| manila tag paper / ink / error title | `#D9C69A` / `#2A2117` / `#7A1C10` | frame.css `.fnote` |
| pegboard wall / stage cloth / under the glass | `#1C1D1E` / `#120F0C` / `#050505` | frame.css, rkit.css |
| keyboard focus ring | `#FFB547`, 2 px, 2 px outside the bezel, keyboard only | rkit.css |
| the jewel pilot | off: dark (all well); amber: working / waiting; red: an error | frame.css `.flamp` |

The ivory key cap, the lit cap's amber and the bronze hammertone are in the pictures themselves (`rkit-key-off.webp`
centre about `#A4967D`, `rkit-key-lit.webp` about `#F9BD98`), not colours to paint.

Contrast measured (WCAG ratio, the picture's centre pixel as background): amber on glass 12.5:1; key ink on the unlit
cap 6.2:1, on the lit cap 10.6:1; panel legend on bronze 10.1:1; cream on crinkle 8.9:1, its sub-text 4.7:1; tag ink on
manila 9.4:1; warn on bronze 5.7:1. All pass AA for normal text.

## B. Screen by screen: IR Capture's views as rendered gear

Read from IR Capture at c8d5e2f (`Sources/IRCaptureApp`: Views.swift, CabViews.swift, NAMViews.swift, HelpViews.swift).
Everything below is a **suggestion** unless it repeats a rule from A. Each line keeps the function it dresses.

**The window (ContentView).** The window is the workshop wall: `frame-peg` tiled as the wall, the top shelf
(`frame-plank` with `frame-box-*` boxes standing on it, `frame-trim-*` round the opening) across the top, the steps in
the opening below over the stage cloth (`frame-backdrop`), still in the ScrollView. At IR Capture's sizes (min 780 x
640, default 920 x 960) draw the frame at 1 pt per bench ref px; the shelf is then about 103 pt tall.
- The `Cab IR | Amp (NAM)` segmented picker becomes **two illuminated keys on the shelf**, CAB IR and AMP NAM, the
  selected one lit (as the bench's page keys: lit = this page). Disabled while busy, as now.
- The line under it ("Record the speaker cab's impulse response.") goes on a **manila tag** hanging under the shelf (the
  bench's status tag) or stays as plain Barlow text on the stage.
- A **jewel pilot** on the shelf (`frame-lamp`): dark when idle, amber while `m.busy` (level check, capture, processing),
  red while `m.errorText` is set. Its words on a manila tag under it (the bench's pattern: the lamp's state in words,
  never cut). The BusyLine and ErrorNote stay where they are too (the lamp adds, it doesn't replace).
- A HELP key on the shelf opens the Help sheet (the Help menu stays).
- Force the dark appearance (`.preferredColorScheme(.dark)`) so system controls not yet dressed (checkboxes, steppers,
  menus' pop-ups) sit right on the wall.

**The job stepper (JobStepper).** Today a status strip. Rule 6 says a key must do something, so either: (a) **jewel
lamps with engraved legends** (CONNECT, SET LEVELS, CAPTURE, RESULTS; for NAM SIGNAL, CONNECT, SET LEVELS, RECORD,
UPLOAD), green when done, unlit when not: an indicator, honestly; or (b) keys that scroll to their step
(`ScrollViewReader.scrollTo`), lit when done. Claude's lean: (a), the shelf's own keys reserved for actions.

**Each step (Step, a GroupBox).** A **rendered panel**: `rkit-panel` (bronze hammertone, screws in the corners) laid
round the step with `Panel9Slice`, the title engraved light in Barlow Semi Condensed caps (`#E6E1D4`), the number in a
jewel lamp (amber = to do, green = done; the checkmark goes). The subtitle in Barlow `#D9D2C2`.
- **Checklist / PreflightList / Note / Aside**: printed matter, so **manila tag or card stock** (`paper.webp` at 220 pt
  over `#D9C69A`, ink `#2A2117`), pinned on the panel, or the bench's paper sheet. Preflight's ok / warn / bad icons
  become small jewel lamps (green / amber / red) beside the words; the words stay (colour is never the only signal).
- **ErrorNote**: a tag with a red title (`#7A1C10`), its Open Audio MIDI Setup / Privacy buttons as keys.

**Connect (CabConnectStep, InterfaceRow, InputsGrid, ReferenceChooser, IdleSignalChips, CabAdvanced).**
- Interface and Output pickers: **glass windows** with a chevron (`GlassWindow` around a `Menu`'s label; a stock
  `Picker` can't be skinned). The "Recording rate" line inside a glass window (it's a value).
- InputsGrid: a row per input on the panel; "Input 3" engraved; Use as **two keys** MIC / OFF (lit = chosen); the mic
  name a `TextField(.plain)` in a glass window, amber; the common-names menu a chevron on the glass.
- Reference source (three cards): **three keys** NONE / LOAD BOX / TAP, lit = chosen, each blurb as engraved small text
  or a tag beside it. "Connected to" a glass-window menu.
- Idle-signal chips: a small tag with an amber jewel ("Signal on Input 3, -24 dBFS. Use it?") and its keys.
- WiringDiagram: the bench draws diagrams as **line drawings on paper** (draftsman style, his "realism mixed by
  layer": real-looking gear, line drawings on the bench). Draw the nodes as ink boxes on a paper sheet; keep the
  `--render-diagrams` export on white as it is (the Quick start PDF wants white).
- Advanced (DisclosureGroup): keep it; its label as a small key ADVANCED, lit while open. Steppers: the value in a
  small glass window with two small keys (minus / plus), or the stock Stepper beside the window.

**Set levels (CabLevelStep, LevelTable; NAM: NAMMeterTable).** The heart of it, and the best match for the bench's gear.
- Per input, a **VU meter** from the rack's level unit (`rack-vu` face, `rack-vu-needle` turned about its pivot; the
  angle table is in layout.json). Honest mapping: the face is printed -20 to +3 VU, not dBFS. Put **0 VU at the
  target** (-6 dBFS peak for the cab's manual level, the auto level's target for the cab, -8 dBFS for NAM). IR Capture's
  OK rule is "within 3 dB of target", which is exactly -3 to +3 VU: the red arc above 0 is "turn down". Below -20 is "no
  signal". It's still IR Capture's peak reading driving it (not VU ballistics); smooth the needle (about 300 ms rise and
  fall, as a VU) and keep the dBFS figure in a glass window beside it, so nothing is hidden. Two meters a unit; stack
  units for more inputs, or use one meter face per row.
- Alternatives: the **magic eyes** (`rack-monitor-ineye/outeye`: 59 frames, warm-up then x00..x55 closing; map "closed"
  to the target) look great and read "tuned in"; the rendered **LED ladder** (`rack-led-ledin`, -42 to 0 dB) is the most
  literal peak meter but leans away from the tube era. Claude's lean: VU pair for levels, an eye for the room-noise
  check.
- CLIP: a **red jewel** per input (as the monitor unit's CLIP lamp), lit on clip; the words "CLIP: turn down" stay.
- The advice ("OK", "Turn up 4 dB"), H2/H3 and noise pills: small glass windows (amber figures) with a jewel lamp for
  the status colour; the words stay.
- Check levels / Stop: **one key**, legend CHECK while idle, STOP while running, lit while running.
- The auto level pill ("Sweep level set (-12 dBFS)"): a glass window, its lamp amber while setting, green when set.

**Capture (CabCaptureStep, CaptureNameFields, TargetsPicker, AdvancedOutput, BusyLine).**
- Capture name, notes, Save to: glass windows (the path in Barlow, amber or cream); Change... a key.
- Files to make (checkboxes with explanations): rows of small keys lit = on, explanation text beside each; or keep
  checkboxes with `accentColor` amber (the bench leaves check boxes stock with an amber accent).
- **CAPTURE** a large illuminated key, lit while capturing. Disabled reasons (`captureProblem`) on a tag beside it.
- Progress: a **nixie readout** of seconds left (the Counter's four tubes in the kit, its window cropped: see C) next
  to a jewel lamp; STOP as a key. The text line stays.
- Record again (dropped out): a key.

**Results (ResultsView, DiagnosticsTable, ResponsePlot, ReexportSheet).**
- Header: the title in a glass window; the quality ("Excellent" / "Good: 1 item to check" / "Record again") as a jewel
  (green / amber / red) with its words engraved beside it.
- Warnings: manila tags (red title for the drop-out one).
- "Load these" files: the file names in glass windows (they are the bench's **speaker IRs**: see D).
- DiagnosticsTable: on a panel, figures in B612 Mono, each status pill a lamp + figure in a small window.
- **ResponsePlot on the instrument faceplate** (`faceplate.webp`, 9-slice, 40 pt corners) round a dark screen (the
  bench's Tools screen: radial #17241F to #090F0C), grid lines dim, the mic curves in IR Capture's mic colours tuned
  lighter for the dark screen. The legend swatches as tiny jewels.
- Show in Finder / Re-export...: keys (FINDER legend if rendered; plain-text keys otherwise).
- Re-export sheet: the same panel / keys / tags.

**NAM record (NAMDirectSteps, NAMModelChoice, NAMInputsGrid, NAMMeterTable, NAMResultsView, NAMLogicSteps).**
- Training signal: Find it in Downloads / Choose sweep file / Open tone3000.com as keys; the loaded file in a glass
  window with a green jewel.
- Capture type (radio): two keys AMP ONLY / FULL CHAIN, lit = chosen, the note on a tag.
- Inputs: as Connect's. Meters: as Set levels (target -8 dBFS at 0 VU).
- RECORD a large key, lit while recording; the 3 min 12 s countdown on the nixies.
- Results: "Ready to upload" a green jewel with its words; the table on a panel; the upload checklist on a tag.

**Import DAW recordings (CabImportSteps, NAMLogicSteps, LogicGrid, NAMGrid).** The same panels and keys. The drop
zone becomes the **bench's drop plate** (its 11-03 design: the window dimmed with a warm edge, a manila tag reading
DROP TO LOAD, what each file becomes). Files listed in glass windows; Role pickers as keys.

**Welcome sheet.** The sheet as one rack unit's face: the crinkle panel (`audio-panel`, 26 pt corners), the title
engraved in cream, the three page dots as three small jewel lamps, Back / Next / Start and Allow recording... as keys,
the checklists on a tag. Microphone status: a jewel (green allowed / red off) with its words.

**Help sheet.** The four-page picker as four keys (QUICK START, WIRING, REFERENCE, TROUBLESHOOTING; lit = page), the
pages as printed manual pages (paper, Barlow, tag ink), Done / Contact Support / Show Log File as keys.

**The visual link between the two apps.** The bench's rack has a **SPEAKER IR unit** (the IR knob steps through the
cabs, a glass window, LOAD / REMOVE) and a **CAPTURE unit** (the NAM capture player: POWER toggle, pilot, window, LOAD /
REMOVE / MAKE), and the stage has the **capture player** (`namdev-*`). Those are where IR Capture's output goes. Two
ways to use them (Lowell's call):
1. As **illustrations** in the results: "These load into the desktop bench's Speaker IR unit" beside a picture of
   `rack-speaker`, "Train at TONE3000, then drop the .nam on the bench: it plays in the Capture player" beside
   `rack-capture` or `namdev-played`. Risk against rule 6: a picture of a switch invites a click. Keep it small and
   framed as a picture (on a card, captioned "In the desktop bench"), or ask Lowell.
2. As **working units**, re-rendered with IR Capture's legends (section E): e.g. a CAB IR results unit on the speaker
   unit's face, its knob stepping through the capture's mics (highlights that mic's curve and file), its window showing
   the file name, its two buttons re-engraved FINDER and RE-EXPORT. A CAPTURE unit only with controls that work (no
   POWER toggle in IR Capture). Claude's lean: 2 for the results (it's the strongest buddy link), 1 nowhere.

## C. How to do it in SwiftUI

**Where the files go.** IR Capture's `.app` is assembled by `scripts/make_app.sh` from the bare SwiftPM binary (no
Xcode project, no asset catalog compile step, no `Bundle.module` copied). So: put the kit at
`Resources/SwellKit/{pictures,fonts,layout.json}` in the repo and add to make_app.sh, after the `mkdir`:
`cp -R Resources/SwellKit "$APP/Contents/Resources/"`. `SwellKit.folder` looks there (`Bundle.main.resourceURL`), or at
`$SWELLKIT_DIR` for `swift run`. An asset catalog would need `xcrun actool` in make_app.sh; not worth it. Note
make_app.sh's comment "no binary assets in the repo" (the icon is drawn by a script): the kit breaks that convention
(about 8 MB). Lowell decides: commit the kit, or fetch it at build time (e.g. from a release asset). The kit's pictures
are signed with the bundle (codesign covers Contents/Resources).

**WebP.** IR Capture's floor is macOS 13 (Package.swift `.macOS(.v13)`, Info.plist `LSMinimumSystemVersion 13.0`).
ImageIO (so NSImage and CGImageSource) decodes WebP from macOS 11, so **WebP is fine; no PNG copies are in the kit**.
(Not run on a Mac from here: check the first build shows the pictures.) `SwellPictures` loads with
`CGImageSourceCreateWithURL`, which reports a nil image rather than crashing if a file is missing.

**Points and @2x.** `layout.json` gives each picture `px_per_pt` (the 1x file's pixels a point): frame-* 1.6 (1 pt = 1
bench ref px, the bench's layout being drawn for a 1440 x 900 window), rkit-* 2.4 (the Tools kit at 24 px a cm, drawn
at 10 pt a cm), faceplate 4.8, audio-panel 2.46. `SwellPictures.image(name, pxPerPoint:)` makes an NSImage of that
point size holding the 1x file and, if there is one, the @2x file as a second representation; AppKit uses the sharper
on a Retina screen. Rack units and the capture player have no fixed size: 10 pt a cm (px_per_pt = pxcm / 10: 2.25 for a
rack unit, 501 x 152 pt for a 3U unit) matches the Tools views.

**9-slice.** `Image(nsImage:).resizable(capInsets: EdgeInsets(...), resizingMode: .stretch | .tile)`, insets in points.
The bench lays the **frame** pieces' edges and middles **cropped or repeated, never stretched** (use `.tile`), the
Tools **keys and windows stretched** (rkit.css `stretch`), the **panel and faceplate tiled** (`round`). Cap insets
(points; top, leading, bottom, trailing):

| piece | insets | mode | notes |
|---|---|---|---|
| `frame-box-circ`, `-box-keys`, `-box-pages` (shelf boxes) | 10, 26, 8, 76 | tile | the 76 trailing is the box's right end and its shadow |
| `frame-window` (old window) | 16, 16, 16, 16 | tile | glass inset 8 |
| `frame-win-circ`, `frame-win-find` (selector glass) | 0, 31, 0, 31 | tile | height is the render's (58 / 46 pt); text on `glass_pt` |
| `frame-cabinet` | 10, 37, 22, 25 | tile | the rack cabinet |
| `frame-card` | 34, 30, 34, 30 | tile | the dark card under the rack |
| `frame-trim-*`, `frame-plank` | strips: crop to length from the start | | never stretch |
| `frame-peg` | tile, 180 pt | | the pegboard |
| `frame-backdrop` | scaledToFill, clipped | | the stage cloth |
| `rkit-key-off/lit/down/litdown` | 5.42 all round | stretch | the picture's shadow margin 1.2 pt lies outside the box (`.padding(-1.2)`) |
| `rkit-win` | 5 all round | stretch | middle transparent: an overlay over `rkit-glass` on `#050505` |
| `rkit-panel` | 17.08 all round | tile | margin 2 pt; content padding 12.5 pt (room for the screws) |
| `faceplate` | 40 all round | tile | middle transparent: an overlay round a screen |
| `audio-panel` (crinkle) | 26 all round | stretch | |

**Sprite sheets** (rects in the file's pixels, origin top left; `SwellPictures.sprite(file, rect:, pxPerPoint:)` crops
with `CGImage.cropping(to:)`):
- `frame-keys@2x.webp` 2200 x 768: 8 columns (RIG, BENCH, PROBES, TOOLS, AUDIO, ADD, FILE, BROWSE) x 4 rows (off, lit,
  down, litdown), cells 275 x 192 px; cell i, row j at (275 i, 192 j); 3.2 px a pt, so a cell is 86 x 60 pt and the key
  itself (cap 58 x 32 + bezel 4) 66 x 40 pt. Crop the @2x (the 1x cells are 137.5 px wide). **The legends are the
  bench's**: IR Capture needs its own (section E) or the blank `rkit-key-*`.
- `audio-keys.webp` 2502 x 576: 9 columns (CORE AUDIO, WINDOWS, ASIO, EXCLUSIVE, SHARED, APPLY, RESTART, STOP, CLOSE) x
  the same 4 rows, cells 278 x 144 px, about 2.4 px a pt. STOP and CLOSE fit IR Capture as they are.
- `frame-lamp@2x.webp` 558 x 186: off, amber, red at x = 0, 186, 372, cells 186 px (58 pt).
- `frame-knob@2x.webp` 2688 x 211: 12 frames of 224 x 211 (the shelf's stepping knob).
- Rack units: each element's `sheet`, `frame` (w, h), `cols`, `rows`; state s is frame `i = states.index(s)` at
  `((i % cols) * w, (i / cols) * h)`, drawn at the element's `box` (picture px of the unit); the rest state is the
  unit's base picture (draw nothing). The VU needle is one picture (`rack-vu-needle`, its `pivot`) rotated by the
  `angle` table (VU -20 = -47 degrees ... 0 = +17.5 ... +3 = +47).
- `namdev-<wear>-<id>.webp`: one row; frame `states.index(s) - 1`.
- Nixies: `rack-counter-delay0..3.webp`, one tube a sheet, 11 frames (0 to 9, dp), 186 to 198 x 300 px. The frames
  are the glow only, made to lie over the Counter's face: crop `rack-counter.webp` at (80, 80) to (568, 257) px as the
  background (four unlit tubes behind black glass), then draw tube k's frame at its box's top left (42, 0), (162, 0),
  (276, 0), (396, 0) in the face's px (layout.json `nixie-tubes`). Checked here by compositing "2045": it reads right.
  Alone on another background the frames show fringes. The face's own legends (COUNTER, ADDED DELAY) are the bench's.

**The key** (`KeyButtonStyle` in SwellKit.swift): a ButtonStyle that picks `rkit-key-{off,lit,down,litdown}` from
`lit` and `configuration.isPressed`, lays it with its insets, sets the legend in Barlow Semi Condensed SemiBold caps,
`#1D150B` (lit `#2A1506`), nudges it 1 pt down while pressed, dims to 50 % when disabled, brightens 4 % on hover, and
adds the `.isSelected` accessibility trait when lit. Use: `Button("Capture") { m.startCapture() }
.buttonStyle(KeyButtonStyle(lit: isCapturing))`. Keyboard focus: macOS draws the focus ring for buttons in Full
Keyboard Access; if it looks wrong over the bezel, add `.focusEffectDisabled()` (macOS 14) and draw the bench's amber
ring yourself.

**Fonts.** Register at launch, process scope (nothing installed system-wide): `SwellKit.registerFonts()` calls
`CTFontManagerRegisterFontsForURL(url, .process, &error)` for each TTF. Then `Font.custom("BarlowSemiCondensed-SemiBold",
size:)` etc. by PostScript name (BarlowSemiCondensed-Regular / -SemiBold / -Bold, Barlow-Regular / -SemiBold / -Bold,
B612Mono-Regular / -Bold, NixieOne-Regular). The TTFs are the bench's **subsets** (about 235 characters: Latin, digits,
punctuation, ° µ Ω − › …); characters outside them (a mic named in Cyrillic) fall back to the system font by
CoreText's cascade. If IR Capture needs full fonts, take Barlow and B612 Mono from Google Fonts (same OFL).

**Accessibility.** Pictures that only dress a control are `.accessibilityHidden(true)` (Panel9Slice does it); the
Button underneath keeps its label and trait. Status is never colour alone (the words stay next to every lamp). Respect
Reduce Motion for the needle's swing and the lamp's slow pulse (the bench pulses the amber pilot 1.6 s). Increase
Contrast: the amber-on-glass and legends already pass AA (A's table); the 50 % disabled keys don't need to.

**`SwellKit.swift`** (in the kit): `SwellKit.registerFonts()`, `Font.swellLegend/swellBody/swellMono/swellNixie`,
`Swell.<colour>`, `SwellPictures` (1x + @2x NSImages in points, sprite crops), `SwellNine` (the insets above),
`Panel9Slice` and `.swellPanel()`, `KeyButtonStyle`, `GlassWindow`, `Lamp` (the shelf's pilot), `JewelLamp`, `ShelfKey`
(a key from a legend sheet). **Not compiled**: this container has no Swift toolchain, and SwiftUI/AppKit don't exist off
macOS anyway. Written for Swift 5.9 / macOS 13 APIs only (`.tracking` on View, `.textCase`, result-builder `if let`);
expect a few fixes on the first `swift build`. Note IR Capture already has a global `let lamp: Color`; SwellKit's type is
`Lamp` (no clash, but rename one if it reads confusingly).

## D. Shared words

Where the apps meet, the words should match (**rule** where marked: the bench's wording Lowell asked for on 11-03, "the
NAM 'speaker' wording is confusing as to what is the NAM's speaker vs the benchs IRs").

| thing | the bench says | IR Capture says now | suggestion |
|---|---|---|---|
| a cab IR file loaded after an amp | **speaker IR**; the rack's **Speaker IR unit**; "Bench speaker IR" (rule) | "IR", "cab IR", "Load these" | When IR Capture tells the user where the files go: "load into an IR loader, or the desktop bench's Speaker IR unit (drop the .wav on its window)". Keep "Cab IR" as the job's name. |
| a NAM capture that includes a cab | **"Its own cab: yes, built into the capture"** (`gear_type` containing `cab`) (rule) | "Full chain (mics on the cab). Amp, cab and mic in one model." | Add "(its own cab built in)" to Full chain's note, so the term carries over. |
| a NAM capture of the amp alone | "none (amp)", "no cab built in" (rule) | "Amp only (load box line out). For use with any cab IR." | Add "(no cab built in: play it into a speaker IR)". |
| the bench's IR after a capture | "Bench speaker IR after it": **Auto: off / Auto: on · IR on · IR off**; Auto is off when the file says it has its own cab (rule) | (none) | UPLOAD-STEPS.txt: tell the user to pick TONE3000's gear type to match (amp only vs amp with cab), since the bench's Auto reads it. Not checked here what TONE3000 writes into `gear_type` for each choice. |
| the level a capture was made at | **Input level** (dBu at the guitar jack / interface input), `input_level_dbu` in the .nam; without it the bench drives the capture at the Input level's full scale | "Set the reamp level to about the level of a guitar"; meters in dBFS | Optional, a function addition (Lowell's call): a "Reamp level" field (dBu, the interface output's calibration) written into report.json and UPLOAD-STEPS so it can be entered as the input level at TONE3000. The bench then plays the capture at the level it was made. |
| where a .nam plays | the **Capture player** (rack CAPTURE unit, the stage's capture player) | (none) | "Drop the .nam on the desktop bench's window: it plays in the Capture player." |
| the capture's file | "capture" | "capture" (both jobs) | Same word already. Keep it. |
| dBFS, dBu, VU | dBu for volts, dBFS for digital, VU on the meter face | dBFS | Never print VU numbers as dBFS (see the meter mapping in B). |

The bench's words to avoid: plain "Speaker" for the IR (old, replaced 11-03); the rack's SPEAKER legend is being
re-rendered as SPEAKER IR (`jobs-imac-audio.json`, not yet run: the picture in this kit still says SPEAKER).

## E. Getting new matching pieces rendered

Pieces IR Capture needs that the kit doesn't have: keys with its legends, units re-lettered (CAB IR results unit, no
POWER toggle), perhaps a bigger blank key. They must come from the **same scene and light** (rule 2), so from the
bench's render scripts in `design/render/` (Blender's Python module, bpy 5.2.3, Cycles on the CPU):

| script | what |
|---|---|
| `rig_scene.py` | the rig's one scene: world, room, lights for the stage devices (10 degrees above) |
| `frame_camera.py` | the frame's one architectural camera and its `lights()` (the shelf, keys, windows, rack units on the rails) |
| `metal_kit.py`, `gear_kit.py` | materials and parts: cast metal, hammertone, screws, wear; `gear_kit.stage()` is the Tools/faceplate studio |
| `shelf_gear.py` (+ `shelf_pieces.py`, `shelf_wood.py`, `shelf_post.py`) | the shelf, its boxes, windows, the jewel pilot, the **illuminated keys** with legends (`SHELF_KEYS`, `SHELF_KEY_W`) |
| `rack.py` (+ `rack_post.py`) | the rack units; each unit is a function (`speaker()`, `capture()`, `monitor()`, `vu()` ...) whose legends are literal strings (e.g. `ink.text('CAPTURE', ...)`, the buttons' `'LOAD'`, `'REMOVE'`, `'MAKE'`) |
| `faceplate.py` (+ `_post`) | the instrument faceplate 9-slice |
| `toolkit.py` (+ `toolkit_post.py`) | the blank key, window, panel, fader cap (px a cm and samples as arguments) |
| `namdevice.py` (+ `_post`) | the stage capture player |
| `extract_fonts.py` | the fonts out of `apps/plugin/page/fonts.css` for the renders |

Their imports (copy them together): toolkit.py needs `frame_camera, gear_kit, instrument, metal_kit, parts, rig_scene,
shelf_gear, shelf_pieces, shelf_wood`; rack.py needs `frame_camera, gear_kit, instrument, metal_kit, parts, rig_knobs,
rig_scene`; faceplate.py `gear_kit, instrument, parts`; namdevice.py adds `cloth, rack, rig_amp`. All of `design/render/`
is 1.4 MB of Python; the fonts come from the bench's `fonts.css` (or the kit's `fonts/`, named as extract_fonts.py names
them).

**Two ways:** IR Capture copies what it needs into its own repo (`design/render/`, unchanged, plus its own job list),
or asks the desktop project (a note in Bench Zips) and the bench renders and posts the pictures. **Prepared already** in
desktop-bench (branch irkit): `design/render/jobs-imac-irkit.json`: (1) the shelf's keys with 14 IR Capture legends
(CAB IR, AMP NAM, SIGNAL, CONNECT, LEVELS, CAPTURE, RECORD, RESULTS, UPLOAD, CHECK, STOP, IMPORT, FINDER, HELP) at the
shelf's full quality; posted with `audio_post.py` (now takes `SHELF_KEYS` + `KEYS_SHEET`, writes `ircapture-keys.webp`
and `.json`); (2) the blank key and window at 48 px a cm for large keys. Not rendered: the lead pushes it to the iMac
runner when it's free. Re-lettered rack units are not prepared (edit the strings in `rack.py`'s `speaker()` /
`capture()`, drop the POWER toggle for IR Capture; then `rack.py FONTS OUT base <unit> 40 192` and `states`).

**Two more renders in the queue will change kit pictures** (re-run `python3 tools/make_ircapture_kit.py` in
desktop-bench after they land to refresh the kit): the Tools kit at full quality (`jobs-imac-toolsrender.json`: the
`rkit-*` in this kit are from a 32 px/cm, 12-sample proof) and the SPEAKER IR re-lettering (`jobs-imac-audio.json`).

**Where renders run.** Not on GitHub's machines (Lowell's rule from 11-03: Actions spending is capped; no hosted render
jobs, no dispatches). On **Lowell's iMac in Boot Camp Windows**, a self-hosted GitHub Actions runner (i7-10700K, 8 cores,
CPU only; measured about 7 to 10 times a 2-core GitHub runner per sample). **That runner is registered to desktop-bench
only** (name `imac-windows`, labels `render, imac-win`, folder `C:\actions-runner-bench`). For IR-Capture's own renders:
- Register a **second runner instance** on the same Windows install for 0x5E3/IR-Capture: run desktop-bench's
  `tools/runner/setup-windows-runner.ps1` with a different folder (e.g. `C:\actions-runner-ircapture`), name (e.g.
  `imac-windows-irc`), the URL `https://github.com/0x5E3/IR-Capture`, and a token from IR-Capture's Settings > Actions >
  Runners (personal-account runners are per repository). The Python, Git and bpy venv parts are already done by the
  first install and are skipped.
- **They won't take turns by themselves**: two runner instances each take a job when one is queued, so two renders
  would share the 8 cores and both slow down (and both write `$HOME/render-out`). Make them take turns: a lock in the
  render script (e.g. `imac_render.sh` waits on `mkdir "$HOME/render.lock"` and removes it on exit), or only queue in
  one repo at a time. Not built or tested.
- IR-Capture's `render.yml` can copy desktop-bench's: the `plan` job reading `"runner": "imac"` from the job list, and
  the `render-imac` job (`runs-on: [self-hosted, render]`, `shell: cmd` running `"C:\Program Files\Git\bin\bash.exe"
  --noprofile --norc design/render/imac_render.sh`, then `imac_commit.sh`), with `design/render/run_jobs.py`,
  `imac_render.sh`, `imac_commit.sh` copied as they are. Use a distinct label (e.g. `render-irc`) on the second runner so
  each repo's jobs land on its own instance. Runs are resumable (`run_jobs.py --keep`, `.done` markers; outputs in
  `$HOME/render-out/<name>`, deleted after the push). The runner only works while the iMac is booted into Windows.

## F. Licences

The fonts are under the **SIL Open Font License 1.1** (texts in `fonts/`): Barlow and Barlow Semi Condensed (Copyright
2017 The Barlow Project Authors), B612 Mono (Copyright 2012 The B612 Project Authors), Nixie One (Copyright 2011
Jovanny Lemonad). None declares a Reserved Font Name. The OFL lets them be bundled in a sold app; the licence text must
travel with them (ship `fonts/OFL-*.txt` inside the app, and list them in IR Capture's About / third-party notices),
and they may not be sold on their own. The kit's TTFs are subsets converted from the bench's WOFF2 (a "Modified
Version" under the OFL; allowed, no rename needed without a Reserved Font Name). The bench lists them in
`docs/THIRD-PARTY-NOTICES.md`. The pictures are Swell Amplification's own renders (the desktop bench's), no third-party
art in them.

## What was checked, and what wasn't

- Checked: the kit's pictures are byte copies of `apps/plugin/page/views` at desktop-bench look dc6e7310; layout.json
  is computed from the page's own layout files (frame-layout.js, rack-layout.js, namdev-layout.js, audio-layout.js) and
  the slices in rkit.css, faceplate.css, audiopage.css; the fonts' names and coverage read with fontTools; contrast
  computed; `audio_post.py`'s change tested both ways on dummy images (the default writes the same files as before).
- Not checked: **SwellKit.swift has never been compiled**; WebP decoding on a real Mac (documented, not run); how
  SwiftUI's tile mode looks on these pieces (the bench repeats whole middles; SwiftUI tiles them the same way, by
  documentation); TONE3000's gear_type values; the two-runner setup.
