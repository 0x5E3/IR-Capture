// Drive the page's worker code in Node with Logic-style 24-bit files.
const fs = require("fs"), vm = require("vm");
const html = fs.readFileSync("ir-capture.html", "utf8");
const grab = (id) => html.match(new RegExp(`<script id="${id}"[^>]*>([\\s\\S]*?)</script>`))[1];
const msgs = [];
const ctx = { self: {}, TextEncoder, Blob, console };
ctx.self.postMessage = (m) => { msgs.push(m); if (m.type === "progress") process.stdout.write("  . " + m.text + "\n"); };
vm.createContext(ctx);
vm.runInContext(grab("dsp") + "\nthis.IRC = IRC;\n" + grab("worker-src"), ctx);
const IRC = ctx.IRC;
const rd = (p) => { const b = fs.readFileSync(p); return b.buffer.slice(b.byteOffset, b.byteOffset + b.length); };
(async () => {
  await ctx.self.onmessage({ data: { cmd: "signal", spec: { fs: 96000, level_dbfs: -12, n_sweeps: 5, duration: 6, gap: 2, discard: 1 } } });
  const sig = msgs.pop(); console.log("signal:", sig.type, sig.name, (await sig.zip.arrayBuffer()).byteLength, "bytes");
  // Logic-style export: 24-bit mono files; room + ref packed as one stereo file to exercise multichannel reading
  const ch = ["close", "room", "ref"].map((n) => { const i = IRC.readWav(rd(`../sim_out/logic_${n}.wav`)); return IRC.wavChannel(i, 0); });
  const w24 = (chs) => { const n = chs[0].length, C = chs.length, buf = Buffer.alloc(44 + n * C * 3); buf.write("RIFF", 0); buf.writeUInt32LE(36 + n * C * 3, 4);
    buf.write("WAVEfmt ", 8); buf.writeUInt32LE(16, 16); buf.writeUInt16LE(1, 20); buf.writeUInt16LE(C, 22); buf.writeUInt32LE(96000, 24);
    buf.writeUInt32LE(96000 * 3 * C, 28); buf.writeUInt16LE(3 * C, 32); buf.writeUInt16LE(24, 34); buf.write("data", 36); buf.writeUInt32LE(n * C * 3, 40);
    let o = 44; for (let i = 0; i < n; i++) for (let c = 0; c < C; c++) { buf.writeIntLE(Math.max(-8388608, Math.min(8388607, Math.round(chs[c][i] * 8388608))), o, 3); o += 3; }
    return buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.length); };
  const files = [{ name: "SM57.wav", buf: w24([ch[0]]) }, { name: "Room+Ref.wav", buf: w24([ch[1], ch[2]]) }];
  const t = Date.now();
  await ctx.self.onmessage({ data: { cmd: "process", spec: { fs: 96000, level_dbfs: -12, n_sweeps: 5, duration: 6, gap: 2, discard: 1 }, capture: "Test",
    files, channels: [{ file: 0, fileName: "SM57.wav", ch: 0, role: "mic", name: "SM57" }, { file: 1, fileName: "Room+Ref.wav", ch: 0, role: "mic", name: "Room" },
      { file: 1, fileName: "Room+Ref.wav", ch: 1, role: "ref", name: "ref" }],
    export: { rates: [44100, 48000, 88200, 96000], lengths: ["full", 1024, 2048, 4096], bits: ["24"], trim: ["set"], full_ms: 500 } } });
  const done = msgs.pop();
  if (done.type !== "done") { console.log("FAIL", done); process.exit(1); }
  const zb = Buffer.from(await done.zip.arrayBuffer()); fs.writeFileSync("/tmp/claude_ir_test.zip", zb);
  console.log(`process: ${((Date.now() - t) / 1000).toFixed(1)} s, ${done.count} files, zip ${(zb.length / 1e6).toFixed(1)} MB`);
  console.log(JSON.stringify(done.result.diagnostics.SM57), "\nwarnings:", done.result.warnings);
  // wrong-rate error path
  await ctx.self.onmessage({ data: { cmd: "process", spec: { fs: 48000, n_sweeps: 5, duration: 6, gap: 2, discard: 1 }, capture: "X", files, channels: [{ file: 0, ch: 0, role: "mic", name: "a" }], export: {} } });
  console.log("rate mismatch ->", msgs.pop().text);
})();
