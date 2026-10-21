// Compare the page's NAM prep (nam.js) with the Python reference on the simulated rig.
// Usage: node test_nam.js ../sim_nam_out/gold
const fs = require("fs"), path = require("path");
global.IRC = require("./dsp.js");
const src = fs.readFileSync(path.join(__dirname, "nam.js"), "utf8")
  .replace("__NAM_LAYOUT__", fs.readFileSync(path.join(__dirname, "..", "nam_v3_layout.json"), "utf8"));
const NAMPREP = new Function("IRC", src + "\nreturn NAMPREP;")(global.IRC);
const dir = process.argv[2] || "../sim_nam_out/gold";
const rd = (p) => { const b = fs.readFileSync(p); return b.buffer.slice(b.byteOffset, b.byteOffset + b.length); };
let ok = true;
const check = (c, m) => { console.log((c ? "PASS " : "FAIL ") + m); ok = ok && !!c; };

const inputs = [["Suhr.wav", "Suhr"], ["SM57.wav", "SM57"], ["Room96.wav", "Room"]].map(([f, n]) => {
  const i = IRC.readWav(rd(path.join(dir, f))); return { name: n, x: IRC.wavChannel(i, 0), fs: i.fs };
});
const t0 = Date.now();
const res = NAMPREP.prepare(inputs, "full", (m) => process.stdout.write("  . " + m + "\n"));
console.log(`prepare: ${((Date.now() - t0) / 1000).toFixed(1)} s`);
const py = JSON.parse(fs.readFileSync(path.join(dir, "gold/report.json")));
for (const n of ["Suhr", "SM57", "Room"]) {
  const a = res.diagnostics[n], b = py.diagnostics[n];
  const keys = Object.keys(b);
  const diff = keys.filter((k) => JSON.stringify(a[k]) !== JSON.stringify(b[k]) &&
    !(typeof a[k] === "number" && typeof b[k] === "number" && Math.abs(a[k] - b[k]) <= Math.abs(b[k]) * 1e-6));
  check(diff.length === 0 && Object.keys(a).length === keys.length, `${n}: report fields match Python` + (diff.length ? " — differ: " + diff.map((k) => `${k} ${a[k]} vs ${b[k]}`).join(", ") : ""));
  const out = NAMPREP.wav24(res.outputs[n]);
  const pyb = new Uint8Array(rd(path.join(dir, "gold", NAMPREP.fileName("gold", n))));
  let same = out.length === pyb.length, ndiff = 0, maxq = 0;
  if (same) for (let i = 44; i < out.length; i += 3) {
    const qa = out[i] | (out[i + 1] << 8) | ((out[i + 2] << 24) >> 8), qb = pyb[i] | (pyb[i + 1] << 8) | ((pyb[i + 2] << 24) >> 8);
    if (qa !== qb) { ndiff++; maxq = Math.max(maxq, Math.abs(qa - qb)); }
  }
  check(same && maxq <= 1 && (n !== "Room" ? ndiff === 0 : ndiff < 100),
    `${n}: WAV ${out.length} bytes, ${ndiff} samples differ from Python (max ${maxq} LSB)` + (n === "Room" ? " — resampled from 96 kHz" : " — bit-identical expected"));
  for (let i = 0; i < 44; i++) if (out[i] !== pyb[i]) { check(false, `${n}: header byte ${i} differs`); break; }
}
check(JSON.stringify(res.warnings) === JSON.stringify(py.warnings), "warnings match Python: " + JSON.stringify(res.warnings));
check(NAMPREP.uploadNotes(res, "gold") === fs.readFileSync(path.join(dir, "gold/UPLOAD-STEPS.txt"), "utf8"), "upload steps text matches Python");
console.log(ok ? "\nALL PASS" : "\nSOME CHECKS FAILED");
process.exit(ok ? 0 : 1);
