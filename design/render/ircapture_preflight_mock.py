# ircapture_preflight_mock.py: the pre-flight unit as the app fills it in, for a look before CI (2026-11-11).
#
#   python3 design/render/ircapture_preflight_mock.py <Resources/SwellKit> <out.png>
#
# Lays sample lines over rack-preflight.webp as RackPaper.swift does: item and reading typed in Courier Prime at the
# form's baselines (irc-rack.json units.preflight.form), pencil ticks, red-pencil rings, a cross in the OK column, a
# pencilled word beside a noisy room; all multiplied over the paper. Pixels: the kit's (pxPerPoint).
import sys, os, json, math
import numpy as np
from PIL import Image, ImageDraw, ImageFont

KIT, OUTP = sys.argv[1], sys.argv[2]
J = json.load(open(os.path.join(KIT, 'irc-rack.json')))
U = J['units']['preflight']; R = U['preflight']; F = R['form']
PXPT = J['pxPerPoint']
base = Image.open(os.path.join(KIT, 'pictures', U['picture'] + '.webp')).convert('RGB')
sx, sy, sw, sh = [v * PXPT for v in R['sheet']]
k = sw / F['w']
fpx = F['typedCm'] * k; adv = F['advance'] * fpx; advcm = F['advance'] * F['typedCm']
font = ImageFont.truetype(os.path.join(KIT, 'fonts', 'CourierPrime-400.ttf'), int(round(fpx)))
hand = ImageFont.truetype(os.path.join(KIT, 'fonts', 'SwellMarker-400-normal.ttf'), int(round(0.62 * k)))
asc = font.getmetrics()[0]; hasc = hand.getmetrics()[0]
ink = Image.new('RGB', base.size, (255, 255, 255)); d = ImageDraw.Draw(ink)
rng = np.random.default_rng(7)
X = lambda cm: sx + cm * k
Y = lambda cm: sy + cm * k
RED = (196, 74, 66); GRAPHITE = (70, 68, 74)


def typed(text, x, baseline):
    px = X(x)
    for c in text:
        dy = rng.normal() * 0.012 * k; dens = int(np.clip(rng.normal() * 14, -30, 30))
        if c != ' ':
            d.text((px, Y(baseline) - asc + dy), c, font=font, fill=(34 + dens, 32 + dens, 44 + dens))
        px += adv


def pencil(pts, col, w, jit, n=3):
    for _ in range(n):
        s = rng.uniform(0.9, 1.06)
        d.line([(X(x + rng.normal() * jit), Y(y + rng.normal() * jit)) for x, y in pts],
               fill=tuple(int(min(255, v * s)) for v in col), width=max(1, int(w * k * rng.uniform(0.7, 1.0))), joint='curve')


def ring(x, w, mid):
    cx, cy, rx, ry = X(x + w / 2), Y(mid), (w / 2 + 0.32) * k, 0.46 * k
    a0 = 2.2 + rng.uniform() * 0.6; turns = 1.12 + 0.08 * rng.uniform(); wob = rng.uniform() * 6.28
    pts = []
    for i in range(91):
        t = i / 90; ang = a0 + t * turns * 2 * math.pi; rr = 1 + 0.06 * math.sin(3 * ang + wob) + 0.05 * t
        sp = lambda v: math.copysign(abs(v) ** 0.55, v)
        pts.append((cx + rx * rr * sp(math.cos(ang)), cy - ry * rr * sp(math.sin(ang))))
    d.line(pts, fill=RED, width=max(1, int(0.055 * k)), joint='curve')


lines = [('Mics', '2: SM57 cap edge, R121 center', 'tick', None), ('Reference', 'Input 8', 'tick', None),
         ('Sample rate', '96 kHz on Scarlett 18i20 USB', 'tick', None), ('Levels', 'R121 center low by 9 dB', 'ring', None),
         ('Sweep level', '-12 dBFS, set automatically', 'tick', None),
         ('Room noise', 'Noisy: R121 center at -38 dBFS', 'ring', 'fridge? fan?'), ('Files', 'None chosen', 'cross', None)]
cols = F['cols']; ix, rx_, okx = cols[0]['x'] + 0.1, cols[1]['x'] + 0.1, cols[2]['x']
for i, (item, reading, mark, aside) in enumerate(lines[:F['rows']]):
    b = F['baseline0'] + i * F['rowH']; mid = b - 0.22
    typed(item, ix, b); typed(reading, rx_, b)
    if mark == 'tick':
        x = okx + 0.55
        pencil([(x, mid), (x + 0.28, mid + 0.32), (x + 0.92, mid - 0.44)], GRAPHITE, 0.07, 0.03)
    if mark in ('ring', 'cross'):
        w = len(reading) * advcm; ring(rx_, w, mid)
        if mark == 'cross':
            x = okx + 1.1
            pencil([(x - 0.45, mid - 0.45), (x + 0.45, mid + 0.45)], RED, 0.07, 0.025)
            pencil([(x + 0.45, mid - 0.45), (x - 0.45, mid + 0.45)], RED, 0.07, 0.025)
        if aside:
            d.text((X(rx_ + w + 0.9), Y(b + 0.02) - hasc), aside, font=hand, fill=RED)
out = np.asarray(base, np.float32) / 255 * (np.asarray(ink, np.float32) / 255)
Image.fromarray((out * 255).astype(np.uint8)).save(OUTP)
print('wrote', OUTP, base.size)
