#!/usr/bin/env python3
"""Quick start.pdf for the DMG: the four steps and the wiring pictures the app renders itself
(`IR Capture --render-diagrams <dir>`), so the PDF and the app always show the same diagrams.

  python3 scripts/make_quickstart.py <diagrams dir> "dist/Quick start.pdf" <version>
"""
import sys
from pathlib import Path

from reportlab.lib.colors import HexColor
from reportlab.lib.pagesizes import letter
from reportlab.lib.utils import ImageReader
from reportlab.pdfgen import canvas

LAMP, INK, GREY = HexColor("#E8962E"), HexColor("#28241F"), HexColor("#6E6860")
diagrams, out, version = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3] if len(sys.argv) > 3 else ""
W, H = letter
M = 54


def wrap(c, text, x, y, width, size=10.5, leading=14, color=INK, font="Helvetica"):
    c.setFont(font, size)
    c.setFillColor(color)
    words, line = text.split(), ""
    for w in words:
        t = (line + " " + w).strip()
        if c.stringWidth(t, font, size) > width:
            c.drawString(x, y, line)
            y -= leading
            line = w
        else:
            line = t
    if line:
        c.drawString(x, y, line)
        y -= leading
    return y


def steps(c, items, y):
    for i, (head, body) in enumerate(items, 1):
        c.setFillColor(LAMP)
        c.circle(M + 9, y + 3.5, 9, fill=1, stroke=0)
        c.setFillColor(HexColor("#000000"))
        c.setFont("Helvetica-Bold", 10)
        c.drawCentredString(M + 9, y, str(i))
        c.setFillColor(INK)
        c.setFont("Helvetica-Bold", 11)
        c.drawString(M + 26, y, head)
        y = wrap(c, body, M + 26, y - 14, W - 2 * M - 26)
        y -= 6
    return y


def picture(c, name, y, max_w):
    p = diagrams / f"wiring-{name}.png"
    if not p.exists():
        return y
    img = ImageReader(str(p))
    iw, ih = img.getSize()
    w = min(max_w * 0.9, iw / 3)
    h = w * ih / iw
    c.drawImage(img, M, y - h, w, h, mask="auto")
    return y - h - 10


c = canvas.Canvas(str(out), pagesize=letter)
c.setTitle("IR Capture: Quick start")
c.setFillColor(LAMP)
c.rect(0, H - 8, W, 8, fill=1, stroke=0)
c.setFillColor(INK)
c.setFont("Helvetica-Bold", 22)
c.drawString(M, H - 58, "IR Capture: Quick start")
c.setFont("Helvetica", 10)
c.setFillColor(GREY)
c.drawString(M, H - 74, f"Version {version}  ·  This page is also in the app under Help › Quick Start." if version else "This page is also in the app under Help › Quick Start.")
y = H - 104
c.setFont("Helvetica-Bold", 13)
c.setFillColor(INK)
c.drawString(M, y, "Install")
y = wrap(c, "Drag IR Capture to Applications and open it from there. On first launch, macOS requests permission to record from the interface. Click Allow.", M, y - 16, W - 2 * M)
y -= 8
c.setFont("Helvetica-Bold", 13)
c.drawString(M, y, "Your first cab IR")
y = steps(c, [
    ("Connect", "Interface output → amp FX return (power amp in) or clean power amp → cab. Do not use the guitar input. Connect the mics on the cab to the interface. Set the amp master low. Mute the studio monitors."),
    ("Set levels", "Click Check levels. Room noise is measured for 2 seconds, a clean sweep level is set, and short sweeps are looped. Adjust each preamp until the meter shows OK."),
    ("Capture", "Enter a name (for example 412_V30_PosA) and click Capture. Duration: about 45 seconds."),
    ("Results", "Load the file at the top of the capture folder (one per mic) into an IR loader, DAW plug-in or modeler. Helix, Iridium and all-sample-rate versions are in More formats."),
], y - 20)
y = picture(c, "cabNoRef", y - 4, W - 2 * M)
y = picture(c, "cabRef", y, W - 2 * M)
c.setFont("Helvetica", 8.5)
c.setFillColor(GREY)
c.drawString(M, 36, "Swell Amplification · swellamps.com  ·  To send system details to support, use Help › Contact Support in the app.")
c.showPage()

c.setFillColor(LAMP)
c.rect(0, H - 8, W, 8, fill=1, stroke=0)
c.setFillColor(INK)
c.setFont("Helvetica-Bold", 13)
y = H - 50
c.drawString(M, y, "A NAM amp model")
y = steps(c, [
    ("Training signal", "Download T3K-sweep-v3.wav from tone3000.com/capture, then click Find it in Downloads in the app's Amp (NAM) tab."),
    ("Connect", "Interface output → reamp box → amp guitar input. Amp only: amp → reactive load box. Load box line out → interface input (cab sim off). Turn off gates, reverb, delay and loop effects."),
    ("Set levels and record", "Click Check levels and set each input to OK. Then click Record (3 minutes 12 seconds). Do not adjust any controls during the recording."),
    ("Train", "Upload the WAV files at tone3000.com/capture. TONE3000 trains the model free of charge and provides a .nam file for use in a NAM player."),
], y - 20)
y = picture(c, "namAmp", y - 4, W - 2 * M)
y = picture(c, "namFull", y, W - 2 * M)
c.setFont("Helvetica-Bold", 13)
c.setFillColor(INK)
c.drawString(M, y - 6, "Troubleshooting")
y = wrap(c, "Each error message states the problem and the corrective step. Common problems (no signal, CLIP, distortion, noise, hum, dropouts) are listed in Help › Troubleshooting. Help › Contact Support opens an email with the required system details.", M, y - 22, W - 2 * M)
c.setFont("Helvetica", 8.5)
c.setFillColor(GREY)
c.drawString(M, 36, "Swell Amplification · swellamps.com")
c.save()
print("wrote", out)
