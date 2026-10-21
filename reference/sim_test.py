#!/usr/bin/env python3
"""
End-to-end check of ircapture against a simulated rig with known answers.

Simulated chain (96 kHz):
  interface out -> tube power amp (40 Hz HPF, 16 kHz LPF, Zout = 8 ohm)
  -> speaker with a real impedance curve (resonance + voice-coil inductance),
     so the terminal voltage gets the usual tube-amp bump
  -> mild speaker nonlinearity (H2/H3)
  -> two mics: close (0.15 ms) and room (8.75 ms + reflections + 0.4 s tail)
  -> noise on every input, identical 317-sample interface latency
  plus a reference channel: terminal voltage through a 20 dB pad.

Truth for each mic is its voltage->SPL impulse response, which doesn't depend
on the amp. Checks:
  1. reference mode recovers the truth (shape and time-of-flight)
  2. sweep mode bakes in the amp + impedance bump (what the reference fixes)
  3. distortion is detected and windowed out
  4. 44.1k export matches the 96k capture
  5. the hardware commands run end-to-end through a mocked sounddevice
"""
import math
import shutil
import sys
import types
from pathlib import Path

import numpy as np
import soundfile as sf
from scipy import signal

sys.path.insert(0, str(Path(__file__).parent))
import ircapture as irc  # noqa: E402

FS = 96000
LAT = 317
rng = np.random.default_rng(1)


# ------------------------------------------------------------------ rig
def biquad(kind, f0, q, gain_db=0.0, fs=FS):
    A = 10 ** (gain_db / 40)
    w = 2 * np.pi * f0 / fs
    al = np.sin(w) / (2 * q)
    c = np.cos(w)
    if kind == "hp":
        b = [(1 + c) / 2, -(1 + c), (1 + c) / 2]
        a = [1 + al, -2 * c, 1 - al]
    elif kind == "peak":
        b = [1 + al * A, -2 * c, 1 - al * A]
        a = [1 + al / A, -2 * c, 1 - al / A]
    return np.array(b) / a[0], np.array(a) / a[0]


def speaker_ir(n=8192):
    d = np.zeros(n)
    d[0] = 1
    for b, a in [biquad("hp", 95, 0.8), biquad("peak", 2500, 1.5, 4.0),
                 biquad("peak", 3600, 4.0, -6.0), biquad("peak", 700, 0.7, -2.0)]:
        d = signal.lfilter(b, a, d)
    sos = signal.butter(4, 5500, "lp", fs=FS, output="sos")
    return signal.sosfilt(sos, d)


def delayed(h, ms, n):
    out = np.zeros(n)
    k = int(round(ms / 1000 * FS))
    out[k:k + len(h)] = h[:n - k]
    return out


h_spk = speaker_ir()
NT = int(0.7 * FS)
H_CLOSE = delayed(h_spk, 0.15, NT)
room = np.zeros(NT)
for ms, g in [(8.75, 0.5), (11.2, -0.32), (14.9, 0.27), (21.6, 0.22), (29.0, -0.15)]:
    room[int(ms / 1000 * FS)] += g
t = np.arange(NT) / FS
diffuse = rng.standard_normal(NT) * 0.06 * np.exp(-6.91 * t / 0.4) * (t > 0.012)
room += signal.sosfilt(signal.butter(2, 6000, "lp", fs=FS, output="sos"), diffuse)
H_ROOM = signal.fftconvolve(room, h_spk)[:NT]

RE, LE, RES, FS0, QMS, ZOUT = 6.5, 0.5e-3, 40.0, 100.0, 4.0, 8.0


def z_speaker(f):
    f = np.maximum(f, 1e-3)
    return RE + 1j * 2 * np.pi * f * LE + RES / (1 + 1j * QMS * (f / FS0 - FS0 / f))


def rig(x):
    """interface output (N,) -> (close, room, ref) recordings."""
    v = signal.sosfilt(signal.butter(2, 40, "hp", fs=FS, output="sos"), x)
    v = signal.sosfilt(signal.butter(2, 16000, "lp", fs=FS, output="sos"), v) * 20.0
    N = len(v)
    F = np.fft.rfft(v)
    f = np.fft.rfftfreq(N, 1 / FS)
    zs = z_speaker(f)
    vt = np.fft.irfft(F * zs / (zs + ZOUT), N)          # terminal voltage
    pk = np.abs(vt).max() or 1.0
    u = vt / pk
    drive = (u + 0.02 * u ** 2 + 0.012 * u ** 3) * pk     # speaker nonlinearity
    close = signal.fftconvolve(drive, H_CLOSE)[:N] * 0.06
    rm = signal.fftconvolve(drive, H_ROOM)[:N] * 0.012
    ref = vt * 0.1 / 20 * 4                              # 20 dB pad, into line in
    out = []
    for sig_, noise_db in [(close, -78), (rm, -74), (ref, -90)]:
        s = sig_ + rng.standard_normal(N) * 10 ** (noise_db / 20)
        out.append(np.concatenate([np.zeros(LAT), s[:-LAT]]))
    return np.stack(out)


# ------------------------------------------------------------------ metrics
FC = np.geomspace(80, 5000, 120)


def smooth_db(h, frac=6, nfft=1 << 18):
    P = np.abs(np.fft.rfft(h, nfft)) ** 2
    f = np.fft.rfftfreq(nfft, 1 / FS)
    out = []
    for c in FC:
        m = (f >= c * 2 ** (-0.5 / frac)) & (f < c * 2 ** (0.5 / frac))
        out.append(10 * np.log10(P[m].mean()))
    return np.array(out)


def shape_error(h, truth):
    d = smooth_db(h) - smooth_db(truth)
    d -= np.median(d)
    return d


def check(cond, msg):
    print(("PASS " if cond else "FAIL ") + msg)
    return bool(cond)


# ------------------------------------------------------------------ run
def main():
    ok = True
    work = Path(__file__).parent / "sim_out"
    shutil.rmtree(work, ignore_errors=True)
    work.mkdir()

    spec = irc.SweepSpec(fs=FS)
    x = irc.make_test_signal(spec)
    rec = rig(x)
    print(f"test signal {len(x) / FS:.1f} s, recorded channels peak "
          + ", ".join(f"{20 * math.log10(np.abs(r).max()):.1f}" for r in rec) + " dBFS\n")

    # -- 1. reference mode
    res = irc.analyse(rec, spec, ["Close", "Room"], 2, irc.ProcessOptions())
    print(irc.summary_text(res), "\n")
    t0 = res["t0"]
    for name, truth in [("Close", H_CLOSE), ("Room", H_ROOM)]:
        e = shape_error(res["irs"][name], truth)
        ok &= check(np.abs(e).max() < 0.5,
                    f"ref mode {name}: response matches truth within {np.abs(e).max():.2f} dB (80 Hz-5 kHz, 1/6 oct)")
    true_close = irc.onset_index(H_CLOSE, 20) / FS * 1000
    true_room = irc.onset_index(H_ROOM, 20) / FS * 1000
    d = res["diagnostics"]
    ok &= check(abs(d["Close"]["arrival_ms"] - true_close) < 0.02,
                f"close arrival {d['Close']['arrival_ms']:.3f} ms vs true {true_close:.3f} ms "
                "(latency cancelled by reference)")
    ok &= check(abs(d["Room"]["delay_vs_first_mic_ms"] - (true_room - true_close)) < 0.02,
                f"room-to-close delay {d['Room']['delay_vs_first_mic_ms']:.3f} ms vs true "
                f"{true_room - true_close:.3f} ms")
    # time-domain shape of the close IR
    hc = res["irs"]["Close"][t0:t0 + 4096]
    tc = H_CLOSE[:4096]
    corr = np.dot(hc, tc) / (np.linalg.norm(hc) * np.linalg.norm(tc))
    ok &= check(corr > 0.999, f"close IR waveform correlation with truth {corr:.5f}")

    # -- 2. sweep mode on the same recording, reference ignored
    res_s = irc.analyse(rec[:2], spec, ["Close", "Room"], None, irc.ProcessOptions())
    e_s = shape_error(res_s["irs"]["Close"], H_CLOSE)
    i100 = int(np.argmin(np.abs(FC - 100)))
    i1k = int(np.argmin(np.abs(FC - 1000)))
    bump = e_s[i100] - e_s[i1k]
    zs = z_speaker(np.array([100.0, 1000.0]))
    div = 20 * np.log10(np.abs(zs / (zs + ZOUT)))
    ok &= check(bump > 3, f"sweep mode bakes in {bump:.1f} dB at 100 Hz vs 1 kHz "
                f"(impedance divider alone predicts {div[0] - div[1]:.1f} dB)")

    # -- 3. distortion
    h2 = d["Close"]["harmonics_db"]["H2"]
    ok &= check(h2 is not None and -50 < h2 < -25, f"H2 detected at {h2} dB on the close mic")

    # -- 4. export
    eo = irc.ExportOptions(bits=("16", "24", "32f"), trim=("set", "individual"))
    files = irc.export(res, "sim", work, eo)
    n_expected = 2 * 4 * 4 * 3 * 2
    ok &= check(len(files) == n_expected, f"{len(files)} files written (expected {n_expected})")
    a96, _ = sf.read(work / "sim/set/96k/sim_Close_96k_32f_full.wav")
    a44, r44 = sf.read(work / "sim/set/44.1k/sim_Close_44.1k_32f_full.wav")
    f96 = np.fft.rfftfreq(1 << 17, 1 / 96000)
    f44 = np.fft.rfftfreq(1 << 17, 1 / r44)
    band = np.geomspace(100, 15000, 60)
    m96 = np.interp(band, f96, 20 * np.log10(np.abs(np.fft.rfft(a96, 1 << 17)) + 1e-12))
    m44 = np.interp(band, f44, 20 * np.log10(np.abs(np.fft.rfft(a44, 1 << 17)) + 1e-12))
    ok &= check(np.abs(m96 - m44).max() < 0.2,
                f"44.1k export matches 96k within {np.abs(m96 - m44).max():.3f} dB (100 Hz-15 kHz)")
    n1024, _ = sf.read(work / "sim/set/48k/sim_Room_48k_24_1024.wav")
    ok &= check(len(n1024) == 1024, "1024-sample file has 1024 samples")
    # set trim keeps the mic delay, individual trim removes it
    c_set, _ = sf.read(work / "sim/set/96k/sim_Close_96k_32f_full.wav")
    r_set, _ = sf.read(work / "sim/set/96k/sim_Room_96k_32f_full.wav")
    r_ind, _ = sf.read(work / "sim/individual/96k/sim_Room_96k_32f_full.wav")
    gap_set = (irc.onset_index(r_set, 20) - irc.onset_index(c_set, 20)) / 96
    gap_ind = irc.onset_index(r_ind, 20) / 96
    ok &= check(abs(gap_set - (true_room - true_close)) < 0.02,
                f"set-trimmed files keep {gap_set:.3f} ms room delay; individual trim starts at {gap_ind:.3f} ms")
    peaks = [np.abs(sf.read(f)[0]).max() for f in files if "/set/" in str(f)]
    ok &= check(abs(max(peaks) - 10 ** (-1 / 20)) < 2e-3 and np.abs(r_set).max() < np.abs(c_set).max(),
                "set normalisation: loudest file at -1 dBFS, room mic level relative to close kept")

    # -- 5. hardware path through a mocked sounddevice
    fake = types.ModuleType("sounddevice")

    def playrec(data, samplerate, input_mapping, output_mapping, device=None, dtype=None):
        assert samplerate == FS and output_mapping == [1]
        y = rig(np.asarray(data)[:, 0].astype(np.float64))
        chan = {1: y[0], 2: y[1], 4: y[2]}
        return np.stack([chan[c] for c in input_mapping], axis=1).astype(np.float32)

    fake.playrec = playrec
    fake.wait = lambda: None
    fake.query_devices = lambda: "0 Fake Interface, 8 in / 8 out"
    sys.modules["sounddevice"] = fake
    print("\n-- level (mocked interface)")
    irc.main(["level", "--in-ch", "1,2", "--ref-ch", "4", "--names", "Close,Room", "--count", "2"])
    print("\n-- capture (mocked interface)")
    irc.main(["capture", "--in-ch", "1,2", "--ref-ch", "4", "--names", "Close,Room",
              "--name", "mock", "--outdir", str(work), "--lengths", "full,2048", "--rates", "48000,96000"])
    ok &= check((work / "mock/set/48k/mock_Close_48k_24_2048.wav").exists()
                and (work / "mock/raw/mock_recording.wav").exists()
                and (work / "mock/report.json").exists(), "capture command wrote raw recording, IRs and report")

    # -- 6. offline path: the files Logic would hand back
    sig = work / "sweeps.wav"
    irc.main(["make-signal", "--out", str(sig)])
    xs, _ = sf.read(sig)
    y = rig(xs)
    for nm, row in zip(["close", "room", "ref"], y):
        sf.write(work / f"logic_{nm}.wav", row.astype(np.float32), FS, subtype="FLOAT")
    print("\n-- process (separate mono files, as exported from Logic)")
    irc.main(["process", "--signal", str(sig.with_suffix(".json")), "--rec",
              str(work / "logic_close.wav"), str(work / "logic_room.wav"), str(work / "logic_ref.wav"),
              "--ref", "3", "--names", "Close,Room", "--name", "logic", "--outdir", str(work)])
    lc, _ = sf.read(work / "logic/set/96k/logic_Close_96k_24_full.wav")
    e = shape_error(lc, H_CLOSE)
    ok &= check(np.abs(e).max() < 0.5, f"offline (Logic) path matches truth within {np.abs(e).max():.2f} dB")

    print("\nALL PASS" if ok else "\nSOME CHECKS FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
