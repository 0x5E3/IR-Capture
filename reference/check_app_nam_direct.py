#!/usr/bin/env python3
"""Checks the app's direct NAM capture (CI smoke test, simulated interface).

The app plays sim_nam_out/standin_signal.wav through a simulated interface:
input 1 ("Suhr") hears it 1234 samples late at gain 0.5, input 2 ("SM57")
1384 samples late at gain -0.3. After lining up, each output file must be
exactly that gain times the signal, and the report must give those offsets.

usage: check_app_nam_direct.py <app output folder> <sim_nam_out>
"""
import json
import sys
from pathlib import Path

import numpy as np
import soundfile as sf

out, sim = Path(sys.argv[1]), Path(sys.argv[2])
x, fs = sf.read(sim / "standin_signal.wav")
rep = json.loads((out / "report.json").read_text())
ok = True


def check(cond, msg):
    global ok
    print(("PASS " if cond else "FAIL ") + msg)
    ok &= bool(cond)


check(rep.get("recorded_with") == "simulated", f"report says recorded_with={rep.get('recorded_with')}")
for name, lat, g in [("Suhr", 1234, 0.5), ("SM57", 1384, -0.3)]:
    d = rep["diagnostics"][name]
    check(d["offset_samples"] == lat, f"{name}: offset {d['offset_samples']} samples (expected {lat})")
    check((d["polarity"] == "inverted") == (g < 0), f"{name}: polarity {d['polarity']}")
    y, yfs = sf.read(out / f"namdirect_{name}.wav")
    info = sf.info(out / f"namdirect_{name}.wav")
    check(yfs == 48000 and info.subtype == "PCM_24" and len(y) == len(x), f"{name}: mono 48 kHz {info.subtype}, {len(y)} samples")
    err = np.abs(y - g * x).max()
    check(err < 2e-7, f"{name}: output equals {g} x signal (max diff {err:.1e})")
    raw = out / "raw recording" / f"namdirect_{name}_raw.wav"
    check(raw.exists() and sf.info(raw).frames >= len(x) + lat, f"{name}: raw recording saved ({raw.name})")
d2 = rep["diagnostics"]["SM57"]
check(abs(d2["delay_vs_first_ms"] - 150 / 48) < 1e-3, f"SM57: delay vs first {d2['delay_vs_first_ms']} ms (expected {150/48:.3f})")
check(not rep["warnings"], f"no warnings {rep['warnings']}")
check((out / "UPLOAD-STEPS.txt").exists(), "UPLOAD-STEPS.txt written")
sys.exit(0 if ok else 1)
