#!/usr/bin/env python3
"""CI smoke test: the files the Mac app wrote during `--demo` must match the Python reference.
The demo makes Universal, Everything, Helix and Iridium files in the consumer layout.
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


def say(c, m):
    global ok
    print(("PASS " if c else "FAIL ") + m)
    ok &= bool(c)


for m in ["Close", "Room", "reference"]:
    a, b = rep["diagnostics"][m], py["diagnostics"][m]
    d = max(abs(a[k] - b[k]) for k in ["recording_peak_dbfs", "noise_floor_db", "sweep_level_spread_db"])
    say(d <= 0.2, f"{m} diagnostics within {d} dB")
say(rep["mode"] == "reference" and rep["warnings"] == [] and rep["recorded_with"] == "logic", "reference mode, no warnings, recorded_with logic")
say(rep.get("polarity", {}).get("mode") == "positive", f"polarity recorded: {rep.get('polarity')}")
top = sorted(p.name for p in app.iterdir())
say(top == ["More formats", "README.txt", "Raw take", "demo_Close.wav", "demo_Room.wav", "report.json"], f"top level: {top}")
say((app / "Raw take/take.json").exists() and (app / "Raw take/demo_recording.wav").exists(), "raw take saved")


def corr(a_path, b_path):
    a, ra = sf.read(a_path)
    b, rb = sf.read(b_path)
    if ra != rb or len(a) != len(b):
        return 0.0, 99.0
    return float(np.dot(a, b) / np.sqrt(np.dot(a, a) * np.dot(b, b))), float(10 * np.log10(np.dot(a, a) / np.dot(b, b)))


P = sim / "logic/set"
pairs = []
for m in ["Close", "Room"]:
    pairs += [(app / f"demo_{m}.wav", P / f"48k/logic_{m}_48k_24_full.wav"),
              (app / f"More formats/Line 6 Helix/demo_{m}_Helix.wav", P / f"48k/logic_{m}_48k_24_2048.wav"),
              (app / f"More formats/Strymon Iridium/demo_{m}_Iridium.wav", P / f"96k/logic_{m}_96k_24_full.wav")]
ev = sorted((app / "More formats/Everything").rglob("*.wav"))
say(len(ev) == 32, f"{len(ev)} Everything files")
pairs += [(f, P / f.parent.name / f.name.replace("demo_", "logic_")) for f in ev]
# extras (minimum phase, mixes): compare with Python's export_extras files from sim_test.py (sim_out/xr, same mics)
E = sim / "xr/extras"
pairs += [(app / "More formats/Minimum phase/demo_Close_MP.wav", E / "48k/xr_Close_48k_24_full_MP.wav"),
          (app / "More formats/Minimum phase/demo_Close_Helix_MP.wav", E / "48k/xr_Close_48k_24_2048_MP.wav"),
          (app / "More formats/Mixes/demo_Close+Room_80-20.wav", E / "48k/xr_Close+Room_80-20_48k_24_full.wav"),
          (app / "More formats/Mixes/demo_Close+Room_60-40_Iridium.wav", E / "96k/xr_Close+Room_60-40_96k_24_full.wav")]
say(not (app / "More formats/Minimum phase/demo_Room_MP.wav").exists(), "no minimum-phase file for the room mic")
worst_c, worst_l = 1.0, 0.0
for a, b in pairs:
    c, lv = corr(a, b)
    if c < 0.99999 or abs(lv) > 0.05:
        print("FAIL", a.relative_to(app), c, lv)
        ok = False
    worst_c, worst_l = min(worst_c, c), max(worst_l, abs(lv))
print(f"{len(pairs)} files compared: worst correlation {worst_c:.7f}, worst level {worst_l:.3f} dB")
print("app output matches Python:", "PASS" if ok else "FAIL")
if not ok:
    print("::error title=Smoke test::The app's IRs don't match the Python reference")
sys.exit(0 if ok else 1)
