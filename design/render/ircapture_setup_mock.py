# ircapture_setup_mock.py: the fourth proof's units as the app draws them, from the kit (11-12, a check before CI).
#
#   python3 design/render/ircapture_setup_mock.py <Resources/SwellKit> <out.png> [shut|open]
#
# connect, files, sweep, formats and plotter stacked: each base with sample states laid over it (keys lit and down, a
# selector turned, thumbwheel figures from the unit's figure sheet), the covers shut (the live controls multiplied by
# the pane's tint, its sheen added, the hardware over them) or open, the plotter's arm and pen carriage moved part way
# with a made-up curve inked, the card's and the VFD's places outlined. Not the app: a check that every place in
# irc-rack.json lands where it should.
import sys, os, json, math
from PIL import Image, ImageDraw, ImageChops
import numpy as np

KIT, OUTP = sys.argv[1], sys.argv[2]
SHUT = (sys.argv[3] if len(sys.argv) > 3 else 'shut') == 'shut'
J = json.load(open(os.path.join(KIT, 'irc-rack.json')))
K = J['pxPerPoint']
PIC = os.path.join(KIT, 'pictures')


def img(n): return Image.open(os.path.join(PIC, n + '.webp')).convert('RGBA')
def P(v): return round(v * K)


def lay(out, U, name):
    L = U['layers'].get(name)
    if L is None: print('  no layer', name); return
    out.alpha_composite(img(L['picture']), (P(L['rect'][0]), P(L['rect'][1])))


def figures(out, W, values):
    sh = img(W['picture']); n = 10; fw = sh.size[0] // n
    for i, v in enumerate(values):
        if v is None: continue
        f = sh.crop((v * fw, 0, (v + 1) * fw, sh.size[1]))
        r = W['windows'][i]
        f = f.resize((max(1, P(r[2])), max(1, P(r[3]))), Image.LANCZOS)
        out.alpha_composite(f, (P(r[0]), P(r[1])))


def outline(out, r, col=(255, 0, 0, 255)):
    ImageDraw.Draw(out).rectangle([P(r[0]), P(r[1]), P(r[0] + r[2]), P(r[1] + r[3])], outline=col, width=1)


def cover(out, U, C):
    if not SHUT:
        lay(out, U, 'cover-hw-open'); return
    x, y, w, h = [P(v) for v in C['rect']]
    tint = np.asarray(img(C['tint']).convert('RGB').resize((w, h)), np.float32) / 255 * C['tintScale']
    sheen = np.asarray(img(C['sheen']).convert('RGB').resize((w, h)), np.float32)
    a = np.asarray(out, np.float32).copy()
    reg = a[y:y + h, x:x + w, :3]
    a[y:y + h, x:x + w, :3] = np.clip(reg * tint + sheen, 0, 255)
    out.paste(Image.fromarray(a.astype(np.uint8), 'RGBA'))
    lay(out, U, 'cover-hw')


units = []
# connect: IMPORT DAW down, REFERENCE at TAP OR PAD, OUT TO AMP 01 with its - pressed
U = J['units']['connect']; Cn = U['connect']
o = img(U['picture']); lay(o, U, 'k1-down'); lay(o, U, 'sel0-p2'); figures(o, Cn['wheels'], [0, 1]); lay(o, U, 'tw1-minus')
outline(o, Cn['vfd']['cells'], (0, 255, 200, 255))
for k in Cn['keys']: outline(o, k['rect'], (255, 255, 0, 255))
for q in Cn['selectors'][0]['labels']: outline(o, q, (255, 0, 255, 255))
units.append(o)
# files: UNIVERSAL lit, MIN PHASE lit and down, CHANGE down; the card's lines outlined
U = J['units']['files']; F = U['files']
o = img(U['picture']); lay(o, U, 'k0-lit'); lay(o, U, 'k3-litdown'); lay(o, U, 'k5-down')
sx, sy, sw, sh_ = F['sheet']; fm = F['form']; k = sw / fm['w']
for f in fm['fields']:
    for b in f['baselines']:
        ImageDraw.Draw(o).line([P(sx + f['x0'] * k), P(sy + b * k), P(sx + f['x1'] * k), P(sy + b * k)], fill=(255, 0, 0, 255))
units.append(o)
# sweep: RATE at 48, LEVEL at -12, figures 08 / 06.0 / 02.5 / 1
U = J['units']['sweep']; S = U['sweep']
o = img(U['picture']); lay(o, U, 'sel0-p2'); lay(o, U, 'sel1-p2')
figures(o, S['wheels'], [0, 8, 0, 6, 0, 0, 2, 5, 1])
cover(o, U, S['cover']); units.append(o)
# formats: POLARITY at AS RECORDED, CUSTOM ON (base up), 48 96 FULL 24 KEEP TIMING lit, FULL ms 0500
U = J['units']['formats']; Fm = U['formats']
o = img(U['picture']); lay(o, U, 't0-down')
for i in (1, 3, 4, 9, 11): lay(o, U, 'k%d-lit' % i)
figures(o, Fm['wheels'], [0, 5, 0])
cover(o, U, Fm['cover']); units.append(o)
# plotter: the arm part way, a curve inked as far as the arm, the pen down on it
U = J['units']['plotter']; Pz = U['plotter']
o = img(U['picture']); g = Pz['grid']; frac = 0.62
xs = np.geomspace(20, 20000, 200); lf = np.log10(xs)
ys = -12 * np.log10(1 + (75 / xs) ** 4) + 5 * np.exp(-((lf - math.log10(2800)) / 0.12) ** 2) - 30 * np.log10(1 + (xs / 5200) ** 6) / 1.5 - 8
X = lambda f: g[0] + math.log10(f / 20) / 3 * g[2]
Y = lambda db: g[1] + (0 - max(-60, min(0, db))) / 60 * g[3]
pts = [(X(f), Y(v)) for f, v in zip(xs, ys) if X(f) <= g[0] + frac * g[2]]
ink = Image.new('RGBA', o.size, (0, 0, 0, 0)); ImageDraw.Draw(ink).line([(P(a), P(b)) for a, b in pts], fill=(196, 84, 30, 230), width=max(1, P(0.6)))
o.alpha_composite(ink)
ax = pts[-1][0]; dx = ax - Pz['park']; dy = pts[-1][1] - Pz['penAt'][1]
pa = Pz['parts']
for nm, ox, oy in (('armshadow', dx, 0), ('arm', dx, 0), ('penshadow', dx, dy), ('carriage', dx, dy), ('pen-0', dx, dy)):
    if nm not in pa: continue
    r = pa[nm]['rect']; o.alpha_composite(img(pa[nm]['picture']), (P(r[0] + ox), P(r[1] + oy)))
outline(o, Pz['grid'], (0, 160, 255, 255))
units.append(o)

W = max(u.size[0] for u in units); H = sum(u.size[1] for u in units) + 8 * (len(units) - 1)
out = Image.new('RGBA', (W, H), (40, 36, 30, 255)); y = 0
for u in units: out.alpha_composite(u, (0, y)); y += u.size[1] + 8
out.save(OUTP)
print(OUTP, out.size)
