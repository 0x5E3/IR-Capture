# ircapture_contact.py: a contact sheet of IR Capture's own pieces (helper for IR Capture, 2026-11-03): each piece over a
# mid grey and over the pegboard, each panel tiled 3 x 3 (its 9-slice laid larger, to check the seams), and a mock shelf
# (the plank strip with a bronze and an oxblood box standing on it, the trim round the opening under it) over the
# pegboard, all at the 1x pictures' points x 2 (the @2x files).
#   python3 design/render/ircapture_contact.py Resources/SwellKit <out.png>
import sys, os, json
from PIL import Image, ImageDraw, ImageFont

K = sys.argv[1]; OUTP = sys.argv[2]
PIC = os.path.join(K, 'pictures')
J = json.load(open(os.path.join(K, 'irc-pieces.json')))['pieces']
S = 2                                     # @2x px a 1x px
try: F = ImageFont.truetype(os.path.join(K, 'fonts', 'Barlow-600-normal.ttf'), 30)
except Exception: F = ImageFont.load_default()


def pic(name): return Image.open(os.path.join(PIC, name + '@2x.webp')).convert('RGBA')


def peg(w, h):
    t = Image.open(os.path.join(PIC, 'frame-peg@2x.webp')).convert('RGBA')
    im = Image.new('RGBA', (w, h))
    for x in range(0, w, t.width):
        for y in range(0, h, t.height): im.paste(t, (x, y))
    return im


def over(im, bg):
    b = (Image.new('RGBA', im.size, bg) if isinstance(bg, tuple) else bg.crop((0, 0) + im.size)).copy()
    b.alpha_composite(im); return b


def nine(name, w, h):
    """The panel's 9-slice laid w x h (@2x px): corners whole, edges and middle repeated (tile)."""
    im = pic(name); m = J[name]; c = int(round(m['capInsets']['top'] * m['px_per_pt'] * S))
    W, H = im.size; out = Image.new('RGBA', (w, h))
    mid = im.crop((c, c, W - c, H - c)); tw, th = mid.size
    for x in range(c, w - c, tw):
        for y in range(c, h - c, th):
            out.paste(mid.crop((0, 0, min(tw, w - c - x), min(th, h - c - y))), (x, y))
    for x in range(c, w - c, tw):
        ww = min(tw, w - c - x)
        out.paste(im.crop((c, 0, c + ww, c)), (x, 0)); out.paste(im.crop((c, H - c, c + ww, H)), (x, h - c))
    for y in range(c, h - c, th):
        hh = min(th, h - c - y)
        out.paste(im.crop((0, c, c, c + hh)), (0, y)); out.paste(im.crop((W - c, c, W, c + hh)), (w - c, y))
    for (sx, sy, dx, dy) in ((0, 0, 0, 0), (W - c, 0, w - c, 0), (0, H - c, 0, h - c), (W - c, H - c, w - c, h - c)):
        out.paste(im.crop((sx, sy, sx + c, sy + c)), (dx, dy))
    return out


def box3(name, w):
    """A box's 3-slice laid w @2x px wide: the ends whole, the middle repeated."""
    im = pic(name); m = J[name]; ppt = m['px_per_pt'] * S
    l = int(round(m['capInsets']['leading'] * ppt)); r = int(round(m['capInsets']['trailing'] * ppt))
    W, H = im.size; out = Image.new('RGBA', (w, H))
    mid = im.crop((l, 0, W - r, H)); tw = mid.width
    for x in range(l, w - r, tw): out.paste(mid.crop((0, 0, min(tw, w - r - x), H)), (x, 0))
    out.paste(im.crop((0, 0, l, H)), (0, 0)); out.paste(im.crop((W - r, 0, W, H)), (w - r, 0))
    return out


def strip(name, length, vertical=False):
    im = pic(name); out = Image.new('RGBA', (im.width, length) if vertical else (length, im.height))
    step = im.height if vertical else im.width
    for o in range(0, length, step): out.paste(im, (0, o) if vertical else (o, 0))
    return out


rows = []
def label(t):
    im = Image.new('RGBA', (1, 34)); rows.append(('label', t)); return


blocks = []
def add(title, ims):
    blocks.append((title, ims))


GREY = (128, 128, 128, 255)
for n in ('rkit-panel-fine', 'rkit-panel-nam'):
    p = pic(n)
    t = nine(n, p.width * 3 - 2 * int(round(J[n]['capInsets']['top'] * 4.8)), p.height * 2)
    c = int(round(J[n]['capInsets']['top'] * 4.8)); mid = p.crop((c, c, p.width - c, p.height - c))
    t3 = Image.new('RGBA', (mid.width * 3, mid.height * 3))
    for i in range(3):
        for j in range(3): t3.paste(mid, (i * mid.width, j * mid.height))
    dd = ImageDraw.Draw(t)
    try: LF = ImageFont.truetype(os.path.join(K, 'fonts', 'BarlowSemiCondensed-600-normal.ttf'), 34)
    except Exception: LF = F
    dd.text((90, 90), 'CAB IR  ·  INPUT LEVEL  ·  CAPTURE', fill=(0xE6, 0xE1, 0xD4, 255), font=LF)
    dd.text((90, 140), 'Reamp level about that of a guitar', fill=(0xD9, 0xD2, 0xC2, 255), font=LF)
    add('%s  %dx%d (1x %dx%d)  on grey, on pegboard, 9-slice laid 3x wider and 2x taller, its middle tiled 3x3; '
        'contrast #E6E1D4 %.1f:1' % (n, p.width, p.height, J[n]['px'][0], J[n]['px'][1], J[n]['contrast_on_mean']['#E6E1D4']),
        [over(p, GREY), over(p, peg(p.width, p.height)), over(t, peg(t.width, t.height)), t3])
pl = strip('irc-plank', 2 * pic('irc-plank').width + 900)
add('irc-plank @2x %dx%d, laid 2.3 periods (seams at %d and %d px) over grey and pegboard' %
    (pic('irc-plank').width, pic('irc-plank').height, pic('irc-plank').width, 2 * pic('irc-plank').width),
    [over(pl, GREY), over(pl, peg(pl.width, pl.height))])
for b in ('irc-box-bronze', 'irc-box-oxblood'):
    p = pic(b); w3 = box3(b, int(p.width * 1.9))
    add('%s @2x %dx%d; laid 1.9x wide (3-slice)' % (b, p.width, p.height), [over(p, GREY), over(p, peg(p.width, p.height)), over(w3, peg(w3.width, w3.height))])
th = strip('irc-trim-h', 2400); tv = strip('irc-trim-v', 1600, True)
add('irc-trim-h and irc-trim-v (2.x periods each) over grey and pegboard', [over(th, GREY), over(th, peg(th.width, th.height))])

# the mock shelf: the plank strip, a bronze box and an oxblood box on it, the trim round the opening below
Wm = 3000
plk = strip('irc-plank', Wm); ppt = J['irc-plank']['px_per_pt'] * S
ft = int(round(J['irc-plank']['y_pt']['front_top_edge'] * ppt)); fb = int(round(J['irc-plank']['y_pt']['front_bottom_edge'] * ppt))
bb = box3('irc-box-bronze', 1500); bo = box3('irc-box-oxblood', 1100)
y0 = bb.height + 20
Hm = y0 - ft + plk.height + 560
mock = peg(Wm, Hm)
op = (120, y0 - ft + fb + 70, Wm - 120, Hm - 40)               # the opening under the shelf
d = ImageDraw.Draw(mock); d.rectangle(op, fill=(18, 15, 12, 255))
mock.alpha_composite(plk, (0, y0 - ft))
ox = 140; mock.alpha_composite(bb, (ox, y0 - bb.height + 0))
mock.alpha_composite(bo, (ox + 1500 + 30, y0 - bo.height))
# trim: top run along the opening's top edge, the sides down it (the face centred on the opening's edge)
tm = J['irc-trim-h']; tv_m = J['irc-trim-v']
tw_px = int(round(tm['face_pt']['w'] * ppt))
fy = int(round(tm['face_pt']['y_top'] * ppt))
trh = strip('irc-trim-h', op[2] - op[0] + tw_px); trb = trh
fx = int(round(tv_m['face_pt']['x_left'] * ppt))
trv = strip('irc-trim-v', op[3] - op[1], True)
mock.alpha_composite(trv, (op[0] - tw_px // 2 - fx, op[1]))
mock.alpha_composite(trv, (op[2] - tw_px // 2 - fx, op[1]))
mock.alpha_composite(trh, (op[0] - tw_px // 2, op[1] - tw_px // 2 - fy))
mock.alpha_composite(trb, (op[0] - tw_px // 2, op[3] - tw_px // 2 - fy))
add('mock shelf @2x: plank strip, boxes laid by plank_overlap_pt (box bottom = strip top + %.2f pt), trim round the opening' %
    J['irc-box-bronze']['plank_overlap_pt'], [mock])

# lay out
pad = 24; Wsheet = max(sum(i.width for i in ims) + pad * (len(ims) + 1) for _, ims in blocks)
Wsheet = min(max(Wsheet, 3100), 6400)
y = pad; placed = []
for title, ims in blocks:
    placed.append(('t', title, (pad, y))); y += 44
    x = pad; hrow = 0
    for im in ims:
        if x + im.width > Wsheet - pad and x > pad: x = pad; y += hrow + pad; hrow = 0
        placed.append(('i', im, (x, y))); x += im.width + pad; hrow = max(hrow, im.height)
    y += hrow + pad
sheet = Image.new('RGBA', (Wsheet, y), (232, 230, 226, 255)); d = ImageDraw.Draw(sheet)
for kind, a, pos in placed:
    if kind == 't': d.text(pos, a, fill=(20, 20, 20, 255), font=F)
    else: sheet.alpha_composite(a, pos)
sheet.convert('RGB').save(OUTP, optimize=True)
print('wrote', OUTP, sheet.size)
