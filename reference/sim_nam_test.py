#!/usr/bin/env python3
"""
Known-answer test for namprep against a simulated rig.

Signal: the real TONE3000 sweep (T3K-sweep-v3.wav) if --signal points at it,
otherwise a stand-in with the same layout (same envelope, the two clicks at
10.5 s and 11.5 s, the 9 s block repeated at the end). CI uses the stand-in;
the sweep file isn't redistributed here.

Simulated amp: 80 Hz high-pass, asymmetric tube-style clipping, 6 kHz
low-pass, phase-inverting, plus noise, optional 60 Hz hum, optional gain
drift. Mics: the amp output through a cab, with 0.5 ms (close) and 3.1 ms
(room, with reflections) of air.

Truth: the amp's output with no latency, shifted by the amp's own click
onset (the first samples of an IIR filter's impulse response are tiny).
"""
import argparse
import math
import shutil
import sys
from pathlib import Path

import numpy as np
import soundfile as sf
from scipy import signal

sys.path.insert(0, str(Path(__file__).parent))
import namprep as nm  # noqa: E402

FS = 48000
rng = np.random.default_rng(7)


def stand_in_signal():
    env = 10 ** (nm.ENV / 20)
    x = np.zeros(nm.N)
    noise = rng.standard_normal(len(env) * nm.EB)
    shaped = signal.sosfilt(signal.butter(2, [80, 5000], "bp", fs=FS, output="sos"), noise)
    shaped /= np.sqrt((shaped ** 2).mean())
    for b, e in enumerate(env):
        if e > 1.1e-5:
            x[b * nm.EB:(b + 1) * nm.EB] = shaped[b * nm.EB:(b + 1) * nm.EB] * e
    # 26 s .. end: guitar-ish content
    t = np.arange(nm.N) / FS
    body = 0.3 * np.sin(2 * np.pi * 110 * t * (1 + 0.5 * np.sin(2 * np.pi * 0.05 * t))) \
        + 0.1 * signal.sosfilt(signal.butter(2, [100, 4000], "bp", fs=FS, output="sos"), rng.standard_normal(nm.N))
    s = len(env) * nm.EB
    x[s:] = body[s:]
    x[nm.BLIPS[0] - 2000:nm.BLIPS[1] + 2000] = 0
    x[nm.NOISE[0]:nm.BLIPS[0]] = 0
    for b in nm.BLIPS:
        x[b] = 0.99
    x[nm.N - nm.VAL:] = x[:nm.VAL]
    x[:nm.FIRST] = 0
    x[nm.LAST + 1:nm.N - nm.VAL] = 0
    return np.clip(x, -0.99, 0.99)


HP = signal.butter(1, 80, "hp", fs=FS, output="sos")
LP = signal.butter(2, 6000, "lp", fs=FS, output="sos")


def amp(x, gain=8.0, out=0.35, drift_db=0.0):
    u = signal.sosfilt(HP, x) * gain
    if drift_db:
        u *= 10 ** (np.linspace(0, drift_db, len(u)) / 20)
    y = np.tanh(u + 0.3) - math.tanh(0.3)
    y = signal.sosfilt(LP, y)
    return -out * y                       # phase-inverting, like many amps


def cab_ir(n=4096):
    d = np.zeros(n)
    d[0] = 1
    d = signal.sosfilt(signal.butter(2, 90, "hp", fs=FS, output="sos"), d)
    d = signal.sosfilt(signal.butter(4, 5000, "lp", fs=FS, output="sos"), d)
    return d


def delayed(h, ms, n):
    k = int(round(ms / 1000 * FS))
    out = np.zeros(n)
    out[k:k + len(h)] = h[:n - k]
    return out


H = cab_ir()
H_CLOSE = delayed(H, 0.5, 8192)
H_ROOM = delayed(H, 3.1, 8192) * 0.4
H_ROOM[int(0.0071 * FS):int(0.0071 * FS) + len(H)] += -0.15 * H[:8192 - int(0.0071 * FS)]


def record(y, lead, tail, noise_db=-85, hum_db=None):
    """Put y into a longer recording: `lead` samples before (negative: start late)."""
    total = lead + len(y) + tail
    r = np.zeros(total)
    if lead >= 0:
        r[lead:lead + len(y)] = y
    else:
        r[:len(y) + lead] = y[-lead:]
        r = r[:len(y) + lead + tail]
    r = r + rng.standard_normal(len(r)) * 10 ** (noise_db / 20)
    if hum_db is not None:
        t = np.arange(len(r)) / FS
        r += 10 ** (hum_db / 20) * (np.sin(2 * np.pi * 60 * t) + 0.5 * np.sin(2 * np.pi * 120 * t + 1))
    return r


def onset(h):
    a = np.abs(h)
    return int(np.argmax(a >= 0.1 * a.max()))


def check(cond, msg):
    print(("PASS " if cond else "FAIL ") + msg)
    return bool(cond)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--signal", help="path to T3K-sweep-v3.wav (optional)")
    a = ap.parse_args()
    if a.signal:
        x, fs = sf.read(a.signal)
        assert fs == FS and len(x) == nm.N
        print("signal: real TONE3000 sweep file")
    else:
        x = stand_in_signal()
        print("signal: stand-in with the v3 layout")
    ok = True
    work = Path(__file__).parent / "sim_nam_out"
    shutil.rmtree(work, ignore_errors=True)
    work.mkdir()
    if not a.signal:
        # The app's direct-capture smoke test plays this file through a simulated interface.
        sf.write(work / "standin_signal.wav", x, FS, subtype="PCM_24")

    imp = np.zeros(4000)
    imp[0] = 0.99
    amp_on = onset(amp(imp))
    y_amp = amp(x)
    truth = np.concatenate([y_amp[amp_on:], np.zeros(amp_on)])

    # 1. amp only, 1234 samples of latency, 0.4 s of tail
    LAT = 1234
    rec = record(y_amp, LAT, int(0.4 * FS))
    res = nm.prepare([("Suhr", rec, FS)], "amp")
    d = res["diagnostics"]["Suhr"]
    out = res["outputs"]["Suhr"]
    print(d, res["warnings"])
    ok &= check(d["offset_samples"] == LAT + amp_on,
                f"amp: offset {d['offset_samples']} = latency {LAT} + amp onset {amp_on}")
    err = np.abs(out - truth)[:nm.N - 2000].max()
    ok &= check(len(out) == nm.N and err < 1e-3,
                f"amp: output is {len(out)} samples and matches the true amp output (max diff {err:.1e}, noise ~1e-4)")
    ok &= check(d["polarity"] == "inverted", "amp: polarity inversion reported")
    ok &= check(abs(d["drift_samples"]) == 0 and d["replicate_esr"] < 1e-4,
                f"amp: no drift, replicate ESR {d['replicate_esr']}")
    ok &= check(not res["warnings"], f"amp: clean take gives no warnings {res['warnings']}")
    ok &= check(d["hum_hz"] is None, "amp: no hum reported on a clean take")

    files = nm.write_outputs(res, "JCM800 ch2", work)
    y_read, fs_read = sf.read(files[0])
    info = sf.info(files[0])
    ok &= check(fs_read == 48000 and info.subtype == "PCM_24" and info.channels == 1 and len(y_read) == nm.N,
                f"amp: file is mono 48 kHz {info.subtype}, {len(y_read)} samples")
    q = np.floor(rec * 8388608 + 0.5) / 8388608         # a 24-bit recording passes through bit for bit
    res_q = nm.prepare([("q", q, FS)], "amp")
    nm.write_outputs({**res_q, "outputs": res_q["outputs"]}, "q", work)
    yq, _ = sf.read(work / "q/q_q.wav")
    s = res_q["diagnostics"]["q"]["offset_samples"]
    ok &= check(np.array_equal(yq[:len(q) - s], q[s:s + nm.N][:len(q) - s]),
                "amp: a 24-bit recording passes through bit for bit")

    # 2. Logic with latency compensation: recording starts 200 samples late, stops 0.3 s early
    rec2 = record(y_amp, -200, 0)[:nm.N - 200 - int(0.3 * FS)]
    r2 = nm.prepare([("late", rec2, FS)], "amp")
    d2 = r2["diagnostics"]["late"]
    ok &= check(d2["offset_samples"] == -200 + amp_on and d2.get("padded_samples", 0) > 0,
                f"late start / early stop: offset {d2['offset_samples']}, padded {d2.get('padded_samples')}")

    # 3. clipping
    rec3 = np.clip(record(y_amp * 3.2, 500, 9600), -1, 1)
    r3 = nm.prepare([("hot", rec3, FS)], "amp")
    ok &= check(any("clipped" in w for w in r3["warnings"]), "clipping detected")

    # 4. hum
    r4 = nm.prepare([("hum", record(y_amp, 500, 9600, hum_db=-62), FS)], "amp")
    ok &= check(r4["diagnostics"]["hum"]["hum_hz"] == 60 and any("hum" in w for w in r4["warnings"]),
                f"60 Hz hum detected (share {r4['diagnostics']['hum']['hum_share']})")

    # 5. clock drift: recording runs 3 ppm fast
    rec5 = record(y_amp, 700, 9600)
    t_new = np.arange(int(len(rec5) / (1 + 3e-6))) * (1 + 3e-6)
    rec5 = np.interp(t_new, np.arange(len(rec5)), rec5)
    r5 = nm.prepare([("drift", rec5, FS)], "amp")
    exp = -round(nm.N * 3e-6 * (1 - nm.VAL / nm.N))
    ok &= check(abs(r5["diagnostics"]["drift"]["drift_samples"] - exp) <= 1 and any("clock" in w for w in r5["warnings"]),
                f"clock drift {r5['diagnostics']['drift']['drift_samples']} samples (expected about {exp}) reported")

    # 6. amp changing over the take
    r6 = nm.prepare([("warm", record(amp(x, drift_db=1.5), 700, 9600), FS)], "amp")
    e6 = r6["diagnostics"]["warm"]["replicate_esr"]
    ok &= check(e6 > 0.005 and any("different at the end" in w for w in r6["warnings"]),
                f"amp drift over the take: replicate ESR {e6} flagged")

    # 7. 96 kHz recording
    rec7 = nm.resample_to(record(y_amp, 900, 9600), FS, 96000)
    r7 = nm.prepare([("hi", rec7, 96000)], "amp")
    o7 = r7["outputs"]["hi"]
    c7 = float(np.dot(o7, truth) / (np.linalg.norm(o7) * np.linalg.norm(truth)))
    ok &= check(r7["diagnostics"]["hi"]["offset_samples"] == 900 + amp_on and c7 > 0.9999,
                f"96 kHz recording: resampled, offset {r7['diagnostics']['hi']['offset_samples']}, correlation {c7:.6f}")

    # 8. errors
    for label, bad, want in [("short", rec[:FS * 60], "long"), ("short2", rec[:nm.N - FS * 3], "stops"), ("noise", rng.standard_normal(nm.N + 9600) * 0.1, "couldn't find")]:
        try:
            nm.prepare([(label, bad, FS)], "amp")
            ok &= check(False, f"{label}: should have failed")
        except nm.PrepError as e:
            ok &= check(want in str(e), f"{label}: refused with '{e}'")

    # 9. full chain, two mics
    LAT9 = 611
    mic_c = signal.fftconvolve(y_amp, H_CLOSE)[:nm.N] * 0.9
    mic_r = signal.fftconvolve(y_amp, H_ROOM)[:nm.N] * 1.2
    r9 = nm.prepare([("SM57", record(mic_c, LAT9, 9600, -80), FS), ("Room", record(mic_r, LAT9, 9600, -78), FS)], "full")
    d9 = r9["diagnostics"]
    imp_c = signal.fftconvolve(amp(imp), H_CLOSE)[:4000]
    imp_r = signal.fftconvolve(amp(imp), H_ROOM)[:4000]
    true_c, true_r = LAT9 + onset(imp_c), LAT9 + onset(imp_r)
    print(d9, r9["warnings"])
    ok &= check(d9["SM57"]["offset_samples"] == true_c and d9["Room"]["offset_samples"] == true_r,
                f"two mics: offsets {d9['SM57']['offset_samples']}, {d9['Room']['offset_samples']} (true {true_c}, {true_r})")
    ok &= check(abs(d9["Room"]["delay_vs_first_ms"] - (true_r - true_c) / 48) < 0.03,
                f"two mics: room is {d9['Room']['delay_vs_first_ms']} ms behind the close mic")
    nm.write_outputs(r9, "412 full", work)
    ok &= check((work / "412_full/412_full_SM57.wav").exists() and (work / "412_full/UPLOAD-STEPS.txt").exists(),
                "two mics: one file per mic, plus report and upload steps")

    # recordings for the page/app golden tests
    gold = work / "gold"
    gold.mkdir()
    sf.write(gold / "Suhr.wav", np.clip(rec, -1, 1), FS, subtype="PCM_24")
    sf.write(gold / "SM57.wav", record(mic_c, LAT9, 9600, -80), FS, subtype="PCM_24")
    sf.write(gold / "Room96.wav", nm.resample_to(record(mic_r, LAT9, 9600, -78), FS, 96000), 96000, subtype="FLOAT")
    gs = []
    for f, n in [("Suhr.wav", "Suhr"), ("SM57.wav", "SM57"), ("Room96.wav", "Room")]:
        z, r = sf.read(gold / f)
        gs.append((n, z, r))
    rg = nm.prepare(gs, "full")
    nm.write_outputs(rg, "gold", gold)
    print("\nALL PASS" if ok else "\nSOME CHECKS FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
