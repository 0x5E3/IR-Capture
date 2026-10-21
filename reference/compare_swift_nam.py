#!/usr/bin/env python3
"""
Golden test: the Swift NAM prep against the Python reference, on the simulated rig.

  python3 sim_nam_test.py                       # writes sim_nam_out/gold (Python's files)
  python3 compare_swift_nam.py <ircapture-cli> sim_nam_out/gold

Runs `ircapture-cli nam-prep` on the same recordings and checks that the report
fields, warnings, upload steps and every output sample match Python.
"""
import json
import subprocess
import sys
from pathlib import Path

import numpy as np

# python3 compare_swift_nam.py --app <app capture folder> sim_nam_out/gold   checks the app's own output instead
APP = sys.argv[1] == "--app"
if APP:
    app_folder, gold = Path(sys.argv[2]), Path(sys.argv[3])
else:
    cli, gold = sys.argv[1], Path(sys.argv[2])
out = gold / "swift"
ok = True


def check(c, m):
    global ok
    print(("PASS " if c else "FAIL ") + m)
    ok &= bool(c)


if APP:
    out = app_folder.parent / "_cmp"
    import shutil
    shutil.rmtree(out, ignore_errors=True)
    (out / "gold").mkdir(parents=True)
    for f in app_folder.iterdir():
        shutil.copy(f, out / "gold" / f.name.replace("namdemo_", "gold_"))
    txt = (out / "gold/UPLOAD-STEPS.txt").read_text().replace("namdemo", "gold")
    (out / "gold/UPLOAD-STEPS.txt").write_text(txt)
    r = subprocess.CompletedProcess([], 0, "checking the app's files in " + str(app_folder), "")
else:
  r = subprocess.run([cli, "nam-prep", "--rec", str(gold / "Suhr.wav"), str(gold / "SM57.wav"), str(gold / "Room96.wav"),
                    "--names", "Suhr,SM57,Room", "--kind", "full", "--name", "gold", "--outdir", str(out)],
                   capture_output=True, text=True)
print(r.stdout)
if APP:
    rep = json.loads((app_folder / "report.json").read_text())
    check(rep["kind"] == "full" and "IR Capture (Mac)" in rep.get("app", ""), "app report: kind full, written by the app")
check(r.returncode == 0, "Swift nam-prep ran" + (": " + r.stderr if r.returncode else ""))
py = json.loads((gold / "gold/report.json").read_text())
sw = json.loads((out / "gold/report.json").read_text())
for n in ["Suhr", "SM57", "Room"]:
    a, b = sw["diagnostics"][n], py["diagnostics"][n]
    diff = [k for k in b if not (a.get(k) == b[k] or (isinstance(b[k], float) and isinstance(a.get(k), (int, float))
                                                         and abs(a[k] - b[k]) <= abs(b[k]) * 1e-6))]
    check(not diff and set(a) == set(b), f"{n}: report fields match Python" + (f" — differ: {[(k, a.get(k), b[k]) for k in diff]}" if diff else ""))
    qa = np.frombuffer((out / f"gold/gold_{n}.wav").read_bytes(), dtype=np.uint8)
    qb = np.frombuffer((gold / f"gold/gold_{n}.wav").read_bytes(), dtype=np.uint8)
    same_hdr = len(qa) == len(qb) and np.array_equal(qa[:44], qb[:44])

    def s24(u):
        t = u[44:44 + (len(u) - 44) // 3 * 3].reshape(-1, 3).astype(np.int32)
        v = t[:, 0] | (t[:, 1] << 8) | (t[:, 2] << 16)
        return np.where(v >= 1 << 23, v - (1 << 24), v)
    if same_hdr:
        d = np.abs(s24(qa) - s24(qb))
        nd, mx = int(np.count_nonzero(d)), int(d.max())
    else:
        nd, mx = -1, -1
    check(same_hdr and mx <= 1 and (nd == 0 if n != "Room" else nd < 100),
          f"{n}: WAV {len(qa)} bytes, {nd} samples differ from Python (max {mx} LSB)")
check(sw["warnings"] == py["warnings"], f"warnings match Python: {sw['warnings']}")
check((out / "gold/UPLOAD-STEPS.txt").read_text() == (gold / "gold/UPLOAD-STEPS.txt").read_text(), "upload steps text matches Python")
print("\nALL PASS" if ok else "\nSOME CHECKS FAILED")
if APP and not ok:
    print("::error title=Smoke test::The app's NAM files don't match the Python reference")
sys.exit(0 if ok else 1)
