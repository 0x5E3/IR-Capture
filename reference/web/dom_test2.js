const { JSDOM, VirtualConsole } = require("jsdom");
const fs = require("fs");
const html = "<!doctype html><html><head></head><body>" + fs.readFileSync("ir-capture.html","utf8") + "</body></html>";
const vc = new VirtualConsole(); vc.on("jsdomError", e => console.log("JSDOM ERROR:", e.message));
let saved = null;
const dom = new JSDOM(html, { runScripts: "dangerously", virtualConsole: vc, pretendToBeVisual: true,
  beforeParse(w) { w.TextEncoder = TextEncoder; w.matchMedia = () => ({ matches: false }); w.HTMLElement.prototype.scrollIntoView = () => {};
    w.claude = { use: async () => ({ save: async (r) => { saved = r; return { status: "saved" }; } }) }; } });
const w = dom.window, d = w.document;
const mk = (p, name) => { const b = fs.readFileSync(p); const ab = b.buffer.slice(b.byteOffset, b.byteOffset + b.length); return { name, arrayBuffer: async () => ab }; };
setTimeout(async () => {
  const ev = new w.Event("drop"); ev.dataTransfer = { files: [mk("../sim_out/logic_close.wav","SM57.wav"), mk("../sim_out/logic_room.wav","Room.wav"), mk("../sim_out/logic_ref.wav","Ref.wav"), mk("../sim_out/sweeps.wav","ircapture_sweeps_96k.wav")] };
  d.getElementById("drop").dispatchEvent(ev);
  await new Promise(r => setTimeout(r, 1500));
  console.log("rows:", [...d.querySelectorAll("#chan-body tr")].map(t => t.querySelector("td").firstChild.textContent + "=" + t.querySelector("select").value).join(", "));
  console.log("go enabled:", !d.getElementById("go").disabled, "| err:", d.getElementById("file-err").hidden ? "-" : d.getElementById("file-err").textContent);
  d.getElementById("go").click();
  const t = Date.now();
  while (!d.getElementById("progress").hidden || Date.now() - t < 1000) { await new Promise(r => setTimeout(r, 500)); if (Date.now() - t > 200000) break; }
  console.log("done in", ((Date.now()-t)/1000).toFixed(0), "s | pill:", d.getElementById("status-pill").textContent, "| readout:", d.getElementById("ir-readout").textContent, "| run err:", d.getElementById("run-err").textContent, "| page err:", d.getElementById("page-err").textContent);
  d.getElementById("dl-irs").click(); await new Promise(r => setTimeout(r, 500));
  console.log("saved:", saved && saved.filename, saved && saved.data.size);
  process.exit(0);
}, 500);
