# IR Capture

A Mac app for capturing guitar-cab impulse responses with as little fuss as a ToneX capture: set up the mics, set the levels, press one button, and get trimmed IRs at every common sample rate and length.

It uses the same processing as the **Cab IR Capture** web page and the Python reference in `reference/`. CI checks it against both on every build.

> **Status:** the processing is verified against a simulated rig (fake amp, cab, two mics and a reference tap, with known answers). The app's audio recording has **not yet been tested on real hardware**. The first real capture is also the app's first real test.

## Get the app

1. Go to the **[Releases page](https://github.com/0x5E3/IR-Capture/releases/tag/latest)**.
2. Under **Assets**, click **IR-Capture.zip**. It downloads to your Downloads folder.
3. Double-click the zip. **IR Capture** appears next to it.
4. Drag **IR Capture** into your **Applications** folder.

### First launch (the app isn't signed by Apple yet)

1. Double-click **IR Capture**. macOS says it can't check it for malicious software. Click **Done** (or **Cancel**).
2. Open **System Settings › Privacy & Security**. Scroll down to the message about IR Capture and click **Open Anyway**. Enter your password if asked.
3. Click **Open** in the next box.
4. When the app first records, macOS asks if IR Capture may use the microphone. Click **Allow**. That covers every input on your interface.

You only do this once per download. A newer build needs steps 1–3 again.

If you clicked Don't Allow for the microphone: **System Settings › Privacy & Security › Microphone**, turn on IR Capture, then quit and reopen the app.

## Two ways to capture

**Capture with the app** (one button, no Logic):
1. Pick the interface, the sample rate, the output that feeds the power amp, and what's on each input (mic name, or the reference tap).
2. Click **Start level check**. Short sweeps loop while you set each preamp until it says OK. Click **Stop level check**.
3. Name the capture and click **Capture**. About 45 seconds later the results appear, with **Show in Finder**.

**Use Logic recordings** (same as the web page):
1. Save the test signal.
2. Record it in Logic, following the steps on screen.
3. Drag the exported WAVs in and click **Make IRs**.

Files land in **Music › IR Captures** unless you pick another folder:

```
<capture>/report.json                       diagnostics (send this to Claude)
<capture>/raw/                              the raw recording and sweep settings (app captures)
<capture>/set/<rate>/<capture>_<mic>_<rate>_<bits>_<length>.wav
<capture>/individual/...                    if "Trim each mic" is ticked
```

## The reference tap (recommended)

Pad the speaker-terminal voltage by about 20 dB (for example 10 kΩ in series and 1.1 kΩ to ground) into a line input, and mark that input **Reference tap**. The IRs are then speaker, mic and room only, whatever power amp drives the cab. Without it, a tube amp bakes about 5 dB of impedance bump into the IR. For a bridged output, or if the tap hums, use an isolation transformer or a balanced input.

## For developers

```
swift build -c release            # IRCaptureCore, ircapture-cli, IRCaptureApp
swift test                        # unit tests
cd reference && python3 sim_test.py && python3 compare_swift.py ../.build/release/ircapture-cli sim_out
scripts/make_app.sh               # macOS: dist/IR-Capture.zip
```

- `Sources/IRCaptureCore`: the DSP, a line-for-line port of `reference/web/dsp.js`, which is itself a port of `reference/ircapture.py`. Plain Swift, so it builds and tests on Linux too. Keep all three in step.
- `Sources/ircapture-cli`: `make-signal` and `process`, used by the golden test.
- `Sources/IRCaptureApp`: SwiftUI app. `DuplexIO.swift` plays and records through one AUHAL unit on one device, so input and output share a clock.
- `reference/`: the Python reference, the simulated rig (`sim_test.py`), the web page source, and `compare_swift.py`.
- CI (`.github/workflows/build.yml`) runs on macOS: simulated rig → page DSP vs Python → universal build → unit tests → Swift vs Python golden test → app bundle → the `latest` release.
