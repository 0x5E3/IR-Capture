import json, re, pathlib
here = pathlib.Path(__file__).parent
dsp = (here / "dsp.js").read_text()
assert "</script" not in dsp
ex = json.loads((here / "example.json").read_text())
page = (here / "page.html").read_text()
page = page.replace("__DSP__", dsp).replace("__EXAMPLE__", json.dumps(ex, separators=(",", ":"))).replace("__VERSION__", "0.1")
(here / "ir-capture.html").write_text(page)
print(len(page), "bytes")
