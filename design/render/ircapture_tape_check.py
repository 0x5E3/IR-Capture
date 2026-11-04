# ircapture_tape_check.py: the reel deck put together from the kit's pictures the way TapeDeck.swift does it (2026-11-04).
#   python3 design/render/ircapture_tape_check.py Resources/SwellKit <out.png> [phi_s phi_t p]
# For checking the layers line up before a CI build: rear shadow turned round its centre, rear flange with its windows
# cut by the mask, the pack cut to its radius (edge a shade darker), the free tape, the front shadow inside the flange,
# the front flange, the prong frame; then the counter wheels. 1x pictures, drawn at 2x for a closer look.
import sys, os, json, math
import numpy as np
from PIL import Image, ImageDraw, ImageEnhance

KIT, OUTP = sys.argv[1], sys.argv[2]
PHI_S = float(sys.argv[3]) if len(sys.argv) > 3 else 23.0
PHI_T = float(sys.argv[4]) if len(sys.argv) > 4 else 71.0
PROG = float(sys.argv[5]) if len(sys.argv) > 5 else 0.37
S = 2.0                                   # drawing scale, px a pt
J = json.load(open(os.path.join(KIT, 'tape-pieces.json')))['deck']
EY = J['ellipse_y']


def pic(name):
    for suf, ppp in (('@2x', 4.8), ('', 2.4)):
        p = os.path.join(KIT, 'pictures', name + suf + '.webp')
        if os.path.exists(p): return Image.open(p).convert('RGBA'), ppp
    raise FileNotFoundError(name)


def placed(name, rect):
    im, _ = pic(name)
    return im.resize((int(round(rect[2] * S)), int(round(rect[3] * S))), Image.LANCZOS)


def mask_poly(size, polys, invert):
    m = Image.new('L', size, 0 if invert else 255) if False else Image.new('L', size, 255 if invert else 0)
    d = ImageDraw.Draw(m)
    for p in polys: d.polygon(p, fill=0 if invert else 255)
    return m


def windows(c, reel, phi):
    w = reel['win']; out = []
    for k in range(3):
        a0 = w['a0_deg'] + 120 * k - phi; a1 = a0 + w['span_deg']
        pts = [(c[0] + w['r1'] * math.cos(math.radians(a0 + (a1 - a0) * i / 24)), c[1] - w['r1'] * math.sin(math.radians(a0 + (a1 - a0) * i / 24)) * EY) for i in range(25)]
        pts += [(c[0] + w['r0'] * math.cos(math.radians(a1 - (a1 - a0) * i / 24)), c[1] - w['r0'] * math.sin(math.radians(a1 - (a1 - a0) * i / 24)) * EY) for i in range(25)]
        out.append([(x * S, y * S) for x, y in pts])
    return out


def ellipse(size, c, r, dy=0.0):
    m = Image.new('L', size, 0); d = ImageDraw.Draw(m)
    d.ellipse([(c[0] - r) * S, (c[1] + dy - r * EY) * S, (c[0] + r) * S, (c[1] + dy + r * EY) * S], fill=255)
    return m


def with_mask(im, m):
    a = np.asarray(im).copy(); a[..., 3] = (a[..., 3].astype(np.float64) * np.asarray(m) / 255).astype(np.uint8)
    return Image.fromarray(a, 'RGBA')


def tangent(c1s, r1, s1, c2s, r2, s2):
    c1 = np.array([c1s[0], -c1s[1] / EY]); c2 = np.array([c2s[0], -c2s[1] / EY])
    D = c2 - c1; k = s2 * r2 - s1 * r1; dd = D @ D; L = math.sqrt(max(0, dd - k * k))
    perp = lambda v: np.array([-v[1], v[0]])
    t = (L * D - k * perp(D)) / dd
    a = c1 - s1 * r1 * perp(t); b = c2 - s2 * r2 * perp(t)
    return (a[0], -a[1] * EY), (b[0], -b[1] * EY)


deck = placed('tape-deck', [0, 0] + J['size'])
canvas = deck.copy()
for key, phi, side in (('s', PHI_S, 1 - PROG), ('t', PHI_T, PROG)):
    r = J['reels'][key]; bx = r['box']
    loc = lambda a: (a[0] - bx[0], a[1] - bx[1])
    size = (int(round(bx[2] * S)), int(round(bx[3] * S)))
    layer = Image.new('RGBA', canvas.size, (0, 0, 0, 0))
    def put(im): layer.alpha_composite(im, (int(round(bx[0] * S)), int(round(bx[1] * S))))
    sh = placed('tape-reel-%s-rearshadow' % key, bx)
    sc = loc(r['shadow_c_rear'])
    put(sh.rotate(-phi, resample=Image.BICUBIC, center=(sc[0] * S, sc[1] * S)))
    put(with_mask(placed('tape-reel-%s-rear' % key, bx), mask_poly(size, windows(loc(r['c_rear']), r, phi), True)))
    hub, full = r['hub'], r['pack_full']
    rp = math.sqrt(hub * hub + (full * full - hub * hub) * side)
    pk = placed('tape-reel-%s-pack' % key, bx)
    if rp > hub + 0.5:
        put(with_mask(ImageEnhance.Brightness(pk).enhance(0.8), ellipse(size, loc(r['c_pack']), rp, -r['tape_thick'])))
        put(with_mask(pk, ellipse(size, loc(r['c_pack']), rp)))
        ro = J['rollers'][0 if key == 's' else 1]
        a, b = (tangent(r['c_pack'], rp, -1, ro['c'], ro['r'], 1) if key == 's' else tangent(ro['c'], ro['r'], 1, r['c_pack'], rp, -1))
        canvas.alpha_composite(layer); layer = Image.new('RGBA', canvas.size, (0, 0, 0, 0))
        ImageDraw.Draw(canvas).line([(a[0] * S, a[1] * S), (b[0] * S, b[1] * S)], fill=(78, 53, 35, 255), width=max(1, int(r['tape_thick'] * S)))
    fs = placed('tape-reel-%s-frontshadow' % key, bx)
    fc = loc(r['shadow_c_front'])
    put(with_mask(fs.rotate(-phi, resample=Image.BICUBIC, center=(fc[0] * S, fc[1] * S)), ellipse(size, loc(r['c_front']), r['r'])))
    put(with_mask(placed('tape-reel-%s-front' % key, bx), mask_poly(size, windows(loc(r['c_front']), r, phi), True)))
    pr, _ = pic('tape-reel-%s-prongs' % key)
    n = r['prongs']['frames']; i = int(round(phi / (r['prongs']['span_deg'] / n))) % n
    fw = pr.width // n
    pb = r['prongs']['box']
    fr = pr.crop((i * fw, 0, (i + 1) * fw, pr.height)).resize((int(round(pb[2] * S)), int(round(pb[3] * S))), Image.LANCZOS)
    layer.alpha_composite(fr, (int(round(pb[0] * S)), int(round(pb[1] * S))))
    canvas.alpha_composite(layer)
wh, _ = pic('tape-wheels'); wb = J['wheel_box']; fw = wh.width // 10
for i, w in enumerate(J['wheels']):
    dgt = int(('%04d' % 27)[i])
    fr = wh.crop((dgt * fw, 0, (dgt + 1) * fw, wh.height)).resize((int(round(wb[2] * S)), int(round(wb[3] * S))), Image.LANCZOS)
    canvas.alpha_composite(fr, (int(round((wb[0] + w[0] - J['wheels'][0][0]) * S)), int(round(wb[1] * S))))
bg = Image.new('RGBA', canvas.size, (38, 30, 24, 255)); bg.alpha_composite(canvas)
bg.convert('RGB').save(OUTP)
print('wrote', OUTP, bg.size)
