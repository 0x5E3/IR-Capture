# IR Capture

A Mac app for capturing guitar-cab impulse responses with as little fuss as a ToneX capture: wire the rig, check levels, press one button, and get finished IRs that load anywhere. It also records amps for NAM models trained at TONE3000.

It uses the same processing as the **Cab IR Capture** web page and the Python reference in `reference/`. CI checks it against both on every build.

> **Status:** version 1.0.0, pre-release. The processing is verified against a simulated rig (fake amp, cab, two mics and a reference tap, with known answers). The app's audio recording has **not yet been tested on real hardware**. The first real capture is also the app's first real test. Builds aren't signed by Apple until the Developer ID is set up (see `docs/SIGNING.md`).

## Get the app

1. Go to the **[Releases page](https://github.com/0x5E3/IR-Capture/releases/tag/latest)**.
2. Under **Assets**, click **IR-Capture.dmg**. It downloads to your Downloads folder.
3. Double-click the DMG. A window opens: drag **IR Capture** onto **Applications**. The **Quick start.pdf** in that window has the wiring pictures.
4. Open **IR Capture** from Applications.

### First launch (only while builds aren't signed)

1. Double-click **IR Capture**. macOS says it can't check it for malicious software. Click **Done** (or **Cancel**).
2. Open **System Settings › Privacy & Security**. Scroll down to the message about IR Capture and click **Open Anyway**. Enter your password if asked.
3. Click **Open** in the next box.

A newer unsigned build needs steps 1–3 again. Once releases are signed and notarized, none of this is needed: it opens on the first double-click.

The **Welcome** screen asks for permission to record from your interface, with a button. Click it, then **Allow**. If you clicked Don't Allow: **System Settings › Privacy & Security › Microphone**, turn on IR Capture, then quit and reopen the app.

## Cab IR

**Record here** (the main way):
1. **Connect.** Interface output → the amp's **FX return** (power amp in) or a clean power amp → the cab. Not the guitar input. Mics into the interface. The app shows the wiring picture, finds the interface when you plug it in, and picks the sample rate. Name each mic, and choose **Where's your reference?** (None is fine).
2. **Set levels.** Click **Check levels**. The app listens to the room for 2 seconds, finds a clean sweep level by itself, then loops short sweeps while you turn each preamp until it says OK.
3. **Capture.** Name it, check the **Before you capture** list, and click **Capture**. About 45 seconds later the results appear.

**Import DAW recordings** (secondary): save the test signal, record it in Logic, Reaper, Ableton, Pro Tools or GarageBand, and drag the exported WAVs in.

Files land in **Music › IR Captures** unless you pick another folder:

```
412_V30_PosA/
    412_V30_PosA_SM57.wav          ← Universal: 48 kHz, 24-bit, 500 ms. Load these.
    412_V30_PosA_R121.wav
    README.txt                     what everything is
    report.json                    the measurements (send this to Claude)
    More formats/                  only what you ticked under Files to make:
        Everything/<rate>/…        44.1, 48, 88.2, 96 kHz × 500 ms, 1024, 2048, 4096 samples
        Line 6 Helix/…             48 kHz, 2048 samples
        Strymon Iridium/…          96 kHz, 500 ms
        Custom/<trim>/<rate>/…     the Advanced matrix
    Raw take/                      the untouched recording + settings
```

**Re-export** (in the results, or **Re-export a past capture…**) makes other formats from the raw take without recording again.

Every IR comes out with its main peak positive, so mics blend without cancelling; a mic that recorded inverted is flipped and the results say so. **Advanced file options › Keep polarity as recorded** turns that off.

## Amp (NAM)

The app gets recordings ready for NAM training at [TONE3000](https://www.tone3000.com/capture); it doesn't train models itself. Both routes start with TONE3000's sweep file, `T3K-sweep-v3.wav` (the app can find it in Downloads).

**Record here:** choose the capture type (amp only, or full chain), wire interface → reamp box → amp, check levels (live meters aiming for −8 dBFS), then **Record** (3 min 12 s). The app plays the file on the same interface it records with, so the clocks can't drift, and keeps the raw recording.

**Import DAW recordings:** record the sweep in a 48 kHz DAW project and drag the exported WAVs in.

Output: `<capture>/<capture>_<input>.wav` (mono, 48 kHz, 24-bit), `report.json` and `UPLOAD-STEPS.txt`. Pair amp-only models with IRs captured with a reference, because the load box's line out already includes the speaker's impedance bump.

## Help and support

**Help** menu: Quick Start, Wiring, The Reference Tap (with a pad parts list), Troubleshooting, Contact Support (a mail draft with the app version, macOS version, interface and the latest report attached), Show Log File (`~/Library/Logs/IR Capture/`).

## Status of what's tested

- Simulated only: all processing, polarity, export targets and re-export (CI, every build).
- In CI on a Mac: the app launches, processes simulated recordings through its own window, renders its diagrams, opens its help pages. NAM recording runs through a simulated interface.
- Never on a real interface yet: the level check, the noise check, automatic sweep level, Capture, NAM Record, dropout detection, sample-rate switching and restoring.

## For developers

```
swift build -c release            # IRCaptureCore, ircapture-cli, IRCaptureApp
swift test                        # unit tests
cd reference && python3 sim_test.py && python3 compare_swift.py ../.build/release/ircapture-cli sim_out
scripts/make_app.sh               # macOS: dist/IR-Capture.zip (signed if CODESIGN_IDENTITY is set)
python3 scripts/make_dmg.py "dist/IR Capture.app" "dist/Quick start.pdf" dist/IR-Capture.dmg
```

- `VERSION` is the version string; keep `IRCaptureVersion` in `Spec.swift` the same (CI checks).
- `Sources/IRCaptureCore`: the DSP, a line-for-line port of `reference/web/dsp.js`, itself a port of `reference/ircapture.py`. Keep all three in step. `Targets.swift` has polarity normalization (also in Python and the page), the export targets (each with its manufacturer source), README.txt and the raw take.
- `Sources/ircapture-cli`: `make-signal`, `process` (`--targets`, `--keep-polarity`, `--raw-take`), `reexport` and `nam-prep`, used by the golden tests.
- `Sources/IRCaptureApp`: SwiftUI app. `DuplexIO.swift` plays and records through one AUHAL unit on one device, so input and output share a clock; it also reports input timestamp gaps and processor overloads (dropouts). `Support.swift` has the product name, support address, log and Contact Support.
- Signing and notarization: `scripts/make_app.sh`, `scripts/notarize.sh`, `scripts/IRCapture.entitlements`, and the CI steps that run when the Apple secrets exist. Setup: `docs/SIGNING.md`.
- CI (`.github/workflows/build.yml`) runs on macOS: simulated rig → page DSP vs Python → universal build → unit tests → Swift vs Python golden tests → app bundle → smoke tests and screenshots → diagrams and Quick start PDF → DMG → the `latest` release. A `v*` tag makes a signed, versioned release.
