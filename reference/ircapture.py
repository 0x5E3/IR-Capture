#!/usr/bin/env python3
"""
ircapture - guitar cabinet impulse-response capture core (reference implementation)

Pipeline
  1. Test signal: N exponential (log) sine sweeps separated by silent gaps.
  2. Play through amp -> cab, record mic channels (+ optional speaker-terminal
     reference channel), all on the same interface clock.
  3. Deconvolve every channel with the sweep's inverse filter (Farina). Each
     sweep becomes a linear impulse; speaker harmonic distortion lands in
     separate impulses *before* it and is windowed away (and measured).
  4. Average the sweeps (first one(s) discarded as warm-up), measure noise
     floor from sweep-to-sweep residuals, tail length, H2..H5, consistency.
  5. Reference mode: divide each mic IR by the speaker-terminal IR, giving the
     voltage->SPL response of speaker+mic+room. Amp, interface and the
     amp/speaker impedance interaction drop out. Sweep mode: IR is relative to
     the digital sweep and includes the amp.
  6. Trim the mic set with ONE common offset (keeps time-of-flight between
     mics) or per mic; resample the single capture to every target rate;
     truncate to each length with fades; normalise; write WAVs + report.

Commands
  make-signal   write the sweep WAV + JSON sidecar (e.g. to play from Logic)
  process       turn recorded WAV(s) into IRs
  devices       list audio devices                  (needs `sounddevice`)
  level         repeat short test sweeps with meters (needs `sounddevice`)
  capture       play, record and process in one go  (needs `sounddevice`)
"""
from __future__ import annotations

import argparse
import json
import math
import sys
from dataclasses import asdict, dataclass
from datetime import datetime
from pathlib import Path

import numpy as np
import soundfile as sf
from scipy import signal

VERSION = "0.1"
H_MAX = 5                 # highest harmonic measured / guarded against
LIN_PRE_S = 0.020         # samples kept before the anchor impulse (s)
DIST_WIN_S = 0.050        # window for harmonic-vs-linear energy (s)


# =========================================================================
# Test signal
# =========================================================================
@dataclass
class SweepSpec:
    fs: int = 96000
    f1: float = 20.0
    f2: float = 22000.0
    duration: float = 6.0     # seconds per sweep
    n_sweeps: int = 5
    discard: int = 1          # leading sweeps dropped from the average
    gap: float = 2.0          # silence after each sweep (>= room tail + latency)
    lead: float = 1.0         # silence before the first sweep
    level_dbfs: float = -12.0  # sweep peak level at the interface output
    fade_in: float = 0.10
    fade_out: float = 0.005

    def __post_init__(self):
        self.f2 = min(self.f2, 0.45 * self.fs)
        if not 0 < self.f1 < self.f2:
            raise ValueError("need 0 < f1 < f2")
        if self.n_sweeps - self.discard < 1:
            raise ValueError("n_sweeps must exceed discard")

    @property
    def L(self) -> float:                    # sweep rate constant (s)
        return self.duration / math.log(self.f2 / self.f1)

    @property
    def n_sweep(self) -> int:
        return int(round(self.duration * self.fs))

    @property
    def n_gap(self) -> int:
        return int(round(self.gap * self.fs))

    @property
    def n_lead(self) -> int:
        return int(round(self.lead * self.fs))

    @property
    def period(self) -> int:
        return self.n_sweep + self.n_gap

    def harmonic_advance(self, n: float) -> float:
        """Seconds by which harmonic n's impulse precedes the linear one."""
        return self.L * math.log(n)

    def max_ir_seconds(self) -> float:
        """Longest linear window that can't collide with the next sweep's
        harmonics (up to the 10th)."""
        return self.gap + self.duration - self.harmonic_advance(10) - 0.05


def _half_hann(n: int, rising: bool) -> np.ndarray:
    w = 0.5 - 0.5 * np.cos(np.pi * (np.arange(n) + 0.5) / n)
    return w if rising else w[::-1]


def make_sweep(spec: SweepSpec) -> np.ndarray:
    """Unit-amplitude exponential sine sweep."""
    t = np.arange(spec.n_sweep) / spec.fs
    x = np.sin(2 * np.pi * spec.f1 * spec.L * (np.exp(t / spec.L) - 1.0))
    fi, fo = int(spec.fade_in * spec.fs), int(spec.fade_out * spec.fs)
    if fi:
        x[:fi] *= _half_hann(fi, True)
    if fo:
        x[-fo:] *= _half_hann(fo, False)
    return x


def inverse_filter(sweep: np.ndarray, spec: SweepSpec) -> np.ndarray:
    """Time-reversed sweep with +6 dB/oct envelope, scaled so that
    sweep * inverse has unity in-band gain. Linear impulse lands at index
    len(sweep) - 1 of the convolution."""
    t = np.arange(len(sweep)) / spec.fs
    inv = sweep[::-1] * np.exp(-t / spec.L)
    d = signal.fftconvolve(sweep, inv)
    D = np.abs(np.fft.rfft(d))
    f = np.fft.rfftfreq(len(d), 1 / spec.fs)
    band = (f >= max(200.0, 4 * spec.f1)) & (f <= min(8000.0, spec.f2 / 2))
    return inv / np.median(D[band])


def make_test_signal(spec: SweepSpec) -> np.ndarray:
    sw = make_sweep(spec) * 10 ** (spec.level_dbfs / 20)
    tail = int(0.5 * spec.fs)
    out = np.zeros(spec.n_lead + spec.n_sweeps * spec.period + tail)
    for k in range(spec.n_sweeps):
        s = spec.n_lead + k * spec.period
        out[s:s + spec.n_sweep] = sw
    return out


def save_spec(spec: SweepSpec, path: Path):
    d = asdict(spec)
    d["ircapture_version"] = VERSION
    path.write_text(json.dumps(d, indent=2))


def load_spec(path: Path) -> SweepSpec:
    d = json.loads(Path(path).read_text())
    d.pop("ircapture_version", None)
    return SweepSpec(**d)


# =========================================================================
# Analysis
# =========================================================================
def deconvolve(rec: np.ndarray, inv: np.ndarray) -> np.ndarray:
    """rec (C, N) -> deconvolved (C, N + M - 1)."""
    return signal.oaconvolve(rec, inv[None, :], axes=1)


def locate_impulses(h: np.ndarray, spec: SweepSpec, tol: int = 4):
    """Find the linear impulse of every sweep on the anchor channel.
    Works without knowing latency or where the recording started."""
    a = np.abs(h)
    P = spec.period
    g = int(np.argmax(a))
    gv = a[g]

    def peak_near(i):
        lo, hi = max(0, i - tol), min(len(a), i + tol + 1)
        if lo >= hi:
            return None
        j = lo + int(np.argmax(a[lo:hi]))
        return j if a[j] > 0.5 * gv else None

    first = g
    while (j := peak_near(first - P)) is not None:
        first = j
    found = [first]
    while (j := peak_near(found[-1] + P)) is not None:
        found.append(j)
    expected = [first + k * P for k in range(len(found))]
    jitter = max(abs(f - e) for f, e in zip(found, expected))
    return expected, jitter


def band_weight(f: np.ndarray, f1: float, f2: float, nyq: float) -> np.ndarray:
    """1 inside the trusted band, rising smoothly (log-f) to 1e6 outside.
    Used to scale the deconvolution regulariser."""
    w = np.ones_like(f)
    lo_a, lo_b = f1 / 2, f1 * 1.5
    hi_a, hi_b = f2 * 0.8, min(f2 * 1.25, nyq)
    lf = np.log2(np.maximum(f, 1e-3))

    def ramp(x0, x1):             # 0 at x0 -> 1 at x1 (in log2 f)
        return np.clip((lf - np.log2(x0)) / (np.log2(x1) - np.log2(x0)), 0, 1)

    big = 6.0                      # 10^6
    lo = 1 - ramp(lo_a, lo_b)      # 1 below lo_a, 0 above lo_b
    hi = ramp(hi_a, hi_b)          # 0 below hi_a, 1 above hi_b
    expo = big * np.maximum(0.5 - 0.5 * np.cos(np.pi * lo),
                            0.5 - 0.5 * np.cos(np.pi * hi))
    return w * 10 ** expo


def divide_by_reference(hm: np.ndarray, hr: np.ndarray, spec: SweepSpec,
                        npre: int, reg_db: float = 40.0) -> np.ndarray:
    """Regularised spectral division hm / hr. Output has t=0 (reference
    arrival) at index npre, same length as the inputs."""
    W = hm.shape[-1]
    nfft = 1 << int(math.ceil(math.log2(2 * W)))
    Hm, Hr = np.fft.rfft(hm, nfft), np.fft.rfft(hr, nfft)
    f = np.fft.rfftfreq(nfft, 1 / spec.fs)
    pr = np.abs(Hr) ** 2
    eps = pr.max() * 10 ** (-reg_db / 10) * band_weight(f, spec.f1, spec.f2, spec.fs / 2)
    r = np.fft.irfft(Hm * np.conj(Hr) / (pr + eps), nfft)
    return np.concatenate([r[-npre:], r[:W - npre]])


def onset_index(h: np.ndarray, thr_db: float) -> int:
    a = np.abs(h)
    return int(np.argmax(a > a.max() * 10 ** (-thr_db / 20)))


def _db(x, floor=1e-30):
    return 10 * math.log10(max(float(x), floor))


@dataclass
class ProcessOptions:
    ir_max: float = 1.0          # analysed linear window (s)
    reg_db: float = 40.0         # reference-division regularisation
    onset_db: float = 20.0       # onset = first sample within this of peak


def analyse(rec: np.ndarray, spec: SweepSpec, names: list[str],
            ref_index: int | None, opt: ProcessOptions) -> dict:
    """rec: (C, N) at spec.fs. ref_index: row of the speaker-terminal
    reference, or None for sweep-referenced IRs. Returns IRs (t=0 at index
    `t0`, capture rate) plus diagnostics."""
    fs = spec.fs
    C = rec.shape[0]
    mic_rows = [i for i in range(C) if i != ref_index]
    if len(names) != len(mic_rows):
        raise ValueError(f"{len(mic_rows)} mic channels but {len(names)} names")
    warnings: list[str] = []

    rec_peaks = [20 * math.log10(max(np.abs(rec[i]).max(), 1e-12)) for i in range(C)]
    for i, p in enumerate(rec_peaks):
        label = "reference" if i == ref_index else names[mic_rows.index(i)]
        if p > -0.3:
            warnings.append(f"{label}: recording peaks at {p:.1f} dBFS - likely clipped, redo with less gain")
        elif p < -30:
            warnings.append(f"{label}: recording peaks at only {p:.1f} dBFS - raise input gain")

    inv = inverse_filter(make_sweep(spec), spec)
    h = deconvolve(rec, inv)

    anchor = ref_index if ref_index is not None else int(np.argmax(np.abs(h).max(axis=1)))
    expected, jitter = locate_impulses(h[anchor], spec)
    if len(expected) != spec.n_sweeps:
        warnings.append(f"found {len(expected)} sweeps, expected {spec.n_sweeps}")
    if jitter > 1:
        warnings.append(f"sweep impulses drift by up to {jitter} samples - playback and "
                        "recording may not share a clock")

    pre = int(round((spec.harmonic_advance(H_MAX + 0.5) + 0.02) * fs))
    seglen = spec.period
    used = []
    for k, p in enumerate(expected):
        if k < spec.discard:
            continue
        if p - pre >= 0 and p - pre + seglen <= h.shape[1]:
            used.append(p)
    if not used:
        raise RuntimeError("no complete sweeps found in the recording")
    if len(used) < 2:
        warnings.append("only one usable sweep - noise floor can't be measured")
    segs = np.stack([h[:, p - pre:p - pre + seglen] for p in used])   # (K, C, S)
    avg = segs.mean(axis=0)

    ir_max = min(opt.ir_max, spec.max_ir_seconds(), (seglen - pre) / fs - 0.05)
    if ir_max < opt.ir_max:
        warnings.append(f"analysis window shortened to {ir_max:.2f} s by sweep timing - "
                        "use a longer gap for longer room tails")
    npre = int(LIN_PRE_S * fs)
    nlin = npre + int(ir_max * fs)
    a0 = pre - npre
    lin_k = segs[:, :, a0:a0 + nlin]       # per-sweep linear IRs
    lin = avg[:, a0:a0 + nlin]
    K = lin_k.shape[0]

    # ---- per-channel diagnostics on the raw (sweep-referenced) IRs
    diag = {}
    L = spec.L
    w = int(DIST_WIN_S * fs)
    g1 = int(0.001 * fs)
    for i in range(C):
        label = "reference" if i == ref_index else names[mic_rows.index(i)]
        x = lin[i]
        peak = np.abs(x).max()
        d = {"recording_peak_dbfs": round(rec_peaks[i], 1)}
        if K >= 2:
            resid = lin_k[:, i] - x
            noise_rms = math.sqrt(float((resid ** 2).sum(0).mean()) / (K - 1) / K)
            d["noise_floor_db"] = round(20 * math.log10(max(noise_rms, 1e-30) / peak), 1)
            env = np.sqrt(np.convolve(x ** 2, np.ones(int(0.01 * fs)) / int(0.01 * fs), "same"))
            above = np.nonzero(env > 2 * noise_rms)[0]
            q = int(np.argmax(np.abs(x)))
            d["tail_above_noise_ms"] = round((above[-1] - q) / fs * 1000, 1) if len(above) else 0.0
            lv = [20 * math.log10(np.sqrt(np.mean(lin_k[k, i] ** 2)) / np.sqrt(np.mean(x ** 2)))
                  for k in range(K)]
            cc = [float(np.dot(lin_k[k, i], x) / (np.linalg.norm(lin_k[k, i]) * np.linalg.norm(x)))
                  for k in range(K)]
            d["sweep_level_spread_db"] = round(max(lv) - min(lv), 2)
            d["sweep_min_correlation"] = round(min(cc), 5)
        else:
            noise_rms = 0.0
        # harmonics, measured on the averaged segment around this channel's own peak
        q = a0 + int(np.argmax(np.abs(x)))
        e_lin = float((avg[i, q - g1:q + w] ** 2).sum())
        e_noise = noise_rms ** 2 * (w + g1)
        hd = {}
        for n in range(2, H_MAX + 1):
            c = q - int(round(L * math.log(n) * fs))
            e = float((avg[i, c - g1:c + w] ** 2).sum())
            hd[f"H{n}"] = None if (K >= 2 and e < 2 * e_noise) else round(_db(e / e_lin), 1)
        d["harmonics_db"] = hd
        worst = max([v for v in hd.values() if v is not None], default=None)
        if worst is not None and worst > -30 and i != ref_index:
            warnings.append(f"{label}: harmonic distortion at {worst:.0f} dB re linear - speaker "
                            "is being driven hard; the IR is linear, consider ~6 dB less level")
        diag[label] = d

    # ---- the IRs themselves
    irs = {}
    for name, i in zip(names, mic_rows):
        if ref_index is not None:
            irs[name] = divide_by_reference(lin[i], lin[ref_index], spec, npre, opt.reg_db)
        else:
            irs[name] = lin[i].copy()
    onsets = {n: onset_index(v, opt.onset_db) for n, v in irs.items()}
    for n in names:
        diag[n]["arrival_ms"] = round((onsets[n] - npre) / fs * 1000, 3)
    first = min(onsets.values())
    for n in names:
        diag[n]["delay_vs_first_mic_ms"] = round((onsets[n] - first) / fs * 1000, 3)

    return {
        "irs": irs, "fs": fs, "t0": npre, "onsets": onsets,
        "mode": "reference" if ref_index is not None else "sweep",
        "sweeps_used": K, "timing_jitter_samples": int(jitter),
        "analysis_window_s": round(ir_max, 3),
        "diagnostics": diag, "warnings": warnings,
    }


# =========================================================================
# Export
# =========================================================================
@dataclass
class ExportOptions:
    rates: tuple = (44100, 48000, 88200, 96000)
    lengths: tuple = ("full", 1024, 2048, 4096)
    full_ms: float = 500.0
    bits: tuple = ("24",)          # "16", "24", "32f"
    trim: tuple = ("set",)         # "set" and/or "individual"
    preroll_ms: float = 0.25
    fade_frac: float = 0.10
    peak_dbfs: float = -1.0


def normalize_polarity(result: dict, keep: bool = False) -> list[str]:
    """Make each IR's main peak positive (commercial IR packs do this, so mics sum
    without cancelling). Records the decision in result["polarity"]; returns notes.
    With keep=True nothing is flipped but the detection is still recorded."""
    irs, names = result["irs"], list(result["irs"].keys())
    pol, notes = {}, []
    for m in names:
        h = irs[m]
        neg = bool(h[int(np.argmax(np.abs(h)))] < 0)
        flip = neg and not keep
        if flip:
            irs[m] = -h
        pol[m] = {"main_peak": "negative" if neg else "positive", "flipped": flip}
    result["polarity"] = {"mode": "keep" if keep else "positive", "mics": pol}
    flipped = [m for m in names if pol[m]["flipped"]]
    kept = [m for m in names if not pol[m]["flipped"]]
    for m in flipped:
        if kept:
            notes.append(f"{m} was inverted relative to {kept[0]} and has been flipped.")
        else:
            notes.append(f"{m} came out inverted (main peak negative) and has been flipped.")
    if keep:
        for m in names:
            if pol[m]["main_peak"] == "negative":
                notes.append(f"{m} is inverted (main peak negative). It was kept as recorded.")
    return notes


def resample_to(x: np.ndarray, fs: int, rate: int) -> np.ndarray:
    if rate == fs:
        return x.copy()
    g = math.gcd(int(fs), int(rate))
    return signal.resample_poly(x, rate // g, fs // g)


def cut(h: np.ndarray, start: int, n: int, n_in: int, fade_frac: float) -> np.ndarray:
    out = np.zeros(n)
    s0, s1 = max(start, 0), min(start + n, len(h))
    if s1 > s0:
        out[s0 - start:s1 - start] = h[s0:s1]
    if n_in > 0:
        out[:n_in] *= _half_hann(n_in, True)
    nf = max(int(fade_frac * n), 2)
    out[-nf:] *= _half_hann(nf, False)
    return out


def _write(path: Path, x: np.ndarray, rate: int, bits: str, rng):
    path.parent.mkdir(parents=True, exist_ok=True)
    if bits == "16":
        tpdf = rng.random(len(x)) - rng.random(len(x))          # +-1 LSB TPDF
        q = np.clip(np.round(x * 32767 + tpdf), -32768, 32767).astype(np.int16)
        sf.write(path, q, rate, subtype="PCM_16")
    elif bits == "24":
        sf.write(path, x, rate, subtype="PCM_24")
    elif bits == "32f":
        sf.write(path, x.astype(np.float32), rate, subtype="FLOAT")
    else:
        raise ValueError(f"unknown bit depth {bits}")


def export(result: dict, capture_name: str, outdir: Path, opt: ExportOptions) -> list[Path]:
    fs, irs, onsets = result["fs"], result["irs"], result["onsets"]
    pre_fs = opt.preroll_ms / 1000 * fs
    rng = np.random.default_rng(0)
    written = []
    for mode in opt.trim:
        variants = {}            # (mic, rate, length) -> array
        for rate in opt.rates:
            set_start = int(round((min(onsets.values()) - pre_fs) * rate / fs))
            n_in = int(round(opt.preroll_ms / 1000 * rate))
            for mic, h in irs.items():
                # x fs/rate keeps the convolution gain identical at every rate
                # (sample values alone would make a 96k IR ~6.8 dB louder than 44.1k)
                hr = resample_to(h, fs, rate) * (fs / rate)
                start = set_start if mode == "set" else int(round((onsets[mic] - pre_fs) * rate / fs))
                for ln in opt.lengths:
                    n = int(round(opt.full_ms / 1000 * rate)) if ln == "full" else int(ln)
                    variants[(mic, rate, ln)] = cut(hr, start, n, n_in, opt.fade_frac)
        target = 10 ** (opt.peak_dbfs / 20)
        # gains are shared across rates and lengths, so every variant of a mic
        # plays at the same level; only the loudest file reaches peak_dbfs
        if mode == "set":       # one gain for everything: keeps mic balance
            g = target / max(np.abs(v).max() for v in variants.values())
            gains = {m: g for m in irs}
        else:
            gains = {m: target / max(np.abs(v).max() for k, v in variants.items() if k[0] == m)
                     for m in irs}
        for (mic, rate, ln), v in variants.items():
            for b in opt.bits:
                tag = "full" if ln == "full" else f"{ln}"
                p = (outdir / capture_name / mode / f"{rate / 1000:g}k"
                     / f"{capture_name}_{mic}_{rate / 1000:g}k_{b}_{tag}.wav")
                _write(p, v * gains[mic], rate, b, rng)
                written.append(p)
    return written


def write_report(result: dict, spec: SweepSpec, capture_name: str, outdir: Path,
                 extra: dict | None = None) -> Path:
    rep = {k: v for k, v in result.items() if k not in ("irs", "onsets", "polarity_notes")}
    rep.update({"capture": capture_name, "created": datetime.now().isoformat(timespec="seconds"),
                "sweep": asdict(spec), "ircapture_version": VERSION})
    if extra:
        rep.update(extra)
    p = outdir / capture_name / "report.json"
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(rep, indent=2))
    return p


def summary_text(result: dict) -> str:
    lines = [f"mode: {result['mode']}-referenced, {result['sweeps_used']} sweeps averaged, "
             f"timing jitter {result['timing_jitter_samples']} samples"]
    for name, d in result["diagnostics"].items():
        hd = ", ".join(f"{k} {'<noise' if v is None else f'{v:.0f}'}" for k, v in d["harmonics_db"].items())
        parts = [f"peak {d['recording_peak_dbfs']:.1f} dBFS"]
        if "noise_floor_db" in d:
            parts += [f"noise {d['noise_floor_db']:.0f} dB", f"tail {d['tail_above_noise_ms']:.0f} ms",
                      f"sweep spread {d['sweep_level_spread_db']:.2f} dB"]
        if "arrival_ms" in d:
            parts.append(f"arrival {d['arrival_ms']:.2f} ms")
        lines.append(f"  {name:<12} " + " | ".join(parts) + f" | {hd}")
    for w in result["warnings"]:
        lines.append(f"  ! {w}")
    return "\n".join(lines)


# =========================================================================
# I/O helpers
# =========================================================================
def load_recordings(paths: list[str]) -> tuple[np.ndarray, int]:
    chans, fs, n = [], None, None
    for p in paths:
        x, r = sf.read(p, dtype="float64", always_2d=True)
        if fs is None:
            fs = r
        elif r != fs:
            raise ValueError(f"{p}: {r} Hz, others are {fs} Hz")
        chans.extend(x.T)
    n = min(len(c) for c in chans)
    if any(len(c) != n for c in chans):
        print(f"note: recordings differ in length, using the first {n} samples of each", file=sys.stderr)
    return np.stack([c[:n] for c in chans]), fs


def _parse_list(s, cast=str):
    return [cast(x.strip()) for x in s.split(",") if x.strip()] if s else []


def _len_cast(x):
    return "full" if x == "full" else int(x)


def _need_sd():
    try:
        import sounddevice as sd  # noqa: F401
    except (ImportError, OSError) as e:
        sys.exit(f"audio I/O needs the 'sounddevice' package ({e}). pip install sounddevice")
    return sd


def _device(s):
    if s is None:
        return None
    return int(s) if s.isdigit() else s


# =========================================================================
# Commands
# =========================================================================
def spec_from_args(a) -> SweepSpec:
    return SweepSpec(fs=a.fs, f1=a.f1, f2=a.f2, duration=a.sweep_s, n_sweeps=a.sweeps,
                     discard=a.discard, gap=a.gap, level_dbfs=a.level)


def export_from_args(a) -> ExportOptions:
    return ExportOptions(rates=tuple(_parse_list(a.rates, int)), lengths=tuple(_parse_list(a.lengths, _len_cast)),
                         full_ms=a.full_ms, bits=tuple(_parse_list(a.bits)), trim=tuple(_parse_list(a.trim)),
                         preroll_ms=a.preroll_ms, peak_dbfs=a.peak)


def run_processing(rec, spec, names, ref_index, capture_name, outdir, a, extra=None):
    res = analyse(rec, spec, names, ref_index,
                  ProcessOptions(ir_max=a.ir_max, reg_db=a.reg_db, onset_db=a.onset_db))
    res["polarity_notes"] = normalize_polarity(res, keep=getattr(a, "keep_polarity", False))
    print(summary_text(res))
    for n in res["polarity_notes"]:
        print("  * " + n)
    files = export(res, capture_name, outdir, export_from_args(a))
    rep = write_report(res, spec, capture_name, outdir, extra)
    print(f"wrote {len(files)} IR files and {rep}")
    return res, files


def cmd_make_signal(a):
    spec = spec_from_args(a)
    out = Path(a.out)
    sf.write(out, make_test_signal(spec).astype(np.float32), spec.fs, subtype="FLOAT")
    save_spec(spec, out.with_suffix(".json"))
    print(f"wrote {out} ({len(make_test_signal(spec)) / spec.fs:.1f} s) and {out.with_suffix('.json')}")


def cmd_process(a):
    spec = load_spec(Path(a.signal))
    rec, fs = load_recordings(a.rec)
    if fs != spec.fs:
        sys.exit(f"recording is {fs} Hz but the test signal was made at {spec.fs} Hz")
    ref = a.ref - 1 if a.ref else None
    n_mics = rec.shape[0] - (ref is not None)
    names = _parse_list(a.names) or [f"mic{i + 1}" for i in range(n_mics)]
    run_processing(rec, spec, names, ref, a.name, Path(a.outdir), a)


def cmd_devices(a):
    sd = _need_sd()
    print(sd.query_devices())


def _playrec(sd, x, fs, out_ch, in_chs, device):
    y = sd.playrec(x[:, None].astype(np.float32), samplerate=fs, input_mapping=in_chs,
                   output_mapping=[out_ch], device=device, dtype="float32")
    sd.wait()
    return np.asarray(y, dtype=np.float64).T


def cmd_level(a):
    sd = _need_sd()
    spec = SweepSpec(fs=a.fs, f1=a.f1, f2=a.f2, duration=1.5, n_sweeps=1, discard=0, gap=1.0,
                     lead=0.2, level_dbfs=a.level)
    mics = _parse_list(a.in_ch, int)
    chans = mics + ([a.ref_ch] if a.ref_ch else [])
    labels = (_parse_list(a.names) or [f"in{c}" for c in mics]) + (["reference"] if a.ref_ch else [])
    x = make_test_signal(spec)
    inv = inverse_filter(make_sweep(spec), spec)
    print(f"short sweeps at {a.level:.0f} dBFS out. Target sweep peak {a.target:.0f} dBFS. Ctrl-C to stop.")
    try:
        for _ in range(a.count or 10 ** 9):
            y = _playrec(sd, x, spec.fs, a.out_ch, chans, _device(a.device))
            parts = []
            for lab, row in zip(labels, y):
                pk = 20 * math.log10(max(np.abs(row).max(), 1e-9))
                adv = "CLIP" if pk > -0.3 else f"{a.target - pk:+.0f} dB"
                h = signal.oaconvolve(row, inv)
                q = int(np.argmax(np.abs(h)))
                w = int(DIST_WIN_S * spec.fs)
                e1 = (h[q - 50:q + w] ** 2).sum()
                c2 = q - int(round(spec.harmonic_advance(2) * spec.fs))
                c3 = q - int(round(spec.harmonic_advance(3) * spec.fs))
                h2 = _db((h[c2 - 50:c2 + w] ** 2).sum() / e1)
                h3 = _db((h[c3 - 50:c3 + w] ** 2).sum() / e1)
                parts.append(f"{lab}: {pk:6.1f} dBFS ({adv})  H2 {h2:4.0f} H3 {h3:4.0f}")
            print("   ".join(parts), flush=True)
    except KeyboardInterrupt:
        print()


def cmd_capture(a):
    sd = _need_sd()
    spec = spec_from_args(a)
    mics = _parse_list(a.in_ch, int)
    chans = mics + ([a.ref_ch] if a.ref_ch else [])
    names = _parse_list(a.names) or [f"in{c}" for c in mics]
    x = make_test_signal(spec)
    print(f"capturing {spec.n_sweeps} sweeps, {len(x) / spec.fs:.0f} s ...", flush=True)
    rec = _playrec(sd, x, spec.fs, a.out_ch, chans, _device(a.device))
    outdir = Path(a.outdir)
    raw = outdir / a.name / "raw"
    raw.mkdir(parents=True, exist_ok=True)
    sf.write(raw / f"{a.name}_recording.wav", rec.T.astype(np.float32), spec.fs, subtype="FLOAT")
    save_spec(spec, raw / f"{a.name}_signal.json")
    ref = len(mics) if a.ref_ch else None
    run_processing(rec, spec, names, ref, a.name, outdir, a,
                   extra={"channels": {"mics": dict(zip(names, mics)), "reference": a.ref_ch},
                          "notes": a.notes})


def build_parser():
    p = argparse.ArgumentParser(prog="ircapture", description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)

    def sweep_args(q, level=True):
        q.add_argument("--fs", type=int, default=96000, help="capture sample rate")
        q.add_argument("--f1", type=float, default=20.0)
        q.add_argument("--f2", type=float, default=22000.0)
        if level:
            q.add_argument("--level", type=float, default=-12.0, help="sweep peak at interface output, dBFS")

    def long_sweep_args(q):
        q.add_argument("--sweep-s", type=float, default=6.0)
        q.add_argument("--sweeps", type=int, default=5)
        q.add_argument("--discard", type=int, default=1)
        q.add_argument("--gap", type=float, default=2.0)

    def proc_args(q):
        q.add_argument("--name", required=True, help="capture name, e.g. 412_GreenbackA_pos1")
        q.add_argument("--outdir", default="ir_out")
        q.add_argument("--rates", default="44100,48000,88200,96000")
        q.add_argument("--lengths", default="full,1024,2048,4096")
        q.add_argument("--full-ms", type=float, default=500.0)
        q.add_argument("--bits", default="24", help="any of 16,24,32f")
        q.add_argument("--trim", default="set", help="set and/or individual")
        q.add_argument("--preroll-ms", type=float, default=0.25)
        q.add_argument("--peak", type=float, default=-1.0, help="normalisation peak, dBFS")
        q.add_argument("--ir-max", type=float, default=1.0, help="analysis window, s")
        q.add_argument("--reg-db", type=float, default=40.0)
        q.add_argument("--onset-db", type=float, default=20.0)
        q.add_argument("--keep-polarity", action="store_true",
                       help="don't flip IRs whose main peak is negative")

    def io_args(q):
        q.add_argument("--device", help="audio device index or name")
        q.add_argument("--out-ch", type=int, default=1, help="output channel feeding the amp (1-based)")
        q.add_argument("--in-ch", required=True, help="mic input channels, e.g. 1,2,3")
        q.add_argument("--ref-ch", type=int, help="input channel with the speaker-terminal tap")
        q.add_argument("--names", help="mic names, e.g. SM57,R121,Room")

    q = sub.add_parser("make-signal", help="write sweep WAV + JSON")
    sweep_args(q)
    long_sweep_args(q)
    q.add_argument("--out", default="sweeps.wav")
    q.set_defaults(fn=cmd_make_signal)

    q = sub.add_parser("process", help="process recorded WAVs")
    q.add_argument("--signal", required=True, help="JSON written by make-signal")
    q.add_argument("--rec", nargs="+", required=True, help="recorded WAV(s), channels taken in order")
    q.add_argument("--ref", type=int, help="1-based channel (across all files) of the terminal tap")
    q.add_argument("--names", help="names for the non-reference channels, in order")
    proc_args(q)
    q.set_defaults(fn=cmd_process)

    q = sub.add_parser("devices", help="list audio devices")
    q.set_defaults(fn=cmd_devices)

    q = sub.add_parser("level", help="repeat short sweeps and meter inputs")
    sweep_args(q)
    io_args(q)
    q.add_argument("--target", type=float, default=-6.0, help="target recorded sweep peak, dBFS")
    q.add_argument("--count", type=int, help="stop after this many sweeps")
    q.set_defaults(fn=cmd_level)

    q = sub.add_parser("capture", help="play, record and process")
    sweep_args(q)
    long_sweep_args(q)
    io_args(q)
    proc_args(q)
    q.add_argument("--notes", default="", help="free text stored in the report (mic positions etc.)")
    q.set_defaults(fn=cmd_capture)
    return p


def main(argv=None):
    a = build_parser().parse_args(argv)
    a.fn(a)


if __name__ == "__main__":
    main()
