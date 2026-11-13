# ircapture_bay_mock.py: a whole bay for Lowell to judge (2026-11-12, eighth chat). Not app code: a picture.
#
# New units come from ircapture_rack.py's proof renders (28 px/cm: 2 px a point); the units already built come from the
# app's kit, laid out as the app lays them (their _mock.py outputs where a unit has live parts, so meters, sheets and the
# deck show a take; the kit's base picture otherwise), scaled from 3 px a point to 2. The shelf is ircapture_shelf_mock.py's.
#
#   python3 design/render/ircapture_bay_mock.py <kit> <proof renders> <mocks dir> <out.png> <unit[,unit...]> [width pt]
# A unit name is taken from the proof renders (unit-<name>.png) if there is one, else <mocks>/mk-<name>.png, else the
# kit's base picture. <mocks>/mk-shelf.png is the shelf (ircapture_shelf_mock.py at the same width).
import sys, os, json
from PIL import Image, ImageDraw, ImageFilter

KIT, RD, MK, OUTP, ORDER = sys.argv[1:6]
ORDER = ORDER.split(',')
WPT = float(sys.argv[6]) if len(sys.argv) > 6 else 920.0
S = 2.0                                                    # px a point
J = json.load(open(os.path.join(KIT, 'irc-rack.json')))
PT, UPT, KS = J['ptPerCm'], J['uPt'], J['pxPerPoint']
PANEL = round(48.26 * PT)
U = {'step-cab': 1, 'step': 1, 'chart': 6, 'patch': 2, 'meters': 5, 'preflight': 4, 'deck': 8, 'results': 7,
     'connect': 2, 'files': 4, 'sweep': 2, 'sweep-open': 2, 'formats': 3, 'formats-open': 3, 'plotter': 6,
     'nammeters': 3, 'cart': 3}
lay = {}
for f in os.listdir(RD):
    if f.startswith('rack-unit-') and f.endswith('.json'): lay.update(json.load(open(os.path.join(RD, f)))['out'])

shelf = Image.open(os.path.join(MK, 'mk-shelf.png')).convert('RGBA')
SHELF_PT, GAP_PT = 168.0, 40.0
# the shelf mock is a whole window's top (its wall runs on below): keep the shelf's own 168 pt
shelf = shelf.crop((0, 0, shelf.size[0], round(SHELF_PT * KS)))
shelf = shelf.resize((round(shelf.size[0] * S / KS), round(shelf.size[1] * S / KS)), Image.LANCZOS)
cv = J['cheeks']['v']; ch = J['cheeks']['h']
BOARD = cv['boardWidth']; TB = ch['boardBottom'] - ch['boardTop']
rack_pt = sum(U[u] * UPT for u in ORDER)
y_rack = SHELF_PT + GAP_PT                                # the top board's top
y0 = y_rack + TB                                          # the first unit's top
H = int((y0 + rack_pt + TB + 60) * S); W = int(WPT * S)
im = Image.new('RGB', (W, H), (40, 44, 48))
peg = Image.open(os.path.join(KIT, 'pictures', 'frame-peg@2x.webp')).convert('RGB')
t = int(round(10 * 2.54 * PT * S)); peg = peg.resize((t, t), Image.LANCZOS)
for y in range(0, H, t):
    for x in range(0, W, t): im.paste(peg, (x, y))
x0 = (WPT - PANEL) / 2
# the rack's shadow on the wall (Rack.swift's), then its dark inside
sh = Image.new('L', (W, H), 0)
ImageDraw.Draw(sh).rectangle([(x0 - BOARD + 10) * S, (y_rack + 16) * S, (x0 + PANEL + BOARD + 26) * S, (y0 + rack_pt + TB + 30) * S], fill=158)
sh = sh.filter(ImageFilter.GaussianBlur(16 * S))
im = Image.composite(Image.new('RGB', (W, H), (0, 0, 0)), im, sh)
ImageDraw.Draw(im).rectangle([x0 * S, y0 * S, (x0 + PANEL) * S, (y0 + rack_pt) * S], fill=(6, 6, 6))
im = im.convert('RGBA')


def kitpic(name):
    p = Image.open(os.path.join(KIT, 'pictures', name + '.webp')).convert('RGBA')
    return p.resize((round(p.size[0] * S / KS), round(p.size[1] * S / KS)), Image.LANCZOS)


y = y0
for u in ORDER:
    if 'unit-' + u in lay:
        L = lay['unit-' + u]; p = Image.open(os.path.join(RD, 'unit-%s.png' % u)).convert('RGBA')
        im.alpha_composite(p, (int(round(x0 * S - L['tl'][0])), int(round(y * S - L['tl'][1]))))
    else:
        k = J['units'][u]; px, py = k['panel'][0], k['panel'][1]
        mk = os.path.join(MK, 'mk-%s.png' % u)
        if os.path.exists(mk):
            p = Image.open(mk).convert('RGBA').crop((0, 0, round(k['size'][0] * KS), round(k['size'][1] * KS)))
            p = p.resize((round(p.size[0] * S / KS), round(p.size[1] * S / KS)), Image.LANCZOS)
        else:
            p = kitpic(k['picture'])
        im.alpha_composite(p, (int(round((x0 - px) * S)), int(round((y - py) * S))))
    y += U[u] * UPT

# the boards: the sides the full height, the top and bottom between them (Rack.swift's RackCheek, RackBoard)
v = kitpic(cv['picture']); hb = kitpic(ch['picture'])
for right, xb in ((False, x0 - BOARD), (True, x0 + PANEL)):
    yy = y_rack; i = 0
    while yy < y0 + rack_pt + TB:
        vv = v.transpose(Image.FLIP_TOP_BOTTOM) if ((i % 2 == 1) != right) else v
        seg = vv.crop((0, 0, vv.size[0], min(vv.size[1], int((y0 + rack_pt + TB - yy) * S))))
        im.alpha_composite(seg, (int(round((xb - cv['boardLeft']) * S)), int(round(yy * S))))
        yy += v.size[1] / S; i += 1
for bottom, yb in ((False, y_rack), (True, y0 + rack_pt)):
    hh = hb.transpose(Image.FLIP_LEFT_RIGHT) if bottom else hb
    seg = hh.crop((0, 0, int(PANEL * S), hh.size[1]))
    im.alpha_composite(seg, (int(round(x0 * S)), int(round((yb - ch['boardTop']) * S))))
im.alpha_composite(shelf, (0, 0))
# the shelf's shadow over the top of the scroll area (Rack.swift's gradient)
g = Image.new('RGBA', (W, int(36 * S)), (0, 0, 0, 0))
for r in range(g.size[1]):
    a_ = int(150 * (1 - r / g.size[1]) ** 2)
    ImageDraw.Draw(g).line([(0, r), (W, r)], fill=(0, 0, 0, a_))
im.alpha_composite(g, (0, int(SHELF_PT * S)))
im.convert('RGB').save(OUTP)
print(OUTP, im.size)
