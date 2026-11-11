# ircapture_rack_mock.py: the rack units (ircapture_rack.py) stacked into a mock of the window, for Lowell to judge
# (2026-11-11). Not app code: a picture. 14 pt a cm, 2 px a pt (28 px/cm renders, placed 1:1).
#
#   python3 design/render/ircapture_rack_mock.py <renders dir> <SwellKit pictures dir> <old screenshot or -> <out.png> [unit,unit,...]
import sys, os, json
from PIL import Image, ImageFilter, ImageDraw
import numpy as np

RD, KIT, SHOT, OUTP = sys.argv[1:5]
ORDER = sys.argv[5].split(',') if len(sys.argv) > 5 else ['step', 'patch', 'meters', 'gap', 'results']
PXCM = 28.0; U = 4.445; PW = 48.26
WPT = 920; W = WPT * 2
lay = {}
for f in os.listdir(RD):
    if f.startswith('rack-') and f.endswith('.json'): lay.update(json.load(open(os.path.join(RD, f)))['out'])
UN = {'step': 1, 'patch': 2, 'meters': 5, 'gap': 1, 'results': 6}

# the shelf strip from the old screenshot (the 11-04 shelf from above, 8 pt a cm: context only)
top = None
if SHOT != '-':
    s = Image.open(SHOT).convert('RGB')
    top = s.crop((52, 25, 972, 153)).resize((W, 128 * 2), Image.LANCZOS)
TOP_H = top.size[1] if top else 60
rack_h = int(round(sum(UN[u] for u in ORDER) * U * PXCM))
CHEEK = int(round(1.9 * PXCM)); CAP = CHEEK
H = TOP_H + 26 + CAP + rack_h + CAP + 70
im = Image.new('RGB', (W, H), (40, 44, 48))
# the wall: the bench's pegboard, its holes an inch apart at this scale
peg = Image.open(os.path.join(KIT, 'frame-peg@2x.webp')).convert('RGB')
t = int(round(10 * 2.54 * PXCM)); peg = peg.resize((t, t), Image.LANCZOS)
for y in range(0, H, t):
    for x in range(0, W, t): im.paste(peg, (x, y))
if top: im.paste(top, (0, 0))
x0 = (W - int(round(PW * PXCM))) // 2          # the panels' left edge
y0 = TOP_H + 26 + CAP                            # the first unit's top
pw = int(round(PW * PXCM))

# the rack's shadow on the wall, then its dark inside
sh = Image.new('L', (W, H), 0); d = ImageDraw.Draw(sh)
d.rectangle([x0 - CHEEK + 10, y0 - CAP + 16, x0 + pw + CHEEK + 26, y0 + rack_h + CAP + 30], fill=150)
sh = sh.filter(ImageFilter.GaussianBlur(16))
im = Image.composite(Image.new('RGB', (W, H), (8, 8, 9)), im, sh)
ImageDraw.Draw(im).rectangle([x0 - 2, y0 - 2, x0 + pw + 2, y0 + rack_h + 2], fill=(6, 6, 6))


def over(dst, src, xy):
    dst.paste(src, xy, src)


# the units
y = y0
for u in ORDER:
    L = lay['unit-' + u]; p = Image.open(os.path.join(RD, 'unit-%s.png' % u)).convert('RGBA')
    over(im, p, (int(round(x0 - L['tl'][0])), int(round(y - L['tl'][1]))))
    y += int(round(UN[u] * U * PXCM))

# the wooden sides and top (rough shop-wood boards on edge), if rendered
tv = os.path.join(RD, 'trim-v.png'); th = os.path.join(RD, 'trim-h.png')
if os.path.exists(tv) and 'trim-v' in lay:
    Lv = lay['trim-v']; v = Image.open(tv).convert('RGBA')
    need = rack_h + 2 * CAP
    v = v.crop((0, 0, v.size[0], min(v.size[1], need)))
    for side, xx in ((0, x0 - CHEEK), (1, x0 + pw)):
        vv = v if side == 0 else v.transpose(Image.FLIP_TOP_BOTTOM)
        over(im, vv, (int(round(xx - Lv['px_left'])), y0 - CAP))
    if os.path.exists(th) and 'trim-h' in lay:
        Lh = lay['trim-h']; hh = Image.open(th).convert('RGBA')
        hh = hh.crop((0, 0, min(hh.size[0], pw), hh.size[1]))
        for yy, im_h in ((y0 - CAP, hh), (y0 + rack_h, hh.transpose(Image.FLIP_LEFT_RIGHT))):
            over(im, im_h, (x0, int(round(yy - Lh['row_top']))))
else:
    d = ImageDraw.Draw(im)
    d.rectangle([x0 - CHEEK, y0 - CAP, x0 - 1, y0 + rack_h + CAP], fill=(58, 44, 30))
    d.rectangle([x0 + pw, y0 - CAP, x0 + pw + CHEEK, y0 + rack_h + CAP], fill=(58, 44, 30))
im.save(OUTP)
print(OUTP, im.size)
