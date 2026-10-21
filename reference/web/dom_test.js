const { JSDOM, VirtualConsole } = require("jsdom");
const fs = require("fs");
const html = "<!doctype html><html><head></head><body>" + fs.readFileSync("ir-capture.html","utf8") + "</body></html>";
const vc = new VirtualConsole();
vc.on("jsdomError", e => console.log("JSDOM ERROR:", e.message, e.detail && e.detail.stack ? e.detail.stack.split("\n").slice(0,4).join("\n") : ""));
vc.on("error", e => console.log("console.error", e));
const dom = new JSDOM(html, { runScripts: "dangerously", virtualConsole: vc, pretendToBeVisual: true,
  beforeParse(w) { w.TextEncoder = TextEncoder; w.matchMedia = () => ({ matches: false }); w.claude = { use: async () => ({ save: async (r) => { console.log("SAVE", r.filename, r.data.size); return { status: "saved" }; } }) }; } });
const w = dom.window;
setTimeout(async () => {
  console.log("diag rows:", w.document.querySelectorAll("#diag-body tr").length, "| readout:", w.document.getElementById("sig-readout").textContent);
  w.document.getElementById("dl-signal").click();
  setTimeout(() => { console.log("status:", w.document.getElementById("sig-status").textContent, "| err:", w.document.getElementById("page-err").textContent); process.exit(0); }, 8000);
}, 500);
