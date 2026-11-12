# ircapture_machines_mock.py: the reel deck and the cart machine laid over their bases as the app does (RackMachines.swift),
# for checking a render before CI.
#
#   python3 design/render/ircapture_machines_mock.py <Resources/SwellKit> <out-deck.png> <out-cart.png> [p] [phiS] [phiT]
#
# Deck: p of the take wound on (0 all on the supply reel), the reels at phiS / phiT degrees clockwise, the counter at 32,
# CAPTURE lit, REC lit. Cart: 40 % through (1:54 left), RECORD lit, READY and the cues lit; the label printed blank-side
# only (the app's CartLabel is not drawn here).
import sys, os, json, math
from PIL import Image, ImageDraw, ImageChops
import numpy as np

KIT, OUTD, OUTC = sys.argv[1], sys.argv[2], sys.argv[3]
P_ = float(sys.argv[4]) if len(sys.argv) > 4 else 0.4
PHI = [float(sys.argv[5]) if len(sys.argv) > 5 else 37.0, float(sys.argv[6]) if len(sys.argv) > 6 else 211.0]
J = json.load(open(os.path.join(KIT, 'irc-rack.json')))
K = J['pxPerPoint']
pic = lambda n: Image.open(os.path.join(KIT, 'pictures', n + '.webp')).convert('RGBA')
px = lambda v: v * K


def put(dst, im, x, y, mask=None):
    """Alpha-composite im at (x, y) pt; mask (L, im's size) multiplies its alpha."""
    if mask is not None:
        a = np.asarray(im, np.float32).copy(); a[..., 3] *= np.asarray(mask, np.float32) / 255
        im = Image.fromarray(a.astype(np.uint8), 'RGBA')
    layer = Image.new('RGBA', dst.size, (0, 0, 0, 0)); layer.paste(im, (int(round(px(x))), int(round(px(y)))))
    return Image.alpha_composite(dst, layer)


def windows_mask(size, c, win, phi, invert=True):
    """The flange with its three windows cut (white = flange), c in the picture's px."""
    m = Image.new('L', size, 255 if invert else 0); d = ImageDraw.Draw(m)
    for k in range(3):
        a0 = win['a0'] + k * 120 - phi; a1 = a0 + win['span']
        pts = [(c[0] + px(win['r1']) * math.cos(math.radians(a0 + (a1 - a0) * i / 24)),
                c[1] - px(win['r1']) * math.sin(math.radians(a0 + (a1 - a0) * i / 24))) for i in range(25)]
        pts += [(c[0] + px(win['r0']) * math.cos(math.radians(a1 - (a1 - a0) * i / 24)),
                 c[1] - px(win['r0']) * math.sin(math.radians(a1 - (a1 - a0) * i / 24))) for i in range(25)]
        d.polygon(pts, fill=0 if invert else 255)
    return m


def disc(size, c, r):
    m = Image.new('L', size, 0); ImageDraw.Draw(m).ellipse([c[0] - r, c[1] - r, c[0] + r, c[1] + r], fill=255); return m


def tangent(c1, r1, s1, c2, r2, s2):
    """ircapture_tape.tape_path's tangent, screen points (y down): worked with y up."""
    a1 = (c1[0], -c1[1]); a2 = (c2[0], -c2[1])
    D = (a2[0] - a1[0], a2[1] - a1[1]); dd = D[0] ** 2 + D[1] ** 2; k = s2 * r2 - s1 * r1
    L = math.sqrt(max(0, dd - k * k)); pD = (-D[1], D[0])
    t = ((L * D[0] - k * pD[0]) / dd, (L * D[1] - k * pD[1]) / dd); pt_ = (-t[1], t[0])
    a = (a1[0] - s1 * r1 * pt_[0], a1[1] - s1 * r1 * pt_[1]); b = (a2[0] - s2 * r2 * pt_[0], a2[1] - s2 * r2 * pt_[1])
    return (a[0], -a[1]), (b[0], -b[1])


def deck():
    u = J['units']['deck']; D = u['deck']
    im = pic(u['picture'])
    S = im.size
    for L_ in ('k1-lit', 'rec'):
        l = u['layers'][L_]; im = put(im, pic(l['picture']), l['rect'][0], l['rect'][1])
    hub = D['reels']['s']['hub']; full = D['reels']['s']['packFull']; A = full * full - hub * hub
    lead = 0.22 * J['ptPerCm']
    radii = {'s': max(hub + lead, math.sqrt(hub * hub + A * (1 - P_))), 't': max(hub + lead, math.sqrt(hub * hub + A * P_))}
    for key, phi in zip(('s', 't'), PHI):
        r = D['reels'][key]; bx = r['box']
        c = (px(r['c'][0] - bx[0]), px(r['c'][1] - bx[1]))
        size = pic(r['rear']).size
        # rear shadow, turned about its centre
        sc = (r['rearShadowC'][0] - bx[0], r['rearShadowC'][1] - bx[1])
        sh = pic(r['rearshadow']).rotate(-phi, center=(px(sc[0]), px(sc[1])), resample=Image.BICUBIC)
        im = put(im, sh, bx[0], bx[1])
        im = put(im, pic(r['rear']), bx[0], bx[1], windows_mask(size, c, r['win'], phi))
        rp = radii[key]
        im = put(im, pic(r['pack']), bx[0], bx[1], disc(size, c, px(rp)))
        # the free span to its roller (seen edge on: a dark line a point wide)
        d = ImageDraw.Draw(im)
        if key == 's': a, b = tangent(r['c'], rp, -1, r['roller'], r['rollerR'], 1)
        else: a, b = tangent(r['roller'], r['rollerR'], 1, r['c'], rp, -1)
        d.line([(px(a[0]), px(a[1])), (px(b[0]), px(b[1]))], fill=(78, 53, 35, 255), width=max(1, int(round(K * 1.0))))
        fc = (r['frontShadowC'][0] - bx[0], r['frontShadowC'][1] - bx[1])
        fsh = pic(r['frontshadow']).rotate(-phi, center=(px(fc[0]), px(fc[1])), resample=Image.BICUBIC)
        im = put(im, fsh, bx[0], bx[1], disc(size, c, px(r['r'])))
        im = put(im, pic(r['front']), bx[0], bx[1], windows_mask(size, c, r['win'], phi))
        pr = r['prongs']; n = pr['frames']; step = pr['span'] / n
        i = int(round(phi / step)) % n
        sheet = pic(pr['picture']); fw = sheet.size[0] // n
        im = put(im, sheet.crop((i * fw, 0, (i + 1) * fw, sheet.size[1])), pr['box'][0], pr['box'][1])
    W = D['wheels']; sheet = pic(W['picture']); fw = sheet.size[0] // 10
    for q, dg in zip(W['rects'], '0032'):
        f = sheet.crop((int(dg) * fw, 0, (int(dg) + 1) * fw, sheet.size[1])).resize((int(round(px(q[2]))), int(round(px(q[3])))), Image.LANCZOS)
        im = put(im, f, q[0], q[1])
    im.convert('RGB').save(OUTD); print('deck', im.size)


SEG7 = {'0': 'abcdef', '1': 'bc', '2': 'abdeg', '3': 'abcdg', '4': 'bcfg', '5': 'acdfg', '6': 'acdefg', '7': 'abc', '8': 'abcdefg', '9': 'abcdfg'}


def cart():
    u = J['units']['cart']; C = u['cart']
    im = pic(u['picture'])
    for L_ in ('k1-lit', 'l0', 'l1', 'l2', 'colon'):
        l = u['layers'][L_]; im = put(im, pic(l['picture']), l['rect'][0], l['rect'][1])
    l = u['layers']['dig']; dg = pic(l['picture'])
    m = Image.new('L', dg.size, 0); d = ImageDraw.Draw(m)
    for cell, ch in zip(C['cells'], '154'):
        for s_ in SEG7[ch]:
            poly = [(px(p[0] - l['rect'][0]), px(p[1] - l['rect'][1])) for p in C['segs'][cell['abcdefg'.index(s_)]]]
            d.polygon(poly, fill=255); d.line(poly + [poly[0]], fill=255, width=int(round(2 * 1.6 * K)))
    im = put(im, dg, l['rect'][0], l['rect'][1], m)
    lb = C['label']
    ImageDraw.Draw(im).rectangle([px(lb[0]), px(lb[1]), px(lb[0] + lb[2]), px(lb[1] + lb[3])], outline=(200, 40, 30, 120))
    im.convert('RGB').save(OUTC); print('cart', im.size)


if 'deck' in J['units'] and 'deck' in J['units']['deck']: deck()
if 'cart' in J['units'] and 'cart' in J['units']['cart']: cart()
