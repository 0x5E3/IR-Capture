# ircapture_results_mock.py: the results unit as the app fills it in, for a look before CI (2026-11-11).
#
#   python3 design/render/ircapture_results_mock.py <Resources/SwellKit> <out.png> [verdict]
#
# Lays a sample take over rack-results.webp as RackResults.swift does: typed entries in Courier Prime at the form's
# baselines (irc-rack.json units.results.form), figures right-aligned in their columns, pencil dabs, a red-pencil ring,
# the stamp in the CHECKED box; all multiplied over the paper. Pixels: the kit's (pxPerPoint).
import sys, os, json, math
import numpy as np
from PIL import Image, ImageDraw, ImageFont

KIT, OUTP = sys.argv[1], sys.argv[2]
VERDICT = sys.argv[3] if len(sys.argv) > 3 else 'check'
J = json.load(open(os.path.join(KIT, 'irc-rack.json')))
U = J['units']['results']; R = U['results']; F = R['form']
PXPT = J['pxPerPoint']
base = Image.open(os.path.join(KIT, 'pictures', U['picture'] + '.webp')).convert('RGB')
sx, sy, sw, sh = [v * PXPT for v in R['sheet']]
k = sw / F['w']                                        # px a sheet cm
fpx = F['typedCm'] * k; adv = F['advance'] * fpx
font = ImageFont.truetype(os.path.join(KIT, 'fonts', 'CourierPrime-400.ttf'), int(round(fpx)))
asc = font.getmetrics()[0]
ink = Image.new('RGB', base.size, (255, 255, 255)); d = ImageDraw.Draw(ink)
rng = np.random.default_rng(7)
X = lambda cm: sx + cm * k
Y = lambda cm: sy + cm * k


def typed(text, x, baseline):
    px = X(x)
    for c in text:
        dy = rng.normal() * 0.012 * k; dens = int(np.clip(rng.normal() * 14, -30, 30))
        if c != ' ':
            d.text((px, Y(baseline) - asc + dy), c, font=font, fill=(34 + dens, 32 + dens, 44 + dens))
        px += adv


def chars(x0, x1): return max(1, int((x1 - x0) * k / adv))


def fit(s, n): return s if len(s) <= n else s[:max(1, n - 1)] + '…'


def wrap(s, n):
    out, line = [], ''
    for w in s.split():
        if not line: line = ('  ' if out else '') + w
        elif len(line) + 1 + len(w) <= n: line += ' ' + w
        else: out.append(line); line = '  ' + w
    if line: out.append(line)
    return out


take = dict(capture='Mesa_4x12_V30_posA', date='11 NOV 26', interface='Scarlett 18i20 USB', rate='96 kHz')
rows = [('SM57', 0, dict(peak='-11.6', noise='-108', tail='36', h2='-45', h3='-52', arrival='0.17'), ()),
        ('R121 center', 1, dict(peak='-10.5', noise='-84', tail='451', h2='-27', h3='-51', arrival='0.29'), ('h2',)),
        ('Reference', None, dict(peak='-21.1', noise='-122', tail='360', h2='-', h3='-', arrival='-'), ())]
files = ['Mesa_4x12_V30_posA_SM57.wav', 'Mesa_4x12_V30_posA_R121_center.wav', '48 kHz  24-bit  500 ms']
notes = ['R121 center: harmonic distortion is 27 dB below the linear response. The speaker is being driven hard; an IR '
         "can't capture that, so try about 6 dB less level.", '86 IR files, README.txt, report.json. Reference used.',
         'Notes: 57 1 in off cap edge; 121 6 in center']
COLS = [(0.92, 0.6, 0.24), (0.44, 0.64, 0.84)]

for f in F['fields']: typed(fit(take[f['key']], chars(f['x0'] + 0.1, f['x1'])), f['x0'] + 0.1, f['baseline'])
T = F['table']; cols = T['cols']
widths = {c['key']: max(len(r[2][c['key']]) for r in rows) for c in cols[1:]}
for r, (name, col, vals, ring) in enumerate(rows):
    b = T['baseline0'] + r * T['rowH']
    if col is not None:
        cc = COLS[col]
        for _ in range(60):
            a, e = rng.normal() * 0.2, rng.normal() * 0.16; s = rng.uniform(0.85, 1.0)
            d.line([(X(T['dabX'] + a - 0.12), Y(b - 0.2 + e + 0.1)), (X(T['dabX'] + a + 0.12), Y(b - 0.2 + e - 0.1))],
                   fill=tuple(int(255 * v * s) for v in cc), width=max(1, int(0.03 * k)))
    nx = cols[0]['x'] + 0.1 if col is None else T['nameX']
    typed(fit(name, chars(nx, cols[1]['x'] - 0.35)), nx, b)
    for c in cols[1:]:
        v = vals[c['key']]; x = c['x'] + 0.1 + (widths[c['key']] - len(v)) * F['advance'] * F['typedCm']
        typed(v, x, b)
        if c['key'] in ring:
            w = len(v) * F['advance'] * F['typedCm']; cx, cy = X(x + w / 2), Y(b - 0.22); rx, ry = (w / 2 + 0.35) * k, 0.5 * k
            pts = []
            for i in range(91):
                t = i / 90; ang = 2.4 + t * 1.15 * 2 * math.pi; rr = 1 + 0.06 * math.sin(3 * ang + 1) + 0.05 * t
                pts.append((cx + rx * rr * math.cos(ang), cy - ry * rr * math.sin(ang)))
            d.line(pts, fill=(196, 74, 66), width=max(1, int(0.055 * k)), joint='curve')
for i, f in enumerate(files): typed(f, F['files']['x0'], F['files']['baselines'][i])
N = F['notes']; lines = []
for n in notes: lines += wrap(n, chars(N['x0'], N['x1']))
for i, l in enumerate(lines[:len(N['baselines'])]): typed(l, N['x0'], N['baselines'][i])
# the stamp
st = R['stamps'][VERDICT]
sp = Image.open(os.path.join(KIT, 'pictures', st['picture'] + '.webp')).convert('RGBA')
sp = sp.resize((int(st['size'][0] * PXPT), int(st['size'][1] * PXPT)), Image.LANCZOS).rotate(5.0, resample=Image.BICUBIC, expand=True)
c = F['checked']; cx, cy = X((c[0] + c[2]) / 2), Y((c[1] + c[3]) / 2 + 0.15)
a = np.asarray(sp, np.float32) / 255
layer = np.asarray(ink, np.float32) / 255
x0, y0 = int(cx - sp.size[0] / 2), int(cy - sp.size[1] / 2)
reg = layer[y0:y0 + sp.size[1], x0:x0 + sp.size[0]]
reg[:] = reg * (1 - a[..., 3:]) + reg * a[..., :3] * a[..., 3:]
out = np.asarray(base, np.float32) / 255 * layer
Image.fromarray((out * 255).astype(np.uint8)).save(OUTP)
print('wrote', OUTP, base.size)
