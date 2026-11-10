# ircapture_tape_post.py: ircapture_tape_layers.py's renders made into IR Capture's tape pictures (2026-11-04).
#   python3 design/render/ircapture_tape_post.py <renders dir> Resources/SwellKit
# Needs only numpy and Pillow. Reads tape-layers-reel.json and/or tape-layers-cart.json in the renders dir.
#
# Each machine has one scale in the app: the deck 11.5 pt a cm (72 cm: 828 pt, the stage's width at the default
# 920 pt window), the cart 16.9 pt a cm. Pictures are written at 2.4 px a pt (1x) and, when the render is dense
# enough (at least 1.6 times 1x), 4.8 (@2x): webp, quality 90. Every crop keeps its place: the layout gives each
# picture's rectangle in points from the machine picture's top left, and the anchors in the same points.
#
#   tape-deck            the deck (crop: the deck's outline plus 0.6 cm for its shadow)
#   tape-reel-<s|t>-<layer>   rear, rearshadow, pack, front, frontshadow (one box per reel)
#   tape-reel-<s|t>-prongs    the 24 prong frames side by side (a sprite sheet)
#   tape-wheels          the counter wheel's ten digits side by side
#   tape-cart            the cart's face; tape-cart-key-<k>-<state>, tape-cart-lamp-<n>, tape-cart-colon
#   tape-cart-digits-<p> the timer digit p's ten frames side by side
#   tape-pieces.json     the layout and anchors (merged: a machine not in this run keeps its entry)
import sys, os, json, glob, math
import numpy as np
from PIL import Image
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import webp_out          # (11-10) every WebP lossless and exact (the bench's rule since 11-06); POST_LOSSY=1 the old

R, O = sys.argv[1], sys.argv[2]
PIC = os.path.join(O, 'pictures')
os.makedirs(PIC, exist_ok=True)
PX_PT = 2.4
PT_CM = {'reel': 11.5, 'cart': 16.9, 'box': 11.5}
out_json = os.path.join(O, 'tape-pieces.json')
META = json.load(open(out_json)) if os.path.exists(out_json) else {}


def premul(im):
    a = np.asarray(im.convert('RGBA')).astype(np.float64) / 255.0
    a[..., :3] *= a[..., 3:4]
    return a


def unpremul(a):
    out = a.copy(); al = out[..., 3:4]
    out[..., :3] = np.where(al > 1e-6, out[..., :3] / np.maximum(al, 1e-6), 0.0)
    return Image.fromarray(np.clip(out * 255 + 0.5, 0, 255).astype(np.uint8), 'RGBA')


def resize(a, size):
    ch = [np.asarray(Image.fromarray(a[..., i].astype(np.float32), 'F').resize(size, Image.LANCZOS)) for i in range(4)]
    out = np.clip(np.stack(ch, -1).astype(np.float64), 0, 1)
    out[..., :3] = np.minimum(out[..., :3], out[..., 3:4])
    return out


class Machine:
    def __init__(self, what):
        self.L = json.load(open(os.path.join(R, 'tape-layers-%s.json' % what)))
        self.what = what
        self.pxcm = self.L['pxcm']
        self.k = PT_CM[what] / self.pxcm            # pt per render px
        self.hd = self.pxcm * self.k * 0 + self.pxcm / PT_CM[what] >= PX_PT * 1.6   # render px per pt is enough for @2x
        A = self.L['anchors']
        key = 'deck' if what == 'reel' else 'cart'
        tl, br = A[key + '_tl'], A[key + '_br']
        m = 0.6 * self.pxcm                          # the shadow margin, render px
        self.origin = (tl[0] - m, tl[1] - m)         # the picture's top left, render px
        self.size_px = (br[0] - tl[0] + 2 * m, br[1] - tl[1] + 2 * m)

    def pt(self, p): return [round((p[0] - self.origin[0]) * self.k, 2), round((p[1] - self.origin[1]) * self.k, 2)]

    def rect(self, box): return self.pt(box[:2]) + [round((box[2] - box[0]) * self.k, 2), round((box[3] - box[1]) * self.k, 2)]

    def load(self, name):
        return premul(Image.open(os.path.join(R, name + '.png')))

    def write(self, a, name, size_pt):
        """a: premultiplied render px; written at 1x and, if dense enough, @2x, both exactly size_pt (rounded px)."""
        for scale, suffix in ((PX_PT, ''), (2 * PX_PT, '@2x')):
            if suffix and not self.hd: continue
            sz = (max(1, int(round(size_pt[0] * scale))), max(1, int(round(size_pt[1] * scale))))
            b = a if (a.shape[1], a.shape[0]) == sz else resize(a, sz)
            p = os.path.join(PIC, name + suffix + '.webp')
            unpremul(b).save(p, 'WEBP', quality=90, method=6)
        print(name, size_pt, os.path.getsize(os.path.join(PIC, name + '.webp')), flush=True)

    def crop_full(self, name):
        """The machine picture: the full render cropped to the outline plus margin (fractional, so resampled)."""
        im = Image.open(os.path.join(R, name + '.png')).convert('RGBA')
        x0, y0 = self.origin; w, h = self.size_px
        size_pt = (w * self.k, h * self.k)
        for scale, suffix in ((PX_PT, ''), (2 * PX_PT, '@2x')):
            if suffix and not self.hd: continue
            sz = (int(round(size_pt[0] * scale)), int(round(size_pt[1] * scale)))
            a = premul(im.transform(sz, Image.EXTENT, (x0, y0, x0 + w, y0 + h), Image.BICUBIC))
            unpremul(a).save(os.path.join(PIC, 'tape-' + name + suffix + '.webp'), 'WEBP', quality=90, method=6)
        print('tape-' + name, [round(v, 1) for v in size_pt], flush=True)
        return [round(size_pt[0], 2), round(size_pt[1], 2)]

    def layer(self, name, out=None):
        box = self.L['crops'][name]
        r = self.rect(box)
        self.write(self.load(name), out or ('tape-' + name), (r[2], r[3]))
        return r

    def sheet(self, names, out):
        box = self.L['crops'][names[0]]
        r = self.rect(box)
        frames = [self.load(n) for n in names]
        a = np.concatenate(frames, axis=1)
        self.write(a, out, (r[2] * len(names), r[3]))
        return r


def centroid(a):
    al = a[..., 3]; ys, xs = np.mgrid[0:al.shape[0], 0:al.shape[1]]
    s = al.sum()
    return (float((xs * al).sum() / s), float((ys * al).sum() / s))


def post_reel():
    M = Machine('reel'); A = M.L['anchors']
    d = {'pt_per_cm': PT_CM['reel'], 'px_per_pt': PX_PT, 'ellipse_y': M.L['ellipse_y'], 'samples': M.L['samples'],
         'render_px_per_cm': M.pxcm}
    d['size'] = M.crop_full('deck')
    tl, br = A['deck_tl'], A['deck_br']
    d['outline'] = M.pt(tl) + [round((br[0] - tl[0]) * M.k, 2), round((br[1] - tl[1]) * M.k, 2)]
    cm = PT_CM['reel']
    reels = {}
    for key in ('s', 't'):
        a = A['reel_' + key]; e = {}
        e['box'] = M.layer('reel-%s-rear' % key)
        for lay in ('rearshadow', 'pack', 'front', 'frontshadow'): M.layer('reel-%s-%s' % (key, lay))
        bx = M.L['crops']['reel-%s-rear' % key]
        for lay in ('rear', 'front'):
            c = centroid(M.load('reel-%s-%sshadow-solid' % (key, lay)))
            e['shadow_c_' + lay] = M.pt((bx[0] + c[0], bx[1] + c[1]))
        for k in ('c_rear', 'c_pack', 'c_front', 'c_plate'): e[k] = M.pt(a[k])
        e['r'] = round(a['r_cm'] * cm, 2); e['hub'] = round(a['hub_cm'] * cm, 2); e['pack_full'] = round(a['pack_full_cm'] * cm, 2)
        w = a['win']; e['win'] = {'a0_deg': w['a0'], 'span_deg': w['span'], 'r0': round(w['r0'] * cm, 2), 'r1': round(w['r1'] * cm, 2)}
        e['tape_thick'] = round(0.635 * math.sin(math.radians(M.L['elev'])) * cm, 2)
        n = a['prong_frames']
        e['prongs'] = {'frames': n, 'span_deg': a['prong_span_deg'],
                       'box': M.sheet(['reel-%s-prong-%02d' % (key, i) for i in range(n)], 'tape-reel-%s-prongs' % key)}
        reels[key] = e
    d['reels'] = reels
    d['keys'] = {k: {'c': M.pt(v['c']), 'w': round(v['w_cm'] * cm, 2), 'h': round(v['h_cm'] * cm, 2)} for k, v in A['keys'].items()}
    d['jewel'] = {'c': M.pt(A['jewel']['c']), 'd': round(A['jewel']['d_cm'] * cm, 2)}
    d['wheels'] = [M.pt(w['tl']) + [round((w['br'][0] - w['tl'][0]) * M.k, 2), round((w['br'][1] - w['tl'][1]) * M.k, 2)] for w in A['wheels']]
    d['wheel_box'] = M.sheet(['wheel-%d' % i for i in range(10)], 'tape-wheels')
    d['rollers'] = [{'c': M.pt(r['c']), 'r': round(r['r_cm'] * cm, 2)} for r in A['rollers']]
    d['tape_ends'] = [M.pt(p) for p in A['tape_ends']]
    META['deck'] = d


def post_cart():
    M = Machine('cart'); A = M.L['anchors']
    d = {'pt_per_cm': PT_CM['cart'], 'px_per_pt': PX_PT, 'samples': M.L['samples'], 'render_px_per_cm': M.pxcm}
    d['size'] = M.crop_full('cart')
    tl, br = A['cart_tl'], A['cart_br']
    d['outline'] = M.pt(tl) + [round((br[0] - tl[0]) * M.k, 2), round((br[1] - tl[1]) * M.k, 2)]
    lt, lb = A['label']['tl'], A['label']['br']
    d['label'] = M.pt(lt) + [round((lb[0] - lt[0]) * M.k, 2), round((lb[1] - lt[1]) * M.k, 2)]
    d['keys'] = {}
    for k in ('check', 'record', 'stop'):
        r = None
        for st in ('off', 'lit', 'down', 'litdown'): r = M.layer('cart-key-%s-%s' % (k, st), 'tape-cart-key-%s-%s' % (k, st))
        d['keys'][k] = r
    d['lamps'] = {k: M.layer('cart-lamp-%s' % k, 'tape-cart-lamp-%s' % k) for k in ('ready', 'cue1', 'cue2')}
    d['digits'] = {str(p): M.sheet(['cart-digit-%d-%d' % (p, i) for i in range(10)], 'tape-cart-digits-%d' % p) for p in (0, 2, 3)}
    d['colon'] = M.layer('cart-colon', 'tape-cart-colon')
    META['cart'] = d


def post_box():
    L = json.load(open(os.path.join(R, 'tape-layers-box.json')))
    out = {}
    for key in ('reel', 'cart'):
        a = L['anchors']['box_' + key]
        M = Machine.__new__(Machine)
        M.L = L; M.what = 'box'; M.pxcm = L['pxcm']; M.k = PT_CM['box'] / M.pxcm; M.hd = M.pxcm / PT_CM['box'] >= PX_PT * 1.6
        m = 0.6 * M.pxcm
        M.origin = (a['tl'][0] - m, a['tl'][1] - m); M.size_px = (a['br'][0] - a['tl'][0] + 2 * m, a['br'][1] - a['tl'][1] + 2 * m)
        d = {'size': M.crop_full('box-' + key)}
        d['outline'] = M.pt(a['tl']) + [round((a['br'][0] - a['tl'][0]) * M.k, 2), round((a['br'][1] - a['tl'][1]) * M.k, 2)]
        d['label'] = M.pt(a['label_tl']) + [round((a['label_br'][0] - a['label_tl'][0]) * M.k, 2), round((a['label_br'][1] - a['label_tl'][1]) * M.k, 2)]
        d['tilt_deg'] = a['tilt_deg']
        out[key] = d
    META['boxes'] = out


if os.path.exists(os.path.join(R, 'tape-layers-reel.json')): post_reel()
if os.path.exists(os.path.join(R, 'tape-layers-box.json')): post_box()
if os.path.exists(os.path.join(R, 'tape-layers-cart.json')): post_cart()
json.dump(META, open(out_json, 'w'), indent=1)
print('wrote', out_json)
