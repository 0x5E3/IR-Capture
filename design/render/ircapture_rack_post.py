# ircapture_rack_post.py: ircapture_rack_layers.py's renders into the kit (2026-11-11).
#
#   python3 design/render/ircapture_rack_post.py <renders dir> <Resources/SwellKit>
#
# Writes pictures/rack-<unit>.webp (the base), pictures/rack-<unit>-<layer>.webp (a live state: only the pixels that
# differ from the base, feathered, cropped tight), pictures/rack-cheek-v.webp and rack-cheek-h.webp (the boards), and
# irc-rack.json (points; origin each picture's top left). Lossless (webp_out). Units already in irc-rack.json and not in
# this run are kept.
import sys, os, json, glob
from PIL import Image, ImageFilter, ImageDraw
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


def layer(base, crop_path, box, whole=False):
    """The pixels of a live state that differ from the base: a mask from the difference, opened out and feathered, the
    layer cut to the mask's box. Returns (RGBA picture, box in the base's pixels) or None when nothing changed.
    whole: the crop entire (a part that replaces everything in its box, as a blank plate over a module: where the two
    happen to match the difference is under the threshold, and the module behind would show through)."""
    lyr = Image.open(crop_path).convert('RGBA')
    x0, y0 = box[0], box[1]
    b = np.asarray(base.crop((x0, y0, x0 + lyr.size[0], y0 + lyr.size[1])), dtype=np.float32)
    a = np.asarray(lyr, dtype=np.float32)
    if whole:
        m = np.ones(a.shape[:2], np.float32)
    else:
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


def rect(a):
    """(x0, y0, x1, y1) px to [x, y, w, h] pt."""
    x0, x1 = sorted((a[0], a[2])); y0, y1 = sorted((a[1], a[3]))
    return [pt(x0), pt(y0), pt(x1 - x0), pt(y1 - y0)]


def meters(L):
    """The meter bridge's own parts: each module's places (pt in the base picture), the eye's states as one sheet (the
    bore of module 0's eye, the same at every module), the needle alone."""
    M = L['meters']
    out = {'lamps': M['lamps'], 'vuTable': M['vuTable'], 'modules': []}
    for m in M['modules']:
        out['modules'].append({'gas': rect(m['gas']), 'gasN': m['gasN'], 'vuPivot': [pt(v) for v in m['vuPivot']],
                               'vuWindow': rect(m['vuWindow']), 'eye': [pt(v) for v in m['eye']], 'strip': rect(m['strip']),
                               'lamps': [[pt(v) for v in p] for p in m['lamps']]})
    # the eye: each state's crop cut to the bore (a circle, its edge feathered a pixel), twelve to a row
    E = L['eye']
    bx = E['box_px']; side = (bx[2] - bx[0], bx[3] - bx[1])
    cx, cy = E['center'][0] - bx[0], E['center'][1] - bx[1]
    rad = E['bore_cm'] * PXCM
    yy, xx = np.mgrid[0:side[1], 0:side[0]].astype(np.float32)
    circ = np.clip(rad + 0.5 - np.hypot(xx + 0.5 - cx, yy + 0.5 - cy), 0, 1)
    n = len(E['pictures']); per = 12; rows = -(-n // per)
    sheet = Image.new('RGBA', (per * side[0], rows * side[1]), (0, 0, 0, 0))
    for i, nm in enumerate(E['pictures']):
        im = Image.open(os.path.join(RD, nm + '.png')).convert('RGBA')
        a = np.asarray(im, dtype=np.float32).copy(); a[..., 3] *= circ
        sheet.paste(Image.fromarray(a.astype(np.uint8), 'RGBA'), ((i % per) * side[0], (i // per) * side[1]))
    save(sheet, 'rack-meters-eye')
    out['eye'] = {'picture': 'rack-meters-eye', 'perRow': per, 'states': E['states'], 'cell': [pt(side[0]), pt(side[1])],
                  'center': [pt(cx), pt(cy)], 'bore': pt(rad)}
    # the needle: its own alpha (rendered alone), cut tight; the pivot in that picture
    N = L['needle']
    im = Image.open(os.path.join(RD, N['picture'] + '.png')).convert('RGBA')
    bb = im.getchannel('A').point(lambda v: 255 if v > 2 else 0).getbbox()
    im = im.crop(bb); save(im, 'rack-meters-needle')
    px0, py0 = N['box_px'][0] + bb[0], N['box_px'][1] + bb[1]
    out['needle'] = {'picture': 'rack-meters-needle', 'size': [pt(im.size[0]), pt(im.size[1])],
                     'pivot': [pt(N['pivot'][0] - px0), pt(N['pivot'][1] - py0)]}
    print('  meters: %d modules, eye %d states, needle %s' % (len(out['modules']), n, im.size))
    return out


STAMP_PXPT = 6.0              # the stamps carry twice the kit's pixels: the broken ink is fine detail
STAMPS = {'excellent': ('EXCELLENT', (30, 122, 74)),        # green ink
          'check': ('CHECK NOTES', (52, 60, 138)),           # blue-violet ink
          'again': ('RECORD AGAIN', (172, 34, 28))}          # red ink


def stamps():
    """The verdict's rubber stamps (the proof's EXCELLENT): a double box and the word, the ink uneven and broken; the
    picture is the ink alone (colour, its density in alpha), upright: the app turns it a few degrees and multiplies it
    onto the sheet. 1.3 cm letters, the box fitted to the word."""
    from PIL import ImageDraw, ImageFont
    px = STAMP_PXPT * PT
    cm = lambda v: int(round(v * px))
    fs = ImageFont.truetype(os.path.join(KIT, 'fonts', 'BarlowSemiCondensed-700-normal.ttf'), cm(1.3))
    out = {}
    for k, (txt, col) in STAMPS.items():
        rng = np.random.default_rng(sum(map(ord, txt)))
        tr = 0.14 * fs.size
        wsum = sum(fs.getlength(c) for c in txt) + tr * (len(txt) - 1)
        sw, sh = int(wsum + cm(1.3)), cm(2.5)
        st = Image.new('L', (sw, sh), 0); sd = ImageDraw.Draw(st)
        sd.rectangle([cm(0.1), cm(0.1), sw - cm(0.1), sh - cm(0.1)], outline=255, width=cm(0.13))
        sd.rectangle([cm(0.33), cm(0.33), sw - cm(0.33), sh - cm(0.33)], outline=255, width=max(1, cm(0.04)))
        bb = fs.getbbox('H'); x = (sw - wsum) / 2
        for c in txt:
            sd.text((x, sh / 2 - (bb[1] + bb[3]) / 2), c, font=fs, fill=255); x += fs.getlength(c) + tr
        n1 = np.asarray(Image.fromarray((rng.random((sh, sw)) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(2.2 * px / 110)), np.float32) / 255
        n2 = np.asarray(Image.fromarray((rng.random((sh // 6 + 1, sw // 6 + 1)) * 255).astype(np.uint8)).resize((sw, sh), Image.BICUBIC), np.float32) / 255
        sa = np.asarray(st, np.float32) / 255 * np.clip((n1 - 0.36) * 6, 0, 1) * (0.55 + 0.45 * n2)
        rgba = np.zeros((sh, sw, 4), np.uint8); rgba[..., :3] = col; rgba[..., 3] = (sa * 235).astype(np.uint8)
        name = 'rack-stamp-' + k
        save(Image.fromarray(rgba, 'RGBA'), name)
        out[k] = {'picture': name, 'size': [round(sw / STAMP_PXPT, 3), round(sh / STAMP_PXPT, 3)]}
    return {'pxPerPoint': STAMP_PXPT, 'stamps': out}


def results(L):
    """The results unit's own parts: the sheet's rectangle and the keys' (pt in the base picture), the form's layout
    (sheet cm, as ircapture_rack_layers.FORM), the stamps."""
    Rz = L['results']
    out = {'sheet': rect(Rz['sheet']), 'form': Rz['form'], 'keys': [{'id': k['id'], 'rect': rect(k['rect'])} for k in Rz['keys']]}
    out.update(stamps())
    print('  results: sheet %s, %d keys, %d stamps' % (out['sheet'], len(out['keys']), len(out['stamps'])))
    return out


def centroid(a):
    al = a[..., 3].astype(np.float64); ys, xs = np.mgrid[0:al.shape[0], 0:al.shape[1]]
    t = al.sum()
    return (float((xs * al).sum() / t), float((ys * al).sum() / t)) if t > 0 else (al.shape[1] / 2, al.shape[0] / 2)


def rim_mend(im, c, rpx, band_cm=1.0, drop=24.0, win=151):
    """(11-12) The flanges' rolled lips render with black specks (the scuff bump on that tight curve: up to a third of
    the lip's pixels near black at 42 px/cm, nothing like it on the flat face). Each ring of the lip, one pixel wide, is
    walked round by angle; a pixel more than `drop` darker than the median of its `win` neighbours along the ring takes
    that median's colour (its alpha is kept), twice over. Only the outer band_cm; the boss and the face are not touched."""
    from scipy.ndimage import median_filter
    a = np.asarray(im).astype(np.float32).copy()
    h, w = a.shape[:2]; y, x = np.mgrid[:h, :w]
    r = np.hypot(x - c[0], y - c[1]); th = np.arctan2(y - c[1], x - c[0])
    band = (r >= rpx - band_cm * PXCM) & (a[..., 3] > 0)
    rb = np.floor(r).astype(int); n = 0
    for k in np.unique(rb[band]):
        sel = np.nonzero(band & (rb == k))
        if len(sel[0]) < win: continue
        o = np.argsort(th[sel]); yy, xx = sel[0][o], sel[1][o]
        for _ in range(2):                                   # twice: a long run of specks shifts the first median
            px_ = a[yy, xx, :3]
            med = np.stack([median_filter(px_[:, i], size=min(win, len(yy) // 2 * 2 - 1), mode='wrap') for i in range(3)], -1)
            bad = px_.mean(-1) < med.mean(-1) - drop
            a[yy[bad], xx[bad], :3] = med[bad]; n += int(bad.sum())
    print('  rim mend: %d px' % n)
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), 'RGBA')


def deck(L):
    """The reel deck's own parts. Its reel pictures were rendered alone (their own alpha), so they are saved whole, not
    as a difference from the base: rear, rearshadow, pack, front, frontshadow at the reel's box; the 24 prong frames as one
    sheet; the counter's ten figures as one sheet, each cut to its drum's window. The shadows' centres (for turning them)
    from the solid flanges' shadows."""
    Dk = L['deck']; S = L['solo']
    cm = PT                                                  # pt a cm
    out = {'reels': {}, 'keys': [{'id': k['id'], 'rect': rect(k['rect'])} for k in Dk['keys']]}
    for key, r in Dk['reels'].items():
        bx = r['box']
        e = {'box': [pt(bx[0]), pt(bx[1]), pt(bx[2] - bx[0]), pt(bx[3] - bx[1])], 'c': [pt(v) for v in r['c']],
             'r': round(r['r_cm'] * cm, 3), 'hub': round(r['hub_cm'] * cm, 3), 'packFull': round(r['full_cm'] * cm, 3),
             'win': {'a0': r['win']['a0'], 'span': r['win']['span'], 'r0': round(r['win']['r0'] * cm, 3), 'r1': round(r['win']['r1'] * cm, 3)},
             'roller': [pt(v) for v in r['roller']], 'rollerR': round(r['roller_r_cm'] * cm, 3)}
        for lay_ in ('rear', 'rearshadow', 'pack', 'front', 'frontshadow'):
            nm = 'rack-deck-%s-%s' % (key, lay_)
            im = Image.open(os.path.join(RD, nm + '.png')).convert('RGBA')
            if lay_ in ('rear', 'front'):
                im = rim_mend(im, ((r['c'][0] - bx[0]), (r['c'][1] - bx[1])), r['r_cm'] * PXCM)
            save(im, nm)
            e[lay_] = nm
        for lay_ in ('rear', 'front'):
            a = np.asarray(Image.open(os.path.join(RD, 'rack-deck-%s-%sshadow-solid.png' % (key, lay_))).convert('RGBA'))
            cx, cy = centroid(a)
            e[lay_ + 'ShadowC'] = [pt(bx[0] + cx), pt(bx[1] + cy)]
        pb = r['prong_box']; n = r['frames']
        frames = [Image.open(os.path.join(RD, 'rack-deck-%s-prong-%02d.png' % (key, i))).convert('RGBA') for i in range(n)]
        sh = Image.new('RGBA', (frames[0].size[0] * n, frames[0].size[1]), (0, 0, 0, 0))
        for i, f in enumerate(frames): sh.paste(f, (i * f.size[0], 0))
        save(sh, 'rack-deck-%s-prongs' % key)
        e['prongs'] = {'picture': 'rack-deck-%s-prongs' % key, 'frames': n, 'span': r['span'],
                       'box': [pt(pb[0]), pt(pb[1]), pt(pb[2] - pb[0]), pt(pb[3] - pb[1])]}
        out['reels'][key] = e
    if 'hood' in Dk:
        # (11-12) the head hood stands in front of the reels: its pixels lifted off the base (the reels are not in the
        # base, so they are the hood's own) inside its rounded outline, drawn over the reels by the app
        q = Dk['hood']['rect']; x0, x1 = sorted((q[0], q[2])); y0, y1 = sorted((q[1], q[3]))
        bx0, by0, bx1, by1 = int(x0) - 2, int(y0) - 2, int(x1) + 3, int(y1) + 3
        base = Image.open(os.path.join(RD, L['picture'] + '.png')).convert('RGBA').crop((bx0, by0, bx1, by1))
        ss = 4; rr = Dk['hood']['r_cm'] * PXCM
        m = Image.new('L', (base.size[0] * ss, base.size[1] * ss), 0)
        ImageDraw.Draw(m).rounded_rectangle([(x0 - bx0) * ss, (y0 - by0) * ss, (x1 - bx0) * ss, (y1 - by0) * ss], rr * ss, fill=255)
        m = m.resize(base.size, Image.LANCZOS)
        a = np.asarray(base).copy(); a[..., 3] = (a[..., 3].astype(np.float32) * np.asarray(m, np.float32) / 255).astype(np.uint8)
        save(Image.fromarray(a, 'RGBA'), 'rack-deck-hood')
        out['hood'] = {'picture': 'rack-deck-hood', 'rect': rect((bx0, by0, bx1, by1))}
    W = Dk['wheels']; c0 = W['crop']; r0 = W['rects'][0]
    x0, y0 = int(round(r0[0] - c0[0])), int(round(r0[1] - c0[1])); x1, y1 = int(round(r0[2] - c0[0])), int(round(r0[3] - c0[1]))
    figs = [Image.open(os.path.join(RD, 'rack-deck-wheel-%d.png' % d)).convert('RGBA').crop((x0, y0, x1, y1)) for d in range(10)]
    sh = Image.new('RGBA', ((x1 - x0) * 10, y1 - y0))
    for d, f in enumerate(figs): sh.paste(f, (d * (x1 - x0), 0))
    save(sh, 'rack-deck-wheels')
    out['wheels'] = {'picture': 'rack-deck-wheels', 'rects': [rect(q) for q in W['rects']]}
    print('  deck: 2 reels, %d keys, counter %s' % (len(out['keys']), figs[0].size))
    return out


def cart(L):
    C = L['cart']
    out = {'label': rect(C['label']), 'keys': [{'id': k['id'], 'rect': rect(k['rect'])} for k in C['keys']],
           'segs': [[[pt(v) for v in p_] for p_ in sg] for sg in C['segs']], 'cells': C['cells']}
    print('  cart: label %s, %d keys, %d cells' % (out['label'], len(out['keys']), len(out['cells'])))
    return out


for key, L in lay.get('units', {}).items():
    base = Image.open(os.path.join(RD, L['picture'] + '.png')).convert('RGBA')
    save(base, L['picture'])
    tl, br = L['tl'], L['br']
    u = {'picture': L['picture'], 'u': L['u'], 'size': [pt(base.size[0]), pt(base.size[1])],
         'panel': [pt(tl[0]), pt(tl[1]), pt(br[0] - tl[0]), pt(br[1] - tl[1])], 'layers': {}}
    for lk, LL in L.get('layers', {}).items():
        r = layer(base, os.path.join(RD, LL['picture'] + '.png'), LL['box_px'], whole=key in ('meters', 'nammeters') and lk.startswith('b'))
        if r is None:
            print('  %s %s: no change from the base' % (key, lk)); continue
        im, (x, y, w, h) = r
        save(im, LL['picture'])
        u['layers'][lk] = {'picture': LL['picture'], 'rect': [pt(x), pt(y), pt(w), pt(h)]}
    if 'lamp_x_cm' in L: u['lampXcm'] = L['lamp_x_cm']
    if 'meters' in L: u['meters'] = meters(L)
    if 'results' in L: u['results'] = results(L)
    if 'patch' in L:
        Pa = L['patch']
        u['patch'] = {'n': Pa['n'], 'banks': Pa['banks'], 'toggles': [[pt(v) for v in p] for p in Pa['toggles']],
                      'rows': {k: pt(v) for k, v in Pa['rows'].items()}, 'column': pt(Pa['column'][1] - Pa['column'][0])}
    if 'nammeters' in L:
        Nm = L['nammeters']
        u['nammeters'] = {'lamps': Nm['lamps'], 'db0': Nm['db0'], 'dbStep': Nm['dbStep'], 'colours': Nm['colours'],
                          'modules': [{'bars': [rect(b) for b in m['bars']],
                                       'segs': [[[pt(v) for v in p_] for p_ in sg] for sg in m['segs']],
                                       'cells': [[c[k] for k in 'abcdefgp'] for c in m['cells']],
                                       'leds': [[pt(v) for v in p_] for p_ in m['leds']], 'strip': rect(m['strip'])}
                                      for m in Nm['modules']]}
        print('  nammeters: %d modules' % len(u['nammeters']['modules']))
    if 'deck' in L: u['deck'] = deck(L)
    if 'cart' in L: u['cart'] = cart(L)
    if 'preflight' in L: u['preflight'] = {'sheet': rect(L['preflight']['sheet']), 'form': L['preflight']['form']}
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
