# ircapture_vu_post.py: ircapture_vu.py's renders made into IR Capture's VU meter pictures (2026-11-10).
#   python3 design/render/ircapture_vu_post.py <renders dir> Resources/SwellKit
# Needs numpy and Pillow. Writes, lossless (webp_out):
#   pictures/irc-vu-lit.webp, irc-vu-unlit.webp (+ @2x)   the meter, its lamp lit and unlit, without the needle: the
#            bezel's outline plus 0.6 cm for its shadow on the panel
#   pictures/irc-vu-needle.webp (+ @2x)                   the needle alone, upright
#   irc-vu.json                                           where the bezel, the window and the pivot are (1x px), the
#            needle's own pivot, its shadow's offset, the angle table; read by Gear.swift (VUKit)
# 1x is 40 px a cm (the app draws the bezel 174 pt wide: 16.1 pt a cm, so 2.5 px a point), @2x 80 when the render is
# dense enough. Like every IR Capture piece, set to its true shape (y stretched by 1 / cos 10).
import sys, os, json, math
import numpy as np
from PIL import Image
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import webp_out

R, O = sys.argv[1], sys.argv[2]
PIC = os.path.join(O, 'pictures'); os.makedirs(PIC, exist_ok=True)
L = json.load(open(os.path.join(R, 'vu-render.json')))
px = L['pxcm']; ce = math.cos(math.radians(L['elev']))
D1 = 40.0
DENS = [D1] + ([2 * D1] if px >= 1.6 * D1 else [])
APP_W = 174.0                                       # the bezel's width in the app, points (MeterModule)


def premul(im):
    a = np.asarray(im.convert('RGBA')).astype(np.float64) / 255.0
    a[..., :3] *= a[..., 3:4]
    return a


def unpremul(a):
    out = a.copy(); al = out[..., 3:4]
    out[..., :3] = np.where(al > 1e-6, out[..., :3] / np.maximum(al, 1e-6), 0.0)
    return Image.fromarray(np.clip(out * 255 + 0.5, 0, 255).astype(np.uint8), 'RGBA')


def resample(path, box, size):
    a = premul(Image.open(path))
    ch = [np.asarray(Image.fromarray(a[..., i].astype(np.float32), 'F').resize(size, Image.LANCZOS, box=tuple(float(v) for v in box)))
          for i in range(4)]
    out = np.clip(np.stack(ch, -1).astype(np.float64), 0, 1)
    out[..., :3] = np.minimum(out[..., :3], out[..., 3:4])
    return out


def save(a, name):
    p = os.path.join(PIC, name + '.webp'); unpremul(a).save(p, 'WEBP'); print(name, os.path.getsize(p), flush=True)


(bx0, by0), (bx1, by1) = L['bezel_tl'], L['bezel_br']
m = 0.6 * px
left, top = max(0.0, bx0 - m), max(0.0, by0 - m)
right, bot = min(L['size'][0], bx1 + m), min(L['size'][1], by1 + m)
f1 = D1 / px                                        # 1x px per render px, across; down it is f1 / ce
W1, H1 = int(round((right - left) * f1)), int(round((bot - top) * f1 / ce))
right, bot = left + W1 / f1, top + H1 * ce / f1
X = lambda x: (x - left) * f1
Y = lambda y: (y - top) * f1 / ce
for k, d in enumerate(DENS):
    s = d / D1
    for state in ('lit', 'unlit'):
        save(resample(os.path.join(R, 'vu-%s.png' % state), (left, top, right, bot), (int(W1 * s), int(H1 * s))),
             'irc-vu-%s%s' % (state, '' if k == 0 else '@2x'))
nb = L['needle_box']
NW, NH = int((nb[2] - nb[0]) * f1), int((nb[3] - nb[1]) * f1 / ce)      # (the needle's picture is its crop alone)
for k, d in enumerate(DENS):
    s = d / D1
    save(resample(os.path.join(R, 'vu-needle.png'), (0, 0, NW / f1, NH * ce / f1), (int(NW * s), int(NH * s))),
         'irc-vu-needle' + ('' if k == 0 else '@2x'))
for k, d in enumerate([2 * D1]):
    if d not in DENS:
        for n in ('irc-vu-lit@2x', 'irc-vu-unlit@2x', 'irc-vu-needle@2x'):
            p = os.path.join(PIC, n + '.webp')
            if os.path.exists(p): os.remove(p)
(wx0, wy0), (wx1, wy1) = L['window_tl'], L['window_br']
pv = L['pivot']
sh = L.get('needle_shadow_px', [0.0, 0.0])
ow = (bx1 - bx0) * f1
doc = {'about': 'IR Capture\'s VU meter (design/render/ircapture_vu.py, the Tools studio; ircapture_vu_post.py). Pixels of '
                'the 1x files; the app scales by its width over outline[2]. lit and unlit are the same meter with its lamp '
                'on and off (cross-faded as the lamp warms); the needle is turned about needle_pivot, laid on pivot, by '
                'the angle table (degrees from vertical by VU), and masked to the window.',
       'lit': 'irc-vu-lit', 'unlit': 'irc-vu-unlit', 'needle': 'irc-vu-needle',
       'px_per_pt': round(ow / APP_W, 3), 'size': [W1, H1],
       'outline': [round(X(bx0), 2), round(Y(by0), 2), round(ow, 2), round(Y(by1) - Y(by0), 2)],
       'window': [round(X(wx0), 2), round(Y(wy0), 2), round(X(wx1) - X(wx0), 2), round(Y(wy1) - Y(wy0), 2)],
       'pivot': [round(X(pv[0]), 2), round(Y(pv[1]), 2)],
       'needle_size': [NW, NH], 'needle_pivot': [round((pv[0] - nb[0]) * f1, 2), round((pv[1] - nb[1]) * f1 / ce, 2)],
       'shadow': [round(sh[0] * f1, 2), round(sh[1] * f1 / ce, 2), round(L.get('needle_shadow_soft_px', 1.0) * f1, 2)],
       'angles': L['angles'], 'render': {'pxcm': px, 'samples': L['samples']}}
json.dump(doc, open(os.path.join(O, 'irc-vu.json'), 'w'), indent=1)
print('wrote', os.path.join(O, 'irc-vu.json'))
