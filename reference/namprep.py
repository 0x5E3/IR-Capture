#!/usr/bin/env python3
"""
namprep - turn a recording of the NAM v3 training signal into upload-ready
files for NAM training (TONE3000's capture page, NAM's trainer, or Colab).

The user plays TONE3000's sweep file (NAM's standard v3 training signal,
T3K-sweep-v3.wav) through a reamp box into the amp, and records either the
load box's line out (amp only) or one or more mics on the cab (full chain).
From each recorded channel this writes a mono, 48 kHz, 24-bit WAV that is
exactly as long as the training signal and lined up with it to the sample,
plus a report.

Steps, per channel
  1. Resample to 48 kHz if the recording isn't (windowed-sinc, same as the
     IR export).
  2. Coarse position: correlate the recording's 10 ms log-envelope with the
     signal's (stored in nam_v3_layout.json, so the sweep file isn't needed).
     Distortion and polarity don't change where the sound and silences are.
  3. Fine position: the two one-sample clicks at 10.5 s and 11.5 s. The first
     sample of each click's response that rises above max(10% of the click's
     peak, 2x the noise peak) marks the alignment. The two clicks must agree.
  4. Cut exactly 9,120,000 samples from there (zero-padding the silent edges
     if the recording starts or stops a little early).
  5. Checks: the 9 s block that opens and closes the signal is compared in
     the output (drift between playback and recording clocks, and how much
     the amp changed over the 3 minutes: "replicate ESR"); peak level and
     clipping; noise and hum in the silent gap before the clicks.

Command
  python3 namprep.py --name JCM800_ch2 --kind amp Suhr.wav
  python3 namprep.py --name 412_JCM800 --kind full --names SM57,R121 SM57.wav R121.wav
"""
from __future__ import annotations

import argparse
import json
import math
import struct
import sys
from datetime import datetime
from pathlib import Path

import numpy as np

VERSION = "0.1"
FS = 48000
_LAYOUT = json.loads((Path(__file__).parent / "nam_v3_layout.json").read_text())
N = _LAYOUT["length"]                      # 9,120,000 samples (190 s)
BLIPS = tuple(_LAYOUT["blips"])            # 504000, 552000
VAL = _LAYOUT["validation_length"]         # 432000: first 9 s == last 9 s
NOISE = (420000, 498000)                   # 8.75-10.375 s: silent in the signal (NAM uses 492000-498000)
FIRST, LAST = _LAYOUT["first_sound"], _LAYOUT["last_sound"]
EB = _LAYOUT["env_block"]                  # 480 samples = 10 ms
ENV = np.array(_LAYOUT["env_db"], dtype=np.float64)

CLICK_WIN = 960          # search +-20 ms around the coarse click position
DRIFT_SEG = (24000, 360000)   # inside the 9 s block, used for the drift check
DRIFT_MAX = 48           # +-1 ms
MIN_ENV_CORR = 0.6


class PrepError(Exception):
    pass


# ---------------------------------------------------------------- resampling
# Same windowed-sinc (Kaiser) resampler as the page and the app, so all three
# give the same samples.
_KB, _ZC, _KT = 8.6, 32, 8192


def _bessel_i0(x):
    s = t = 1.0
    for k in range(1, 60):
        t *= (x / (2 * k)) ** 2
        s += t
        if t < 1e-17 * s:
            break
    return s


_i0 = _bessel_i0(_KB)
_KTAB = np.array([_bessel_i0(_KB * math.sqrt(1 - min(1, i / _KT) ** 2)) / _i0 for i in range(_KT + 2)])


def _kernel(d: np.ndarray, c: float, half_w: float) -> np.ndarray:
    a = c * d
    with np.errstate(invalid="ignore", divide="ignore"):
        sinc = np.where(a == 0, 1.0, np.sin(np.pi * a) / (np.pi * a))
    p = np.abs(d) / half_w * _KT
    i = np.clip(np.floor(p).astype(np.int64), 0, _KT)
    f = p - i
    return c * sinc * (_KTAB[i] * (1 - f) + _KTAB[i + 1] * f)


def resample_to(x: np.ndarray, fs: int, rate: int) -> np.ndarray:
    """Polyphase form of the windowed-sinc resampler: output m sits at input
    time t = m * fs / rate and sums every input within +-32/c samples."""
    x = np.asarray(x, dtype=np.float64)
    if rate == fs:
        return x.copy()
    g = math.gcd(int(fs), int(rate))
    P, Q = rate // g, fs // g             # P outputs per Q inputs
    ratio = rate / fs
    c = min(1.0, ratio) * 0.97
    half_w = _ZC / c
    n = int(math.floor(len(x) * ratio + 0.5))
    y = np.zeros(n)
    W = int(math.ceil(2 * half_w)) + 2
    padl = W + 2
    xp = np.concatenate([np.zeros(padl), x, np.zeros(padl + Q * 2 + W)])
    for r in range(min(P, n)):
        cnt = (n - 1 - r) // P + 1
        t = r / ratio
        lo = math.ceil(t - half_w)
        hi = math.floor(t + half_w)
        j = np.arange(lo, hi + 1)
        w = _kernel(t - j, c, half_w)
        acc = np.zeros(cnt)
        base = padl + Q * np.arange(cnt)
        for jj, wj in zip(j, w):
            acc += wj * xp[base + jj]
        y[r::P] = acc
    return y


# ---------------------------------------------------------------- helpers
def _db(x, floor=-200.0):
    return 20 * math.log10(x) if x > 0 else floor


def _r(x, d):
    p = 10 ** d
    return math.floor(x * p + 0.5) / p


def envelope_db(x: np.ndarray) -> np.ndarray:
    nb = len(x) // EB
    e = np.sqrt((x[:nb * EB].reshape(nb, EB) ** 2).mean(axis=1))
    return 20 * np.log10(np.maximum(e, 1e-5))


def coarse_offset(x: np.ndarray) -> tuple[int, float]:
    """Best block offset of the stored envelope in the recording, in samples,
    and its correlation. Negative offsets (recording started a little late)
    are allowed down to the first sound in the signal."""
    env = envelope_db(x)
    T = ENV - ENV.mean()
    tn = math.sqrt(float((T ** 2).sum()))
    L = len(T)
    kmin = -(FIRST // EB)                  # recording may start inside the leading silence
    pad = -kmin
    e = np.concatenate([np.full(pad, -100.0), env, np.full(L, -100.0)])
    kmax = len(env) - L // 2               # at least half the template inside the recording
    best, bk = -2.0, None
    # sliding Pearson correlation
    cs = np.concatenate([[0.0], np.cumsum(e)])
    cs2 = np.concatenate([[0.0], np.cumsum(e * e)])
    for k in range(kmin, max(kmin + 1, kmax)):
        s = k + pad
        seg = e[s:s + L]
        if len(seg) < L:
            break
        sm = cs[s + L] - cs[s]
        ss = cs2[s + L] - cs2[s] - sm * sm / L
        if ss <= 1e-9:
            continue
        r = float(np.dot(seg, T)) / (math.sqrt(ss) * tn)
        if r > best + 1e-12:
            best, bk = r, k
    if bk is None:
        raise PrepError("the recording is too short to contain the training signal")
    return bk * EB, best


def click_onset(x: np.ndarray, centre: int, noise_peak: float):
    """First sample of a click's response; returns (index, peak, sign) or None."""
    lo, hi = max(0, centre - CLICK_WIN), min(len(x), centre + CLICK_WIN)
    if hi - lo < 10:
        return None
    w = np.abs(x[lo:hi])
    p = float(w.max())
    if p < 4 * noise_peak or p <= 0:
        return None
    thr = max(0.1 * p, 2 * noise_peak)
    i = int(np.argmax(w >= thr))
    j = int(np.argmax(w))
    return lo + i, p, 1 if x[lo + j] > 0 else -1


def take(x: np.ndarray, d: int, n: int) -> np.ndarray:
    out = np.zeros(n)
    s0, s1 = max(0, d), min(len(x), d + n)
    if s1 > s0:
        out[s0 - d:s1 - d] = x[s0:s1]
    return out


def hum_check(noise: np.ndarray):
    """Share of the noise energy at mains harmonics (1..8 x 50 or 60 Hz)."""
    n = len(noise)
    w = 0.5 - 0.5 * np.cos(2 * np.pi * (np.arange(n) + 0.5) / n)
    nfft = 1 << 17
    P = np.abs(np.fft.rfft(noise * w, nfft)) ** 2
    f = np.arange(len(P)) * FS / nfft
    tot = float(P[(f >= 20) & (f <= 2000)].sum())
    best = (None, 0.0)
    for f0 in (50.0, 60.0):
        m = np.zeros(len(P), dtype=bool)
        for k in range(1, 9):
            m |= np.abs(f - k * f0) <= 3.0
        share = float(P[m].sum()) / tot if tot > 0 else 0.0
        if share > best[1]:
            best = (int(f0), share)
    return best


# ---------------------------------------------------------------- main step
def prepare_channel(x: np.ndarray, fs: int, label: str) -> tuple[np.ndarray, dict, list[str]]:
    warn: list[str] = []
    info: dict = {"recorded_rate": int(fs)}
    x = np.asarray(x, dtype=np.float64)
    if fs != FS:
        x = resample_to(x, fs, FS)
        info["resampled_to_48k"] = True
    if len(x) < (LAST - FIRST) // 2:
        raise PrepError(f"{label}: the recording is only {len(x) / FS:.0f} s long; the training signal "
                        f"is {N / FS:.0f} s. Record the whole file.")
    d0, r = coarse_offset(x)
    info["match"] = _r(r, 3)
    if r < MIN_ENV_CORR:
        raise PrepError(f"{label}: couldn't find the training signal in this recording (match {r:.2f}). "
                        "Check that the TONE3000 sweep file is what played, and that this is the right track.")
    noise_peak = float(np.abs(take(x, d0 + NOISE[0], NOISE[1] - NOISE[0])).max())
    clicks = [click_onset(x, b + d0, noise_peak) for b in BLIPS]
    if clicks[0] is None and clicks[1] is None:
        raise PrepError(f"{label}: found the signal but not its two alignment clicks at 10.5 s and 11.5 s. "
                        "A noise gate or a very low level can hide them: turn gates off and record again.")
    ds = [c[0] - b for c, b in zip(clicks, BLIPS) if c is not None]
    d = ds[0]
    if len(ds) < 2:
        warn.append(f"{label}: only one of the two alignment clicks was found; alignment is less certain")
        info["click_agreement_samples"] = None
    else:
        info["click_agreement_samples"] = int(abs(ds[1] - ds[0]))
        if abs(ds[1] - ds[0]) > 1:
            warn.append(f"{label}: the two alignment clicks disagree by {abs(ds[1] - ds[0])} samples; "
                        "something in the chain smears clicks (a gate, a long room tail)")
        d = min(ds)
    sign = next(c[2] for c in clicks if c is not None)
    info["offset_samples"] = int(d)
    info["offset_ms"] = _r(d / FS * 1000, 3)
    info["polarity"] = "inverted" if sign < 0 else "normal"

    if d + LAST >= len(x):
        raise PrepError(f"{label}: the recording stops {(d + LAST - len(x) + 1) / FS:.1f} s before the "
                        "training signal ends. Record (or export) a little past the end.")
    if d + FIRST < 0:
        raise PrepError(f"{label}: the recording starts {-(d + FIRST) / FS:.2f} s after the training "
                        "signal began. Start recording before playback.")
    if d < 0 or d + N > len(x):
        info["padded_samples"] = int(max(0, -d) + max(0, d + N - len(x)))
    y = take(x, d, N)

    # -- drift and consistency: the opening 9 s block vs the closing one
    a = y[DRIFT_SEG[0]:DRIFT_SEG[1]]
    ext = take(x, d + N - VAL + DRIFT_SEG[0] - DRIFT_MAX, DRIFT_SEG[1] - DRIFT_SEG[0] + 2 * DRIFT_MAX)
    na = float(np.linalg.norm(a))
    best_k, best_c = 0, -2.0
    for k in range(-DRIFT_MAX, DRIFT_MAX + 1):
        b = ext[k + DRIFT_MAX:k + DRIFT_MAX + len(a)]
        nb = float(np.linalg.norm(b))
        c = float(np.dot(a, b)) / (na * nb) if na > 0 and nb > 0 else 0.0
        if c > best_c + 1e-12:
            best_c, best_k = c, k
    info["drift_samples"] = int(best_k)
    info["start_end_correlation"] = _r(best_c, 5)
    if best_c < 0.9:
        warn.append(f"{label}: the closing 9 s don't match the opening 9 s (correlation {best_c:.2f}). "
                    "The amp changed a lot during the take, or playback and recording ran at different "
                    "speeds. Use one interface for both, with the project at 48 kHz.")
    elif abs(best_k) > 1:
        warn.append(f"{label}: the end of the take has drifted {best_k} samples against the start. "
                    "Playback and recording don't share a clock: use one interface for both "
                    "(not separate input and output devices).")
    v0, v1 = y[:VAL], y[N - VAL:]
    den = float((v1 ** 2).sum())
    esr = float(((v0 - v1) ** 2).sum()) / den if den > 0 else float("nan")
    info["replicate_esr"] = float(f"{esr:.3g}")
    if esr > 0.005:
        warn.append(f"{label}: the amp sounded different at the end than at the start (replicate ESR "
                    f"{esr:.3g}). Warm the amp up for 20 minutes, keep levels steady, and record again. "
                    "A model can't be much more accurate than this.")

    # -- level, clipping
    pk = float(np.abs(y).max())
    info["peak_dbfs"] = _r(_db(pk), 1)
    clip = int(np.count_nonzero(np.abs(y) >= 0.999))
    flat = int(np.count_nonzero((np.abs(y[1:]) > 0.5) & (y[1:] == y[:-1])))
    info["clipped_samples"] = clip
    if clip > 0:
        warn.append(f"{label}: {clip} samples at full scale, so the recording clipped. Lower the "
                    "interface input gain about 6 dB and record again.")
    elif flat > 20:
        warn.append(f"{label}: the waveform has flat tops ({flat} repeated samples near the peak). "
                    "Something before the interface may be clipping (a pad, a line out, a preamp).")
    elif pk > 10 ** (-3 / 20):
        warn.append(f"{label}: peaks at {_db(pk):.1f} dBFS, close to clipping. TONE3000 suggests peaks "
                    "around -8 dBFS: lower the input gain a few dB.")
    elif pk < 10 ** (-24 / 20):
        warn.append(f"{label}: peaks at only {_db(pk):.1f} dBFS. Raise the input gain so peaks land "
                    "around -8 dBFS.")

    # -- noise, hum
    nz = y[NOISE[0]:NOISE[1]]
    nrms = float(np.sqrt((nz ** 2).mean()))
    info["noise_dbfs"] = _r(_db(nrms), 1)
    info["noise_below_peak_db"] = _r(_db(pk) - _db(nrms), 1) if nrms > 0 else None
    f0, share = hum_check(nz) if nrms > 0 else (None, 0.0)
    info["hum_hz"] = f0 if (share > 0.5 and nrms > 10 ** (-90 / 20)) else None
    info["hum_share"] = _r(share, 2)
    if nrms > 0 and _db(pk) - _db(nrms) < 40:
        warn.append(f"{label}: the noise floor is only {_db(pk) - _db(nrms):.0f} dB below the peaks. "
                    "Noise ends up in the model: check cables, gain staging and noisy gear.")
    if info["hum_hz"]:
        warn.append(f"{label}: the noise is mostly {f0} Hz hum. Try the ground lift on the reamp box "
                    "or load box, and keep audio cables away from power cables.")
    return y, info, warn


def prepare(channels: list[tuple[str, np.ndarray, int]], kind: str) -> dict:
    """channels: [(name, samples, rate)]. kind: 'amp' or 'full'."""
    if kind not in ("amp", "full"):
        raise PrepError("kind must be 'amp' or 'full'")
    outs, diag, warnings = {}, {}, []
    for name, x, fs in channels:
        y, info, w = prepare_channel(x, fs, name)
        outs[name] = y
        diag[name] = info
        warnings += w
    first = min(d["offset_samples"] for d in diag.values())
    for d in diag.values():
        d["delay_vs_first_ms"] = _r((d["offset_samples"] - first) / FS * 1000, 3)
    notes = []
    if kind == "amp":
        notes.append("Amp-only model: pair it with cab IRs captured with the speaker-terminal reference "
                     "(reference mode). Sweep-referenced IRs would add the speaker's impedance bump twice.")
    else:
        notes.append("Full-chain model: each mic is its own model. Close mics work best; NAM only models a "
                     "short stretch of time, so room sound won't carry over well.")
        if len(diag) > 1:
            notes.append("Each file is lined up on its own. To blend two of these models like the real "
                         "mics, delay each by its delay_vs_first_ms in the DAW.")
    return {"kind": kind, "outputs": outs, "diagnostics": diag, "warnings": warnings, "notes": notes}


# ---------------------------------------------------------------- output
def wav24(x: np.ndarray, rate: int = FS) -> bytes:
    """Mono 24-bit PCM. Scale 2^23 so a 24-bit recording passes through bit for bit."""
    q = np.clip(np.floor(x * 8388608.0 + 0.5), -8388608, 8388607).astype(np.int32)
    b = (q.astype("<i4").view(np.uint8).reshape(-1, 4)[:, :3]).tobytes()
    hdr = b"RIFF" + struct.pack("<I", 36 + len(b) + (len(b) & 1)) + b"WAVE"
    hdr += b"fmt " + struct.pack("<IHHIIHH", 16, 1, 1, rate, rate * 3, 3, 24)
    hdr += b"data" + struct.pack("<I", len(b))
    return hdr + b + (b"\0" if len(b) & 1 else b"")


def safe_name(s: str) -> str:
    import re
    return re.sub(r"^_+|_+$", "", re.sub(r"[^A-Za-z0-9._-]+", "_", s.strip())) or "capture"


def upload_notes(res: dict, capture: str) -> str:
    lines = [f"NAM capture: {capture}", ""]
    lines += ["How to train it at TONE3000", "",
              "1. Go to tone3000.com and log in.",
              "2. Choose Create Tone, then Capture.",
              "3. Upload the file(s) in this folder (one model per file).",
              "4. Settings: Model Standard, Best Fit on, 400 max epochs (TONE3000's suggestion).",
              "5. Name each model with the amp, the knob settings and, for mics, the mic and its position.",
              "6. Leave it private unless you mean to share it.",
              "7. When it's done, check the ESR: under 0.01 is great; 0.3 or more means something went wrong.",
              ""]
    for n in res["notes"]:
        lines.append("Note: " + n)
    lines.append("")
    for name, d in res["diagnostics"].items():
        lines.append(f"{safe_name(capture)}_{safe_name(name)}.wav: peak {d['peak_dbfs']:.1f} dBFS, noise "
                     f"{d['noise_dbfs']:.1f} dBFS, replicate ESR {d['replicate_esr']:.5f}")
    if res["warnings"]:
        lines += ["", "Warnings:"] + ["- " + w for w in res["warnings"]]
    return "\n".join(lines) + "\n"


def report(res: dict, capture: str, extra: dict | None = None) -> dict:
    r = {"capture": capture, "kind": res["kind"], "created": datetime.now().isoformat(timespec="seconds"),
         "namprep_version": VERSION, "signal": _LAYOUT["name"], "diagnostics": res["diagnostics"],
         "warnings": res["warnings"], "notes": res["notes"]}
    if extra:
        r.update(extra)
    return r


def write_outputs(res: dict, capture: str, outdir: Path) -> list[Path]:
    base = outdir / safe_name(capture)
    base.mkdir(parents=True, exist_ok=True)
    paths = []
    for name, y in res["outputs"].items():
        p = base / f"{safe_name(capture)}_{safe_name(name)}.wav"
        p.write_bytes(wav24(y))
        paths.append(p)
    (base / "report.json").write_text(json.dumps(report(res, capture), indent=2))
    (base / "UPLOAD-STEPS.txt").write_text(upload_notes(res, capture))
    return paths


def load(path: str):
    import soundfile as sf
    x, fs = sf.read(path, dtype="float64", always_2d=True)
    return x.T, fs


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("rec", nargs="+", help="recorded WAV(s); every channel becomes one output")
    p.add_argument("--name", required=True)
    p.add_argument("--kind", choices=["amp", "full"], default="amp")
    p.add_argument("--names", help="names for the channels, in order")
    p.add_argument("--outdir", default="nam_out")
    a = p.parse_args(argv)
    chans = []
    for f in a.rec:
        x, fs = load(f)
        for c in range(x.shape[0]):
            chans.append((x[c], fs))
    names = [s.strip() for s in a.names.split(",")] if a.names else \
        [Path(f).stem for f in a.rec] if len(chans) == len(a.rec) else [f"ch{i + 1}" for i in range(len(chans))]
    if len(names) != len(chans):
        sys.exit(f"{len(chans)} channels but {len(names)} names")
    try:
        res = prepare([(n, x, fs) for n, (x, fs) in zip(names, chans)], a.kind)
    except PrepError as e:
        sys.exit(f"error: {e}")
    files = write_outputs(res, a.name, Path(a.outdir))
    print(json.dumps(res["diagnostics"], indent=1))
    for w in res["warnings"]:
        print("! " + w)
    print("wrote", *files, sep="\n  ")


if __name__ == "__main__":
    main()
