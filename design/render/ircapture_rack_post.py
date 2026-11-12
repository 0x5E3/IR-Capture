# ircapture_rack_post.py: ircapture_rack_layers.py's renders into the kit (2026-11-11).
#
#   python3 design/render/ircapture_rack_post.py <renders dir> <Resources/SwellKit>
#
# Writes pictures/rack-<unit>.webp (the base), pictures/rack-<unit>-<layer>.webp (a live state: only the pixels that
# differ from the base, feathered, cropped tight), pictures/rack-cheek-v.webp and rack-cheek-h.webp (the boards), and
# irc-rack.json (points; origin each picture's top left). Lossless (webp_out). Units already in irc-rack.json and not in
# this run are kept.
import sys, os, json, glob
from PIL import Image, ImageFilter
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import webp_out  # noqa: F401  (every WEBP lossless)

RD, KIT = sys.argv[1], sys.argv[2]
PIC = os.path.join(KIT, 'pictures')
OUTJ = os.path.join(KIT, 'irc-rack.json')
U = 4.445
CHEEK_KEEP_CM = 150.0         # the side boards go dark past about 150 cm from their top (render_long's last segment)

lay = {}
for f in sorted(glob.glob(os.path.join(RD, 'rack-layers-*.json'))):
    d = json.load(open(f))
    for k in ('pxcm', 'pt_per_cm'): lay[k] = d[k]
    lay.setdefault('units', {}).update(d.get('units', {}))
    if 'cheeks' in d: lay['cheeks'] = d['cheeks']
PXCM, PT = lay['pxcm'], lay['pt_per_cm']
PXPT = PXCM / PT

old = json.load(open(OUTJ)) if os.path.exists(OUTJ) else {}
if old and abs(old.get('pxPerPoint', PXPT) - PXPT) > 1e-6:
    sys.exit('irc-rack.json is at %.3f px a point, these renders at %.3f: render every unit at one scale' % (old['pxPerPoint'], PXPT))
J = {'pxPerPoint': PXPT, 'ptPerCm': PT, 'uPt': round(U * PT, 4), 'units': dict(old.get('units', {})), 'cheeks': old.get('cheeks')}


def pt(v): return round(v / PXPT, 3)


def save(im, name):
    im.save(os.path.join(PIC, name + '.webp'))


def layer(base, crop_path, box):
    """The pixels of a live state that differ from the base: a mask from the difference, opened out and feathered, the
    layer cut to the mask's box. Returns (RGBA picture, box in the base's pixels) or None when nothing changed."""
    lyr = Image.open(crop_path).convert('RGBA')
    x0, y0 = box[0], box[1]
    b = np.asarray(base.crop((x0, y0, x0 + lyr.size[0], y0 + lyr.size[1])), dtype=np.float32)
    a = np.asarray(lyr, dtype=np.float32)
    d = np.abs(a[..., :3] - b[..., :3]).max(axis=2)
    m = np.clip((d - 3.0) / 9.0, 0, 1)                    # under 3 of 255: render noise; full from 12
    mi = Image.fromarray((m * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(7)).filter(ImageFilter.GaussianBlur(2.5))
    m = np.asarray(mi, dtype=np.float32) / 255.0
    # the crop's own edge: the denoiser saw only the crop, so its outer rows may differ from the base; fade them out
    e = 4
    ramp = np.ones_like(m)
    for k in range(e):
        f = (k + 1) / (e + 1)
        ramp[k, :] = np.minimum(ramp[k, :], f); ramp[-1 - k, :] = np.minimum(ramp[-1 - k, :], f)
        ramp[:, k] = np.minimum(ramp[:, k], f); ramp[:, -1 - k] = np.minimum(ramp[:, -1 - k], f)
    m = m * ramp
    ys, xs = np.nonzero(m > 1.0 / 255)
    if len(xs) == 0: return None
    bx0, by0, bx1, by1 = xs.min(), ys.min(), xs.max() + 1, ys.max() + 1
    out = a.copy(); out[..., 3] = a[..., 3] * m
    im = Image.fromarray(out.astype(np.uint8), 'RGBA').crop((bx0, by0, bx1, by1))
    return im, (x0 + bx0, y0 + by0, bx1 - bx0, by1 - by0)


for key, L in lay.get('units', {}).items():
    base = Image.open(os.path.join(RD, L['picture'] + '.png')).convert('RGBA')
    save(base, L['picture'])
    tl, br = L['tl'], L['br']
    u = {'picture': L['picture'], 'u': L['u'], 'size': [pt(base.size[0]), pt(base.size[1])],
         'panel': [pt(tl[0]), pt(tl[1]), pt(br[0] - tl[0]), pt(br[1] - tl[1])], 'layers': {}}
    for lk, LL in L.get('layers', {}).items():
        r = layer(base, os.path.join(RD, LL['picture'] + '.png'), LL['box_px'])
        if r is None:
            print('  %s %s: no change from the base' % (key, lk)); continue
        im, (x, y, w, h) = r
        save(im, LL['picture'])
        u['layers'][lk] = {'picture': LL['picture'], 'rect': [pt(x), pt(y), pt(w), pt(h)]}
    if 'lamp_x_cm' in L: u['lampXcm'] = L['lamp_x_cm']
    J['units'][key] = u
    print(key, base.size, len(u['layers']), 'layers')

if lay.get('cheeks'):
    C = lay['cheeks']
    v = Image.open(os.path.join(RD, 'trim-v.png')).convert('RGBA')
    keep = min(v.size[1], int(round(CHEEK_KEEP_CM * PXCM)))
    v = v.crop((0, 0, v.size[0], keep)); save(v, 'rack-cheek-v')
    h = Image.open(os.path.join(RD, 'trim-h.png')).convert('RGBA'); save(h, 'rack-cheek-h')
    J['cheeks'] = {'v': {'picture': 'rack-cheek-v', 'size': [pt(v.size[0]), pt(v.size[1])], 'boardLeft': pt(C['trim-v']['px_left']),
                         'boardWidth': pt(C['trim-v']['px_right'] - C['trim-v']['px_left'])},
                   'h': {'picture': 'rack-cheek-h', 'size': [pt(h.size[0]), pt(h.size[1])], 'boardTop': pt(C['trim-h']['row_top']),
                         'boardBottom': pt(C['trim-h']['row_bot'])}}
    print('cheeks', v.size, h.size)

json.dump(J, open(OUTJ, 'w'), indent=1)
print('wrote', OUTJ)
