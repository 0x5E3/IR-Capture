# ircapture_lettering_post.py: ircapture_kit.py's lettering renders (11-11) made into IR Capture's pictures.
#   python3 design/render/ircapture_lettering_post.py <renders dir> Resources/SwellKit
# Needs only numpy and Pillow (and webp_out.py beside it: every WebP lossless).
#
# Reads the renders' irc-render-<piece>.json and writes, each at 1x and @2x (premultiplied Lanczos, ircapture_kit_post's
# resample), the layout in points beside pictures/:
#   legend-<state>-<id>.png  -> irc-legend-<state>-<id>.webp, irc-legends.json   printed keys, drawn at 12 pt a cm
#   scribble-<v>.png         -> irc-scribble-<v>.webp, irc-scribble.json         masking-tape strips, 15.8 pt a cm
#   gas-line.png, gas-dig.png -> irc-gas-line.webp, irc-gas-dig.webp, irc-gas.json   the VFD status line (14 pt a cm),
#                                                                                the dBFS gas digits (14 pt a cm)
# A piece missing from the renders keeps whatever the kit has (its json entry is merged, not replaced).
import sys, os, json, glob
import numpy as np
from PIL import Image
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, '/home/claude/desktop-bench/design/render')
import webp_out          # noqa: F401  (every WebP lossless and exact)
import ircapture_legends as LG

R, O = sys.argv[1], sys.argv[2]
PIC = os.path.join(O, 'pictures')
os.makedirs(PIC, exist_ok=True)

lay = {}
for f in glob.glob(os.path.join(R, 'irc-render-*.json')):
    j = json.load(open(f))
    for k, v in j['out'].items(): lay[k] = dict(v, pxcm=j['pxcm'], samples=j['samples'])


def premul(im):
    a = np.asarray(im.convert('RGBA')).astype(np.float64) / 255.0
    a[..., :3] *= a[..., 3:4]
    return a


_SRC = {}


def resample(name, box, size):
    if name not in _SRC: _SRC[name] = premul(Image.open(os.path.join(R, name + '.png')))
    a = _SRC[name]
    ch = [np.asarray(Image.fromarray(a[..., i].astype(np.float32), 'F').resize(size, Image.LANCZOS, box=tuple(float(v) for v in box)))
          for i in range(4)]
    out = np.clip(np.stack(ch, -1).astype(np.float64), 0, 1)
    out[..., :3] = np.minimum(out[..., :3], out[..., 3:4])
    return out


def save(a, name):
    out = a.copy(); al = out[..., 3:4]
    out[..., :3] = np.where(al > 1e-6, out[..., :3] / np.maximum(al, 1e-6), 0.0)
    im = Image.fromarray(np.clip(out * 255 + 0.5, 0, 255).astype(np.uint8), 'RGBA')
    p = os.path.join(PIC, name + '.webp')
    im.save(p, 'WEBP', quality=90, method=6)          # lossless (webp_out)
    return im.size


def r2(x): return round(float(x), 2)


def piece(key, out_name, pt_cm, px_pt, margin_cm=0.0):
    """Crops the render to its object (tl..br, cm in size) plus margin_cm round it, writes out_name at px_pt pixels a
    point (1x) and twice that (@2x); returns the picture's size in points and a function taking render px to points."""
    L = lay[key]; w, h = L['cm']; (x0, y0), (x1, y1) = L['tl'], L['br']
    sx, sy = (x1 - x0) / w, (y1 - y0) / h                    # render px a true cm (y: the camera's tilt undone)
    bx0, by0 = x0 - margin_cm * sx, y0 - margin_cm * sy
    W_pt, H_pt = (w + 2 * margin_cm) * pt_cm, (h + 2 * margin_cm) * pt_cm
    for k in (1, 2):
        size = (int(round(W_pt * px_pt * k)), int(round(H_pt * px_pt * k)))
        a = resample(key, (bx0, by0, x1 + margin_cm * sx, y1 + margin_cm * sy), size)
        save(a, out_name + ('' if k == 1 else '@2x'))
    to_pt = lambda p: (r2((p[0] - bx0) / sx * pt_cm), r2((p[1] - by0) / sy * pt_cm))
    return [r2(W_pt), r2(H_pt)], to_pt, margin_cm * pt_cm


def merge(path, new, key):
    doc = json.load(open(path)) if os.path.exists(path) else {}
    for k, v in new.items():
        if k == key and isinstance(v, dict): doc.setdefault(k, {}).update(v)
        else: doc[k] = v
    json.dump(doc, open(path, 'w'), indent=1)
    print('wrote', path, len(doc.get(key, {})), key)


# --- printed keys --------------------------------------------------------------------------------------------------
KEY_PX_PT = 20.0 / LG.PT_PER_CM          # 1x: 20 px a cm (@2x 40, the container's render density)
KEY_M = 0.12                             # cm round the bezel: its shadow
keys = {}
for lid, (text, size, names) in LG.LEGENDS.items():
    files, pt, cap = {}, None, None
    for st in ('off', 'lit', 'down', 'litdown'):
        k = 'legend-%s-%s' % (st, lid)
        if k not in lay: break
        pt, to_pt, out_pt = piece(k, 'irc-legend-%s-%s' % (st, lid), LG.PT_PER_CM, KEY_PX_PT, KEY_M)
        files[st] = 'irc-legend-%s-%s' % (st, lid)
        if st == 'off':
            (cx0, cy0), (cx1, cy1) = to_pt(lay[k]['cap_tl']), to_pt(lay[k]['cap_br'])
            cap = [cx0, cy0, r2(cx1 - cx0), r2(cy1 - cy0)]
    if len(files) == 4:
        keys[lid] = {'legend': text, 'size': size, 'names': names, 'variant': LG.variant(names[0]),
                     'pt': pt, 'outset_pt': r2(KEY_M * LG.PT_PER_CM), 'cap': cap, 'files': files}
if keys:
    merge(os.path.join(O, 'irc-legends.json'),
          {'about': 'Printed keys (design/render/ircapture_legends.py, ircapture_kit.py legend-<id>): each picture is the key '
                    'and its bezel plus outset_pt of shadow on every side, drawn at pt (points, outset included). Looked '
                    'up by size ("std", or "big" for KeyButtonStyle(big: true)) and the key name, lowercased, a leading '
                    '"‹ " and trailing "…" or "." dropped. cap: the cap in the picture (x, y, w, h).',
           'pt_per_cm': LG.PT_PER_CM, 'px_per_pt': r2(KEY_PX_PT), 'keys': keys}, 'keys')

# --- scribble strips -----------------------------------------------------------------------------------------------
SCRIB_PT, SCRIB_PX_PT, SCRIB_M = 15.8, 1.5, 0.35
strips = {}
for v in 'abcd':
    k = 'scribble-' + v
    if k not in lay: continue
    pt, to_pt, out_pt = piece(k, 'irc-scribble-' + v, SCRIB_PT, SCRIB_PX_PT, SCRIB_M)
    wl, wr = to_pt(lay[k]['write_l']), to_pt(lay[k]['write_r'])
    w, h = lay[k]['cm']
    strips[v] = {'file': 'irc-scribble-' + v, 'pt': pt, 'tape': [r2(out_pt), r2(out_pt), r2(w * SCRIB_PT), r2(h * SCRIB_PT)],
                 'write': [wl[0], wr[0]], 'mid': wl[1]}
if strips:
    merge(os.path.join(O, 'irc-scribble.json'),
          {'about': 'Masking-tape scribble strips (ircapture_kit.py scribble-<v>): tape is the strip itself in the picture '
                    '(x, y, w, h, points; the rest is its shadow and margin); write is where the name goes (x from, x to) '
                    'and mid the strip\'s middle line.', 'pt_per_cm': SCRIB_PT, 'px_per_pt': SCRIB_PX_PT, 'strips': strips}, 'strips')

# --- the displays --------------------------------------------------------------------------------------------------
GAS = {'line': (14.0, 2.0), 'dig': (14.0, 2.0)}
disp = {}
for kind, (pt_cm, px_pt) in GAS.items():
    k = 'gas-' + kind
    if k not in lay: continue
    L = lay[k]
    pt, to_pt, out_pt = piece(k, 'irc-gas-' + kind, pt_cm, px_pt, 0.19)     # 0.19 cm: nearly all the render's 0.2 cm margin, its shadow
    (cx0, cy0), (cx1, cy1) = to_pt(L['cells_tl']), to_pt(L['cells_br'])
    bw, bh = L['bezel_cm']; pw, ph = L['piece_cm']
    e = {'file': 'irc-gas-' + kind, 'pt': pt, 'pt_per_cm': pt_cm, 'px_per_pt': px_pt,
         'bezel': [r2((pw - bw) / 2 * pt_cm + out_pt), r2((ph - bh) / 2 * pt_cm + out_pt), r2(bw * pt_cm), r2(bh * pt_cm)],
         'cells': [cx0, cy0, r2(cx1 - cx0), r2(cy1 - cy0)], 'disp': L['disp'], 'n': L['n'], 'look': L.get('look')}
    if L['disp'] == 'matrix': e['mtx'] = L['mtx']
    else: e.update(pitch=L.get('pitch') or 1.3, slant=L.get('slant') or 8.0)
    disp[kind] = e
if disp:
    merge(os.path.join(O, 'irc-gas.json'),
          {'about': 'The displays (ircapture_kit.py gas-line, gas-dig), rendered dark: the app lights the dots and segments '
                    'over cells (x, y, w, h, points) with the render\'s geometry (gas_disp.py; views/gasdisp.js). bezel: '
                    'the bezel in the picture, the layout box.', 'displays': disp}, 'displays')
