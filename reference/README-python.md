# ircapture

Guitar-cab IR capture core: plays log sweeps through the amp and cab, records the mics (plus an optional speaker-terminal reference), and writes trimmed, normalized IRs at every sample rate and length in one pass, with a diagnostics report.

This is the reference implementation of the DSP. It runs from the command line now. The native app should reproduce its output, and `sim_test.py` provides the known-answer test.

**Status:** verified end to end against a simulated rig (`python3 sim_test.py`, all checks pass). It has not yet been run on real hardware. The audio I/O path has only been exercised through a mocked `sounddevice`, so the first real session is also the first real test.

## Install (macOS)

```
pip3 install numpy scipy soundfile sounddevice
```

## Two ways to run a capture

### A. Direct: the script drives the interface

```
python3 ircapture.py devices
python3 ircapture.py level   --device 3 --out-ch 1 --in-ch 1,2,3 --ref-ch 8 --names SM57,R121,Room
python3 ircapture.py capture --device 3 --out-ch 1 --in-ch 1,2,3 --ref-ch 8 --names SM57,R121,Room \
        --name 412_Greenback_posA --notes "57 1in off cap edge; 121 6in center; room 3m"
```

**`level`** loops 1.5 s sweeps and prints, for each input, the recorded peak, the dB to change to reach the target, and H2/H3:
- Set the amp to the loudness you want.
- Turn each preamp until its line reads about 0 dB.
- If H2 or H3 is above about -30 dB, lower the level (`--level`) or the amp volume. An IR is linear, so pushing the speaker gains nothing.

**`capture`** takes about 45 s with the defaults: 5 sweeps of 6 s, the first discarded. It saves the raw recording, so you can re-process it later with different export settings.

### B. Through Logic, with no audio code in the loop

1. `python3 ircapture.py make-signal --out sweeps.wav`. This writes `sweeps.wav` and `sweeps.json`, at 96 kHz by default.
2. In a 96 kHz Logic project, put `sweeps.wav` at bar 1 on a track sent to the output that feeds the amp. Record the mic tracks and the reference track while it plays.
3. Export the tracks as separate WAVs from the project start.
4. Process them:

```
python3 ircapture.py process --signal sweeps.json \
        --rec SM57.wav R121.wav Room.wav Ref.wav --ref 4 --names SM57,R121,Room --name 412_posA
```

The processing finds the sweeps itself, so recording latency and where the region starts don't matter. All inputs must be on the same interface, so that they share one clock.

## The reference tap

Feed the speaker-terminal voltage, padded about 20 dB (for example 10 kΩ series and 1.1 kΩ shunt), into a line input.

IRs are then voltage→SPL: speaker, mic and room only. This makes them independent of the power amp, and they're the correct pair for a reactive-load front end. The simulation shows what happens without it: driving with a tube amp (8 Ω Zout) bakes about 5 dB of impedance bump at resonance into a sweep-referenced IR.

For bridged amps, where neither terminal is ground, or if a ground loop shows up, use a differential input or an isolation transformer.

Without `--ref`, IRs are sweep-referenced and include the amp's response.

## Output

```
ir_out/<name>/report.json
ir_out/<name>/raw/                     recording + sweep spec   (capture only)
ir_out/<name>/set/<rate>k/<name>_<mic>_<rate>k_<bits>_<len>.wav
ir_out/<name>/individual/...           (if --trim set,individual)
```

**Defaults:**
- **Rates:** 44.1, 48, 88.2 and 96 kHz.
- **Lengths:** full (500 ms), 1024, 2048 and 4096 samples.
- **Bit depth:** 24-bit.

Change them with `--rates`, `--lengths`, `--full-ms` and `--bits 16,24,32f`.

**Everything comes from one capture.** Every rate is resampled from it, and gain is matched across rates. A plain resample makes a 96k IR about 6.8 dB louder than the same IR at 44.1k, because convolution gain scales with tap count. Because of that matching, only the loudest file in a set reaches the `--peak` level.

**Trim modes:**
- **`set`** (the default) trims all mics with one offset and normalizes them with one gain. Time-of-flight and level between mics survive, so they blend like the real mics did.
- **`individual`** trims and normalizes each mic on its own.

## Reading the report

| Field | Meaning |
|---|---|
| `noise_floor_db` | Noise in the averaged IR, re its peak. It's measured from sweep-to-sweep residuals, so drift counts as noise too. Each doubling of sweeps buys about 3 dB. |
| `tail_above_noise_ms` | How far the IR stays 6 dB above the noise. Beyond this, a longer "full" IR is just noise. |
| `sweep_level_spread_db` | Level difference between sweeps. If it's well over 0.1 dB, something moved or warmed up. |
| `sweep_min_correlation` | Lowest match between any one sweep and the average. |
| `harmonics_db` | H2 to H5 energy relative to the linear IR, over 50 ms. This is a broadband indicator, not THD at a frequency. |
| `arrival_ms` | First arrival, relative to the speaker terminals in reference mode. |
| `delay_vs_first_mic_ms` | Arrival relative to the earliest mic. |

## Porting notes (native app)

The DSP is plain functions with no state, in this order: `make_sweep` → `inverse_filter` → `deconvolve` → `locate_impulses` → `analyse` (averaging, diagnostics, `divide_by_reference`) → `export`.

A Swift app needs:
- **Audio I/O:** AVAudioEngine or CoreAudio, with channel maps.
- **FFTs:** Accelerate/vDSP.
- **Resampling:** a polyphase resampler (`resample_poly`, Kaiser window). AVAudioConverter is an option, but check its gain and alignment against this code.

Keep `sim_test.py`'s rig as the golden test: the port should match this implementation's files within a small tolerance.
