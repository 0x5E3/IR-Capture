#!/usr/bin/env python3
"""
Golden test: the Swift port against the Python reference, on the simulated rig.

  python3 sim_test.py                     # writes sim_out/ (Python's own checks too)
  python3 compare_swift.py <ircapture-cli> sim_out

Runs the Swift CLI on the same "Logic export" WAVs that sim_test.py processed, then checks
the report fields and every IR file Python wrote against the Swift files, plus the
known-answer checks against the simulated truth.
"""
import json
import subprocess
import sys
from pathlib import Path

import numpy as np
import soundfile as sf

sys.path.insert(0, str(Path(__file__).parent))
import sim_test as sim  # noqa: E402  (builds the same rig and truth, seeded)
import ircapture as irc  # noqa: E402

cli, sim_out = sys.argv[1], Path(sys.argv[2])
swift_out = sim_out / "swift"
ok = True


def check(c, m):
    global ok
    print(("PASS " if c else "FAIL ") + m)
    ok &= bool(c)


# 1. test signal
r = subprocess.run([cli, "make-signal", "--out", str(sim_out / "swift_sweeps.wav")], capture_output=True, text=True)
check(r.returncode == 0, "make-signal ran " + r.stdout.strip() + r.stderr.strip())
xs, _ = sf.read(sim_out / "swift_sweeps.wav")
xp, _ = sf.read(sim_out / "sweeps.wav")
check(len(xs) == len(xp) and np.abs(xs - xp).max() < 1e-6,
      f"test signal identical to Python ({len(xs)} samples, max diff {np.abs(xs - xp).max():.1e})")
js = json.loads((sim_out / "swift_sweeps.json").read_text())
check(all(js[k] == v for k, v in json.loads((sim_out / "sweeps.json").read_text()).items() if k != "ircapture_version"),
      "sweep settings JSON matches Python's")

# 2. process the Logic-style files
r = subprocess.run([cli, "process", "--signal", str(sim_out / "sweeps.json"), "--rec",
                    str(sim_out / "logic_close.wav"), str(sim_out / "logic_room.wav"), str(sim_out / "logic_ref.wav"),
                    "--ref", "3", "--names", "Close,Room", "--name", "logic", "--outdir", str(swift_out),
                    "--bits", "24,32f"], capture_output=True, text=True)
print(r.stdout)
check(r.returncode == 0, "Swift process ran" + (": " + r.stderr if r.returncode else ""))

py = json.loads((sim_out / "logic/report.json").read_text())
sw = json.loads((swift_out / "logic/report.json").read_text())
check(sw["mode"] == "reference" and sw["sweeps_used"] == py["sweeps_used"], f"mode {sw['mode']}, {sw['sweeps_used']} sweeps used")
check(sw["warnings"] == [], f"no warnings ({sw['warnings']})")
for m in ["Close", "Room", "reference"]:
    a, b = sw["diagnostics"][m], py["diagnostics"][m]
    keys = ["recording_peak_dbfs", "noise_floor_db", "sweep_level_spread_db"]
    check(max(abs(a[k] - b[k]) for k in keys) <= 0.2, f"{m}: peak/noise/spread " + ", ".join(f"{a[k]} vs {b[k]}" for k in keys))
    check(abs(a["tail_above_noise_ms"] - b["tail_above_noise_ms"]) < 5, f"{m}: tail {a['tail_above_noise_ms']} vs {b['tail_above_noise_ms']} ms")
    hs = [(a["harmonics_db"][k], b["harmonics_db"][k]) for k in b["harmonics_db"]]
    check(all((x is None) == (y is None) and (x is None or abs(x - y) < 0.3) for x, y in hs), f"{m}: harmonics {a['harmonics_db']}")
    if m != "reference":
        check(abs(a["arrival_ms"] - b["arrival_ms"]) < 0.002 and abs(a["delay_vs_first_mic_ms"] - b["delay_vs_first_mic_ms"]) < 0.002,
              f"{m}: arrival {a['arrival_ms']} ms, delay {a['delay_vs_first_mic_ms']} ms (Python {b['arrival_ms']}, {b['delay_vs_first_mic_ms']})")

# 3. every IR file Python wrote
pyfiles = sorted((sim_out / "logic/set").rglob("*.wav"))
worst = (1.0, 0.0)
missing = 0
for p in pyfiles:
    q = swift_out / p.relative_to(sim_out)
    if not q.exists():
        missing += 1
        continue
    a, ra = sf.read(q)
    b, rb = sf.read(p)
    if ra != rb or len(a) != len(b):
        check(False, f"{q.name}: rate/length {ra}/{len(a)} vs {rb}/{len(b)}")
        continue
    corr = float(np.dot(a, b) / np.sqrt(np.dot(a, a) * np.dot(b, b)))
    lvl = float(10 * np.log10(np.dot(a, a) / np.dot(b, b)))
    worst = (min(worst[0], corr), max(worst[1], abs(lvl)))
check(missing == 0 and len(pyfiles) == 32, f"all {len(pyfiles)} Python IR files have a Swift twin ({missing} missing)")
check(worst[0] > 0.99999 and worst[1] < 0.05, f"every file: correlation >= {worst[0]:.7f}, level within {worst[1]:.3f} dB")
n32 = len(list((swift_out / "logic/set").rglob("*_32f_*.wav")))
check(n32 == 32, f"{n32} 32-bit float files also written")

# 4. known answers (independent of Python)
lc, _ = sf.read(swift_out / "logic/set/96k/logic_Close_96k_32f_full.wav")
e = sim.shape_error(lc, sim.H_CLOSE)
check(np.abs(e).max() < 0.5, f"Swift close IR matches simulated truth within {np.abs(e).max():.2f} dB (80 Hz-5 kHz)")
rs, _ = sf.read(swift_out / "logic/set/96k/logic_Room_96k_32f_full.wav")
true_gap = (irc.onset_index(sim.H_ROOM, 20) - irc.onset_index(sim.H_CLOSE, 20)) / 96
gap = (irc.onset_index(rs, 20) - irc.onset_index(lc, 20)) / 96
check(abs(gap - true_gap) < 0.02, f"set trim keeps the room delay: {gap:.3f} ms vs true {true_gap:.3f} ms")
a96, _ = sf.read(swift_out / "logic/set/96k/logic_Close_96k_32f_full.wav")
a44, _ = sf.read(swift_out / "logic/set/44.1k/logic_Close_44.1k_32f_full.wav")
f96 = np.fft.rfftfreq(1 << 17, 1 / 96000)
f44 = np.fft.rfftfreq(1 << 17, 1 / 44100)
band = np.geomspace(100, 15000, 60)
m96 = np.interp(band, f96, 20 * np.log10(np.abs(np.fft.rfft(a96, 1 << 17)) + 1e-12))
m44 = np.interp(band, f44, 20 * np.log10(np.abs(np.fft.rfft(a44, 1 << 17)) + 1e-12))
check(np.abs(m96 - m44).max() < 0.2, f"44.1k matches 96k within {np.abs(m96 - m44).max():.3f} dB (same tone and level)")
peaks = [np.abs(sf.read(f)[0]).max() for f in (swift_out / "logic/set").rglob("*.wav")]
check(abs(max(peaks) - 10 ** (-1 / 20)) < 2e-3, f"loudest file peaks at {20 * np.log10(max(peaks)):.2f} dBFS (target -1)")


# 5. export targets (the app's consumer layout): every file must equal Python's matrix file, level included
def same(a_path, b_path, label):
    a, ra = sf.read(a_path)
    b, rb = sf.read(b_path)
    if ra != rb or len(a) != len(b):
        check(False, f"{label}: rate/length {ra}/{len(a)} vs {rb}/{len(b)}")
        return
    corr = float(np.dot(a, b) / np.sqrt(np.dot(a, a) * np.dot(b, b)))
    lvl = float(10 * np.log10(np.dot(a, a) / np.dot(b, b)))
    check(corr > 0.99999 and abs(lvl) < 0.05, f"{label}: correlation {corr:.7f}, level {lvl:+.3f} dB")


r = subprocess.run([cli, "process", "--signal", str(sim_out / "sweeps.json"), "--rec",
                    str(sim_out / "logic_close.wav"), str(sim_out / "logic_room.wav"), str(sim_out / "logic_ref.wav"),
                    "--ref", "3", "--names", "Close,Room", "--name", "tgt", "--outdir", str(swift_out),
                    "--targets", "universal,everything,helix,iridium", "--raw-take"], capture_output=True, text=True)
check(r.returncode == 0, "Swift process with targets ran" + (": " + r.stderr if r.returncode else ""))
T = swift_out / "tgt"
P = sim_out / "logic/set"
for m in ["Close", "Room"]:
    same(T / f"tgt_{m}.wav", P / f"48k/logic_{m}_48k_24_full.wav", f"Universal {m} = Python 48k 500 ms")
    same(T / f"More formats/Line 6 Helix/tgt_{m}_Helix.wav", P / f"48k/logic_{m}_48k_24_2048.wav", f"Helix {m} = Python 48k 2048")
    same(T / f"More formats/Strymon Iridium/tgt_{m}_Iridium.wav", P / f"96k/logic_{m}_96k_24_full.wav", f"Iridium {m} = Python 96k 500 ms")
ev = sorted((T / "More formats/Everything").rglob("*.wav"))
check(len(ev) == 32, f"Everything: {len(ev)} files (expected 32)")
worst = 1.0
for f in ev:
    a, _ = sf.read(f)
    b, _ = sf.read(P / f.parent.name / f.name.replace("tgt_", "logic_"))
    worst = min(worst, float(np.dot(a, b) / np.sqrt(np.dot(a, a) * np.dot(b, b))) if len(a) == len(b) else 0.0)
check(worst > 0.99999, f"Everything files match Python's set files (worst correlation {worst:.7f})")
top = sorted(p.name for p in T.iterdir())
check(top == ["More formats", "README.txt", "Raw take", "report.json", "tgt_Close.wav", "tgt_Room.wav"], f"capture folder top level: {top}")
check("tgt_Close.wav" in (T / "README.txt").read_text(), "README.txt names the Universal files")

# 6. re-export from the raw take gives the same files, bit for bit
before = sf.read(T / "More formats/Line 6 Helix/tgt_Close_Helix.wav")[0]
r = subprocess.run([cli, "reexport", "--folder", str(T), "--targets", "universal,helix"], capture_output=True, text=True)
check(r.returncode == 0, "re-export from the raw take ran" + (": " + r.stderr if r.returncode else ""))
after = sf.read(T / "More formats/Line 6 Helix/tgt_Close_Helix.wav")[0]
check(np.array_equal(before, after), "re-exported Helix file is identical to the original")

# 7. polarity: the inverted room mic is flipped exactly as Python flips it
r = subprocess.run([cli, "process", "--signal", str(sim_out / "sweeps.json"), "--rec",
                    str(sim_out / "logic_close.wav"), str(sim_out / "logic_room_inv.wav"), str(sim_out / "logic_ref.wav"),
                    "--ref", "3", "--names", "Close,Room", "--name", "polarity", "--outdir", str(swift_out),
                    "--rates", "48000", "--lengths", "full"], capture_output=True, text=True)
print(r.stdout)
check(r.returncode == 0 and "Room was inverted relative to Close and has been flipped." in r.stdout, "Swift flips the inverted Room mic")
spol = json.loads((swift_out / "polarity/report.json").read_text())["polarity"]
ppol = json.loads((sim_out / "polarity/report.json").read_text())["polarity"]
check(spol == ppol, f"polarity in report.json matches Python: {spol}")
same(swift_out / "polarity/set/48k/polarity_Room_48k_24_full.wav", sim_out / "polarity/set/48k/polarity_Room_48k_24_full.wav", "flipped Room = Python")
r = subprocess.run([cli, "process", "--signal", str(sim_out / "sweeps.json"), "--rec",
                    str(sim_out / "logic_close.wav"), str(sim_out / "logic_room_inv.wav"), str(sim_out / "logic_ref.wav"),
                    "--ref", "3", "--names", "Close,Room", "--name", "keep", "--outdir", str(swift_out),
                    "--rates", "48000", "--lengths", "full", "--keep-polarity"], capture_output=True, text=True)
kp = json.loads((swift_out / "keep/report.json").read_text())["polarity"]
check(kp["mode"] == "keep" and kp["mics"]["Room"] == {"main_peak": "negative", "flipped": False}, "--keep-polarity keeps it inverted")

print("\nALL PASS" if ok else "\nSOME CHECKS FAILED")
sys.exit(0 if ok else 1)
