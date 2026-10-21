#!/usr/bin/env python3
"""CI smoke test: the files the Mac app wrote during `--demo` must match the Python reference.
Usage: check_app_demo.py <app output folder for the capture> <sim_out>"""
import json
import sys
from pathlib import Path

import numpy as np
import soundfile as sf

app, sim = Path(sys.argv[1]), Path(sys.argv[2])
rep = json.loads((app / "report.json").read_text())
py = json.loads((sim / "logic/report.json").read_text())
ok = True
for m in ["Close", "Room", "reference"]:
    a, b = rep["diagnostics"][m], py["diagnostics"][m]
    d = max(abs(a[k] - b[k]) for k in ["recording_peak_dbfs", "noise_floor_db", "sweep_level_spread_db"])
    print(("PASS" if d <= 0.2 else "FAIL"), m, "diagnostics within", d, "dB")
    ok &= d <= 0.2
ok &= rep["mode"] == "reference" and rep["warnings"] == [] and rep["recorded_with"] == "logic"
files = sorted((app / "set").rglob("*.wav"))
print(len(files), "IR files")
ok &= len(files) == 32
for f in files:
    q = sim / "logic/set" / f.relative_to(app / "set").parent / f.name.replace("demo_", "logic_")
    a, _ = sf.read(f)
    b, _ = sf.read(q)
    c = float(np.dot(a, b) / np.sqrt(np.dot(a, a) * np.dot(b, b)))
    if c < 0.99999 or len(a) != len(b):
        print("FAIL", f.name, c)
        ok = False
print("app output matches Python:", "PASS" if ok else "FAIL")
if not ok:
    print("::error title=Smoke test::The app's IRs don't match the Python reference")
sys.exit(0 if ok else 1)
