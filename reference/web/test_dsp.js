// Compare the JS port against the Python reference on the simulated rig.
// Usage: node test_dsp.js ../sim_out
const fs = require("fs"), path = require("path");
const IRC = require("./dsp.js");
const dir = process.argv[2] || "../sim_out";
const rd = (p) => { const b = fs.readFileSync(p); return b.buffer.slice(b.byteOffset, b.byteOffset + b.length); };
const wav = (p) => { const i = IRC.readWav(rd(p)); return { fs: i.fs, x: IRC.wavChannel(i, 0) }; };
let ok = true;
const check = (c, m) => { console.log((c ? "PASS " : "FAIL ") + m); ok = ok && !!c; };

const spec = IRC.makeSpec(JSON.parse(fs.readFileSync(path.join(dir, "sweeps.json"))));
const py = wav(path.join(dir, "sweeps.wav")).x, js = IRC.makeTestSignal(spec);
let md = 0; for (let i = 0; i < js.length; i++) md = Math.max(md, Math.abs(js[i] - py[i]));
check(js.length === py.length && md < 1e-6, `test signal identical to Python (${js.length} samples, max diff ${md.toExponential(1)})`);

const t0 = Date.now();
const rec = ["close", "room", "ref"].map((n) => wav(path.join(dir, `logic_${n}.wav`)).x);
const res = IRC.analyse(rec, spec, ["Close", "Room"], 2, {}, (m) => process.stdout.write("  . " + m + "\n"));
const files = IRC.exportFiles(res, "logic", { bits: ["24", "32f"] });
console.log(`analysis + export: ${((Date.now() - t0) / 1000).toFixed(1)} s, ${files.length} files`);
const pyRep = JSON.parse(fs.readFileSync(path.join(dir, "logic/report.json")));
for (const m of ["Close", "Room", "reference"]) {
  const a = res.diagnostics[m], b = pyRep.diagnostics[m];
  const keys = ["recording_peak_dbfs", "noise_floor_db", "sweep_level_spread_db"];
  const diffs = keys.map((k) => Math.abs(a[k] - b[k]));
  check(Math.max(...diffs) <= 0.2, `${m}: peak/noise/spread match Python (${keys.map((k) => a[k] + " vs " + b[k]).join(", ")})`);
  check(Math.abs(a.tail_above_noise_ms - b.tail_above_noise_ms) < 5, `${m}: tail ${a.tail_above_noise_ms} vs ${b.tail_above_noise_ms} ms`);
  const h = Object.keys(b.harmonics_db).map((k) => [a.harmonics_db[k], b.harmonics_db[k]]);
  check(h.every(([x, y]) => (x === null) === (y === null) && (x === null || Math.abs(x - y) < 0.3)), `${m}: harmonics ${JSON.stringify(a.harmonics_db)}`);
  if (m !== "reference") check(Math.abs(a.arrival_ms - b.arrival_ms) < 0.002 && Math.abs(a.delay_vs_first_mic_ms - b.delay_vs_first_mic_ms) < 0.002,
    `${m}: arrival ${a.arrival_ms} ms, delay ${a.delay_vs_first_mic_ms} ms (Python ${b.arrival_ms}, ${b.delay_vs_first_mic_ms})`);
}
const get = (p) => { const f = files.find((f) => f.path === p); const i = IRC.readWav(f.data.buffer.slice(0)); return IRC.wavChannel(i, 0); };
function compare(jsPath, pyPath, label) {
  const a = get(jsPath), b = wav(pyPath).x;
  let dot = 0, ea = 0, eb = 0, md = 0, pa = 0, pb = 0;
  for (let i = 0; i < a.length; i++) { dot += a[i] * b[i]; ea += a[i] * a[i]; eb += b[i] * b[i]; pa = Math.max(pa, Math.abs(a[i])); pb = Math.max(pb, Math.abs(b[i])); }
  for (let i = 0; i < a.length; i++) md = Math.max(md, Math.abs(a[i] / pa - b[i] / pb));
  const corr = dot / Math.sqrt(ea * eb), lvl = 10 * Math.log10(ea / eb);
  check(a.length === b.length && corr > 0.99999 && Math.abs(lvl) < 0.05,
    `${label}: ${a.length} samples, correlation ${corr.toFixed(7)}, level ${lvl.toFixed(3)} dB, peak-norm max diff ${md.toExponential(1)}`);
}
for (const m of ["Close", "Room"]) for (const r of ["96k", "48k", "44.1k"]) for (const L of ["full", "2048"])
  compare(`logic/set/${r}/logic_${m}_${r}_24_${L}.wav`, path.join(dir, `logic/set/${r}/logic_${m}_${r}_24_${L}.wav`), `${m} ${r} ${L} vs Python`);

// polarity: the room mic recorded inverted gets flipped, matching Python
{
  const recInv = ["close", "room_inv", "ref"].map((n) => wav(path.join(dir, `logic_${n}.wav`)).x);
  const r2 = IRC.analyse(recInv, spec, ["Close", "Room"], 2, {});
  const notes = IRC.normalizePolarity(r2, false);
  const pyPol = JSON.parse(fs.readFileSync(path.join(dir, "polarity/report.json"))).polarity;
  check(JSON.stringify(r2.polarity) === JSON.stringify(pyPol), `polarity decision matches Python: ${JSON.stringify(r2.polarity.mics)}`);
  check(notes.length === 1 && notes[0] === "Room was inverted relative to Close and has been flipped.", `polarity note: ${notes}`);
  const f2 = IRC.exportFiles(r2, "polarity", { rates: [48000], lengths: ["full"] });
  files.push(...f2);
  compare("polarity/set/48k/polarity_Room_48k_24_full.wav", path.join(dir, "polarity/set/48k/polarity_Room_48k_24_full.wav"), "flipped Room vs Python");
  files.splice(files.length - f2.length, f2.length);
}

const zip = IRC.makeZip(files.slice(0, 3));
zip.arrayBuffer().then((b) => {
  fs.writeFileSync("/tmp/claude_test.zip", Buffer.from(b));
  const out = require("child_process").execSync("cd /tmp && rm -rf zt && mkdir zt && cd zt && unzip -q ../claude_test.zip && find . -type f | sort").toString();
  check(out.trim().split("\n").length === 3, "zip extracts with unzip:\n" + out.trim());
  // save example data for the page
  const curves = IRC.responseCurves(res, res.gains.set.Close);
  fs.writeFileSync("example.json", JSON.stringify({ diagnostics: res.diagnostics, warnings: res.warnings, mode: res.mode,
    sweeps_used: res.sweeps_used, names: res.names, curves, files: files.length / 2 }));
  console.log(ok ? "\nALL PASS" : "\nSOME CHECKS FAILED");
  process.exit(ok ? 0 : 1);
});
