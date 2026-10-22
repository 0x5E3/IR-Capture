# IR Capture

A Mac app for capturing guitar-cab impulse responses. Wire the rig, check levels and click Capture. The result is a set of finished IRs in a standard format. The app also records amps for NAM models trained at TONE3000.

The processing is identical to the **Cab IR Capture** web page and the Python reference in `reference/`. CI compares the app against both on every build.

> **Status:** version 1.0.0, pre-release. The processing is verified against a simulated rig (simulated amp, cab, two mics and a reference tap, with known results). The audio recording functions have **not yet been tested on real hardware**. The first real capture is also the first hardware test. Builds are not signed by Apple until the Developer ID is set up (see `docs/SIGNING.md`).

## Get the app

1. Go to the **[Releases page](https://github.com/0x5E3/IR-Capture/releases/tag/latest)**.
2. Under **Assets**, click **IR-Capture.dmg**. The file is saved to the Downloads folder.
3. Double-click the DMG. In the window, drag **IR Capture** onto **Applications**. Wiring diagrams are in **Quick start.pdf** in the same window.
4. Open **IR Capture** from Applications.

### First launch (unsigned builds only)

1. Double-click **IR Capture**. macOS reports that the app cannot be checked for malicious software. Click **Done** (or **Cancel**).
2. Open **System Settings › Privacy & Security**. Scroll down to the message about IR Capture and click **Open Anyway**. Enter the password if requested.
3. Click **Open** in the next dialog.

Repeat steps 1–3 for each new unsigned build. Signed and notarized releases open on the first double-click.

The **Welcome** screen has a button to request recording permission for the interface. Click the button, then click **Allow**. If Don't Allow was clicked: open **System Settings › Privacy & Security › Microphone**, turn on IR Capture, then quit and reopen the app.

## Cab IR

**Record here** (main method):
1. **Connect.** Interface output → amp **FX return** (power amp in) or clean power amp → cab. Do not use the guitar input. Connect the mics to the interface. The wiring diagram is shown in the app. The interface is detected when connected, and the sample rate is set automatically. Enter a name for each mic and select a **Reference source** (None is acceptable).
2. **Set levels.** Click **Check levels**. Room noise is measured for 2 seconds and a clean sweep level is set automatically. Short sweeps are then looped. Adjust each preamp until the meter shows OK.
3. **Capture.** Enter a name, check the **Before you capture** list, and click **Capture**. The results are shown after about 45 seconds.

**Import DAW recordings** (secondary method): save the test signal, record it in Logic, Reaper, Ableton, Pro Tools or GarageBand, and drag the exported WAV files into the app.

Files are saved in **Music › IR Captures** unless another folder is selected:

```
412_V30_PosA/
    412_V30_PosA_SM57.wav          ← Universal: 48 kHz, 24-bit, 500 ms. Load these.
    412_V30_PosA_R121.wav
    README.txt                     description of the files
    report.json                    measurements (send this file to Claude)
    More formats/                  only the sets ticked under Files to make:
        All sample rates/<rate>/…  44.1, 48, 88.2, 96 kHz × 500 ms and 200 ms
        Strymon Iridium/…          96 kHz, 500 ms
        Minimum phase/…            minimum-phase versions of the close mics
        Mixes/…                    two-mic blends (close+close, close+room)
        Custom/<trim>/<rate>/…     the Advanced matrix
    Raw take/                      unprocessed recording + settings
```

**Re-export** (in the results, or **Re-export a past capture…**) makes other formats from the raw take without a new recording.

Each IR is made with its main peak positive, so mics blend without cancellation. An inverted mic is flipped, and the flip is listed in the results. To turn this off, select **Advanced file options › Keep polarity as recorded**.

## Amp (NAM)

The app prepares recordings for NAM training at [TONE3000](https://www.tone3000.com/capture). Models are not trained in the app. Both methods use the TONE3000 sweep file, `T3K-sweep-v3.wav` (to locate it, click **Find it in Downloads**).

**Record here:** select the capture type (amp only or full chain), connect interface → reamp box → amp, check levels (live meters, target −8 dBFS), then click **Record** (3 min 12 s). Playback and recording use the same interface, so there is no clock drift. The raw recording is kept.

**Import DAW recordings:** record the sweep in a 48 kHz DAW project and drag the exported WAV files into the app.

Output: `<capture>/<capture>_<input>.wav` (mono, 48 kHz, 24-bit), `report.json` and `UPLOAD-STEPS.txt`. Use amp-only models with IRs captured with a reference. The load box line out already includes the speaker impedance peak.

## Help and support

**Help** menu: Quick Start, Wiring, The Reference Tap (with a pad parts list), Troubleshooting, Contact Support (a mail draft with the app version, macOS version, interface and the latest report attached), Show Log File (`~/Library/Logs/IR Capture/`).

## Test status

- Simulated only: all processing, polarity, export targets and re-export (CI, every build).
- In CI on a Mac: app launch, processing of simulated recordings through the app window, diagram rendering, help pages. NAM recording is tested with a simulated interface.
- Not yet tested on a real interface: the level check, the noise check, automatic sweep level, Capture, NAM Record, dropout detection, sample-rate switching and restoring.

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
- `Sources/ircapture-cli`: `make-signal`, `process` (`--targets`, including `minphase` and `mixes`, `--keep-polarity`, `--raw-take`), `reexport` and `nam-prep`, used by the golden tests.
- `Sources/IRCaptureApp`: SwiftUI app. `DuplexIO.swift` plays and records through one AUHAL unit on one device, so input and output share a clock; it also reports input timestamp gaps and processor overloads (dropouts). `Support.swift` has the product name, support address, log and Contact Support.
- Signing and notarization: `scripts/make_app.sh`, `scripts/notarize.sh`, `scripts/IRCapture.entitlements`, and the CI steps that run when the Apple secrets exist. Setup: `docs/SIGNING.md`.
- CI (`.github/workflows/build.yml`) runs on macOS: simulated rig → page DSP vs Python → universal build → unit tests → Swift vs Python golden tests → app bundle → smoke tests and screenshots → diagrams and Quick start PDF → DMG → the `latest` release. A `v*` tag makes a signed, versioned release.
