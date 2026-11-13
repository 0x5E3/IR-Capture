"""A sample of the PRINT menu's plain black-and-white page: US Letter landscape at 150 dpi, every mic on one chart,
told apart by line style (no colour), named at the line's end and in the key."""
import sys, math
sys.argv = ['ircapture_rack.py', '/tmp/bw', 'none', '10', '4']
sys.path.insert(0, '/home/claude/ir-capture/design/render')
import numpy as np
from PIL import Image, ImageDraw, ImageFont
import ircapture_rack as R

FD = '/home/claude/ir-capture/Resources/SwellKit/fonts/'
W, H = 1650, 1275
im = Image.new('RGB', (W, H), 'white'); d = ImageDraw.Draw(im)
fB = ImageFont.truetype(FD + 'BarlowSemiCondensed-700-normal.ttf', 34)
fM = ImageFont.truetype(FD + 'BarlowSemiCondensed-600-normal.ttf', 22)
fS = ImageFont.truetype(FD + 'BarlowSemiCondensed-600-normal.ttf', 19)
gx0, gx1, gy0, gy1 = 130, 1450, 190, 1080
X = lambda f: gx0 + math.log10(f / 20) / 3 * (gx1 - gx0)
Y = lambda db: gy0 + (0 - db) / 60 * (gy1 - gy0)

d.text((gx0, 60), 'CAB IR  FREQUENCY RESPONSE', font=fB, fill='black')
d.text((gx0, 108), 'Capture: Mesa 4x12 V30     2026-11-12     1/6 octave smoothing', font=fM, fill='black')
d.text((gx1, 108), 'IR Capture', font=fM, fill=(90, 90, 90), anchor='ra')
for dec in (20, 200, 2000):
    for k in range(1, 10):
        f = dec * k
        if f > 20000: break
        x = X(f); major = k == 1 or f in (50, 500, 5000)
        d.line([(x, gy0), (x, gy1)], fill=(150, 150, 150) if major else (215, 215, 215), width=2 if major else 1)
d.line([(X(20000), gy0), (X(20000), gy1)], fill=(150, 150, 150), width=2)
for db in range(0, -61, -2):
    y = Y(db); major = db % 10 == 0
    d.line([(gx0, y), (gx1, y)], fill=(150, 150, 150) if major else (225, 225, 225), width=2 if major else 1)
    if major: d.text((gx0 - 14, y), str(db), font=fS, fill='black', anchor='rm')
for f, t in ((20, '20'), (50, '50'), (100, '100'), (200, '200'), (500, '500'), (1000, '1k'), (2000, '2k'),
             (5000, '5k'), (10000, '10k'), (20000, '20k')):
    d.text((X(f), gy1 + 14), t, font=fS, fill='black', anchor='ma')
d.text(((gx0 + gx1) / 2, gy1 + 46), 'Hz', font=fS, fill='black', anchor='ma')
d.text((gx0 - 14, gy0 - 26), 'dB', font=fS, fill='black', anchor='rm')
d.rectangle([gx0, gy0, gx1, gy1], outline='black', width=2)

curves = R.demo_curves()
top = max(c[1].max() for c in curves)
names = ['SM57 cap edge', 'R121 centre', 'Room']
styles = [None, (22, 10), (5, 8)]          # solid, dashed, dotted


def styled(pts, pat, width):
    if pat is None:
        d.line(pts, fill='black', width=width, joint='curve'); return
    on, off = pat; acc = 0.0; draw = True
    for (xa, ya), (xb, yb) in zip(pts, pts[1:]):
        L = math.hypot(xb - xa, yb - ya); t = 0.0
        while t < L:
            seg = min((on if draw else off) - acc, L - t)
            if draw:
                d.line([(xa + (xb - xa) * t / L, ya + (yb - ya) * t / L),
                        (xa + (xb - xa) * (t + seg) / L, ya + (yb - ya) * (t + seg) / L)], fill='black', width=width)
            t += seg; acc += seg
            if acc >= (on if draw else off) - 1e-6: acc = 0.0; draw = not draw


for (f, y), nm, st in zip(curves, names, styles):
    y = y - top - 2
    pts = [(X(fi), Y(max(-60, yi))) for fi, yi in zip(f, y) if yi > -60]
    styled(pts, st, 4)
# the key
kx, ky = gx1 - 330, gy0 + 30
d.rectangle([kx - 20, ky - 20, gx1 - 20, ky + 3 * 40 + 4], fill='white', outline='black', width=2)
for i, (nm, st) in enumerate(zip(names, styles)):
    yy = ky + 12 + i * 40
    styled([(kx, yy), (kx + 90, yy)], st, 4)
    d.text((kx + 110, yy), nm, font=fM, fill='black', anchor='lm')
im.save('/tmp/bw/print-bw-sample.png')
print('ok')
