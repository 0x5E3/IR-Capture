import json, re, pathlib
here = pathlib.Path(__file__).parent
dsp = (here / "dsp.js").read_text()
assert "</script" not in dsp
ex = json.loads((here / "example.json").read_text())
page = (here / "page.html").read_text()
nam = (here / "nam.js").read_text().replace("__NAM_LAYOUT__", (here.parent / "nam_v3_layout.json").read_text())
assert "</script" not in nam
page = page.replace("__NAM__", nam).replace("__DSP__", dsp).replace("__EXAMPLE__", json.dumps(ex, separators=(",", ":"))).replace("__VERSION__", "0.1")
(here / "ir-capture.html").write_text(page)
print(len(page), "bytes")
