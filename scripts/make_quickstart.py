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
c.setTitle("IR Capture — Quick start")
c.setFillColor(LAMP)
c.rect(0, H - 8, W, 8, fill=1, stroke=0)
c.setFillColor(INK)
c.setFont("Helvetica-Bold", 22)
c.drawString(M, H - 58, "IR Capture — Quick start")
c.setFont("Helvetica", 10)
c.setFillColor(GREY)
c.drawString(M, H - 74, f"Version {version}  ·  Help › Quick Start in the app has this page too." if version else "Help › Quick Start in the app has this page too.")
y = H - 104
c.setFont("Helvetica-Bold", 13)
c.setFillColor(INK)
c.drawString(M, y, "Install")
y = wrap(c, "Drag IR Capture to Applications and open it from there. The first time, it asks to allow recording from your interface: click Allow.", M, y - 16, W - 2 * M)
y -= 8
c.setFont("Helvetica-Bold", 13)
c.drawString(M, y, "Your first cab IR")
y = steps(c, [
    ("Connect", "Interface output → the amp's FX return (power amp in) or a clean power amp → the cab. Not the guitar input. Mics on the cab into the interface. Amp master low, studio monitors muted."),
    ("Set levels", "Click Check levels. The app listens to the room for 2 seconds, finds a clean sweep level, then loops short sweeps. Turn each preamp until it says OK."),
    ("Capture", "Name it (for example 412_V30_PosA) and click Capture. It takes about 45 seconds."),
    ("Results", "Load the file at the top of the capture folder (one per mic) into your IR loader, DAW plug-in or modeler. Helix, Iridium and every-rate versions are in More formats."),
], y - 20)
y = picture(c, "cabNoRef", y - 4, W - 2 * M)
y = picture(c, "cabRef", y, W - 2 * M)
c.setFont("Helvetica", 8.5)
c.setFillColor(GREY)
c.drawString(M, 36, "Swell Amplification · swellamps.com  ·  Help › Contact Support in the app sends us your details.")
c.showPage()

c.setFillColor(LAMP)
c.rect(0, H - 8, W, 8, fill=1, stroke=0)
c.setFillColor(INK)
c.setFont("Helvetica-Bold", 13)
y = H - 50
c.drawString(M, y, "A NAM amp model")
y = steps(c, [
    ("Training signal", "Download T3K-sweep-v3.wav from tone3000.com/capture, then click Find it in Downloads in the app's Amp (NAM) tab."),
    ("Connect", "Interface output → reamp box → the amp's guitar input. Amp only: amp → reactive load box, its line out → an interface input (cab sim off). Gates, reverb, delay and loop effects off."),
    ("Set levels and record", "Click Check levels and set each input to OK, then Record (3 minutes 12 seconds). Don't touch any knobs while it runs."),
    ("Train", "Upload the WAV files at tone3000.com/capture. It trains the model for free and gives you a .nam file for any NAM player."),
], y - 20)
y = picture(c, "namAmp", y - 4, W - 2 * M)
y = picture(c, "namFull", y, W - 2 * M)
c.setFont("Helvetica-Bold", 13)
c.setFillColor(INK)
c.drawString(M, y - 6, "If something's wrong")
y = wrap(c, "The app explains each problem in plain words with what to do. Help › Troubleshooting covers the common ones (no signal, CLIP, distortion, noise, hum, dropouts). Help › Contact Support opens an email with the details we need.", M, y - 22, W - 2 * M)
c.setFont("Helvetica", 8.5)
c.setFillColor(GREY)
c.drawString(M, 36, "Swell Amplification · swellamps.com")
c.save()
print("wrote", out)
