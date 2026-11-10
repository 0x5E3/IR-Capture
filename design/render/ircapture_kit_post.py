# ircapture_kit_post.py: ircapture_kit.py's renders made into IR Capture's pictures (helper for IR Capture, 2026-11-03).
#   python3 design/render/ircapture_kit_post.py <renders dir> Resources/SwellKit
# On the iMac this sits beside the bench's scripts (desktop-bench/design/render/); it needs only numpy and Pillow.
#
# Every piece is resampled (area filter, on premultiplied alpha so shadows and edges keep no fringe) to 24 px a cm (1x)
# and 48 (@2x), set to its true shape (the camera's 10 degrees shortens what faces it by 1.5 %: y is stretched by
# 1 / cos 10), and written as pictures/<name>.webp and <name>@2x.webp (lossless since 11-10: webp_out). IR Capture draws these at
# 10 pt a cm, so 1x is 2.4 px a pt. The layout (sizes, cap insets, where the faces and edges are) goes to
# irc-pieces.json beside pictures/.
#
#   rkit-panel-fine, rkit-panel-nam   as toolkit_post.py's panel: cropped to the outline plus 0.2 cm (its shadow), the
#           middle (inside 1.5 + 0.2 cm) made a repeating tile both ways (the last 1.6 cm cross-faded into the mirror of
#           the first), 394 x 394 at 1x like rkit-panel.webp
#   irc-plank          a horizontal strip, exactly one period (60 cm, 600 pt) of the plank: its oak maps repeat every
#           60 cm, and the last 2.5 cm are cross-faded into the 2.5 cm rendered before the period's start (the light
#           and the fine wear noise differ a little along the length), so laid end to end it has no seam
#   irc-box-bronze, irc-box-oxblood   a 3-slice along x: the left end whole (3.3 cm: margin, rounded corner, foot),
#           the middle repeating (mirror cross-fade 1.6 cm, as toolkit_post), the right end whole with its shadow
#   irc-trim-h, irc-trim-v            strips, one period (30 cm) each, made periodic as the plank
import sys, os, json, glob, math
import numpy as np
from PIL import Image
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, '/home/claude/desktop-bench/design/render')
import webp_out          # (11-10) every WebP lossless and exact (the bench's rule since 11-06); POST_LOSSY=1 the old

R = sys.argv[1]
O = sys.argv[2]
PIC = os.path.join(O, 'pictures')
OUTS = (24.0, 48.0)                   # px a cm: 1x, @2x
PT_CM = 10.0                          # IR Capture's points a cm
lay = {}
for f in glob.glob(os.path.join(R, 'irc-render-*.json')):
    j = json.load(open(f)); lay.update({k: dict(v, pxcm=j['pxcm'], elev=j['elev'], samples=j['samples']) for k, v in j['out'].items()})
META = {}


def premul(im):
    a = np.asarray(im.convert('RGBA')).astype(np.float64) / 255.0
    a[..., :3] *= a[..., 3:4]
    return a


def unpremul(a, rgb_only=False):
    out = a.copy(); al = out[..., 3:4]
    out[..., :3] = np.where(al > 1e-6, out[..., :3] / np.maximum(al, 1e-6), 0.0)
    im = Image.fromarray(np.clip(out * 255 + 0.5, 0, 255).astype(np.uint8), 'RGBA')
    return im.convert('RGB') if rgb_only else im


_SRC = {}


def resample(name, box, size):
    """The render's region box (x0, y0, x1, y1 in its px, fractional) to size px: Lanczos (antialiased when shrinking)
    on premultiplied float channels, so edges and soft shadows keep no fringe and no 8-bit banding."""
    if name not in _SRC: _SRC[name] = premul(Image.open(os.path.join(R, name + '.png')))
    a = _SRC[name]
    ch = [np.asarray(Image.fromarray(a[..., i].astype(np.float32), 'F').resize(size, Image.LANCZOS, box=tuple(float(v) for v in box)))
          for i in range(4)]
    out = np.clip(np.stack(ch, -1).astype(np.float64), 0, 1)
    out[..., :3] = np.minimum(out[..., :3], out[..., 3:4])   # premultiplied colour never above its alpha (Lanczos ringing)
    return out


def smooth(o):
    w = (np.arange(o) + 0.5) / o; return w * w * (3 - 2 * w)


def tile_mirror(a, S0, S1, axis, o):
    """toolkit_post.tile()'s cross-fade along one axis: the last o of [S0, S1) faded into the mirror of the first o."""
    a = np.moveaxis(a, axis, 0).copy(); w = smooth(o)
    for i in range(o):
        c = S1 - o + i; a[c] = (1 - w[i]) * a[c] + w[i] * a[S0 + o - 1 - i]
    return np.moveaxis(a, 0, axis)


def tile_wrap(a, S0, S1, axis, o):
    """For a texture already periodic over [S0, S1): the last o faded into the o rendered just before S0, so the period's
    end runs on into its start."""
    a = np.moveaxis(a, axis, 0).copy(); w = smooth(o)
    for i in range(o):
        c = S1 - o + i; a[c] = (1 - w[i]) * a[c] + w[i] * a[S0 - o + i]
    return np.moveaxis(a, 0, axis)


def detrend2(a, S0, S1, T0, T1, deg=2):
    """The studio's light falls off across a 16 cm panel (brighter toward the key, up left); repeated as a tile that
    gradient reads as a grid (11-03 contact sheet). A low-order 2D polynomial fitted to the middle [T0, T1) x [S0, S1)
    (rows x cols), each premultiplied channel, is taken out (less its mean), evaluated at coordinates clamped to the
    middle so the corners and edges get the boundary's correction and nothing jumps."""
    H, W = a.shape[:2]
    ys, xs = np.mgrid[T0:T1:4, S0:S1:4]
    u = (xs - S0) / (S1 - S0) * 2 - 1; v = (ys - T0) / (T1 - T0) * 2 - 1
    terms = lambda u, v: [np.ones_like(u), u, v] + ([u * u, u * v, v * v] if deg >= 2 else [])
    A = np.stack([t.ravel() for t in terms(u, v)], 1)
    yy, xx = np.mgrid[0:H, 0:W]
    U = (np.clip(xx, S0, S1 - 1) - S0) / (S1 - S0) * 2 - 1; V = (np.clip(yy, T0, T1 - 1) - T0) / (T1 - T0) * 2 - 1
    B = np.stack(terms(U, V), -1)
    out = a.copy()
    for c in range(3):
        coef, *_ = np.linalg.lstsq(A, a[T0:T1:4, S0:S1:4, c].ravel(), rcond=None)
        fit = B @ coef
        out[..., c] = a[..., c] - (fit - coef[0]) * a[..., 3]
    return np.clip(out, 0, 1)


def detrend_rows(a, S0, S1, axis=1, smooth_px=6, nch=4):
    """For a strip repeated along one axis (1: along x): each line's straight-line trend along the repeat over [S0, S1)
    taken out (premultiplied colour, and alpha for a shadow's falloff, the slopes smoothed over neighbouring lines so no streaks), evaluated at
    positions clamped to [S0, S1)."""
    if axis == 0:
        return np.swapaxes(detrend_rows(np.swapaxes(a, 0, 1), S0, S1, 1, smooth_px, nch), 0, 1)
    a = a.copy(); n = a.shape[1]; x = np.arange(S0, S1, dtype=np.float64); xc = x.mean()
    seg = a[:, S0:S1, :nch]
    slope = ((seg - seg.mean(1, keepdims=True)) * (x - xc)[None, :, None]).sum(1) / ((x - xc) ** 2).sum()
    k = np.ones(smooth_px) / smooth_px
    slope = np.stack([np.convolve(np.pad(slope[:, c], smooth_px, mode='edge'), k, 'same')[smooth_px:-smooth_px] for c in range(nch)], 1)
    xx = np.clip(np.arange(n), S0, S1 - 1) - xc
    a[..., :nch] = a[..., :nch] - slope[:, None, :] * xx[None, :, None]
    a = np.clip(a, 0, 1); a[..., :3] = np.minimum(a[..., :3], a[..., 3:4])
    return a


def feather(a, sides, n):
    """The picture's outer edges on the given sides ('t', 'b', 'l', 'r') faded to zero alpha over n px (premultiplied: the
    colour with it), so a shadow cut by the frame ends softly instead of at a hard line."""
    a = a.copy(); H, W = a.shape[:2]; w = smooth(n)
    for sd in sides:
        for i in range(min(n, H if sd in 'tb' else W)):
            if sd == 't': a[i] *= w[i]
            elif sd == 'b': a[H - 1 - i] *= w[i]
            elif sd == 'l': a[:, i] *= w[i]
            else: a[:, W - 1 - i] *= w[i]
    return a


def save(a, name, rgb=False):
    os.makedirs(PIC, exist_ok=True)
    im = unpremul(a, rgb)
    p = os.path.join(PIC, name + '.webp')
    im.save(p, 'WEBP', quality=90, method=6)          # lossless (webp_out): quality is the encoder's effort
    print(name + '.webp', im.size, os.path.getsize(p), flush=True)
    return im.size


def alpha_extent(name, axis, lo, hi, thresh=0.6):
    """The last index along axis (rows 0, cols 1) of the render where the alpha's mean over [lo, hi) of the other axis
    passes thresh (0-255)."""
    a = np.asarray(Image.open(os.path.join(R, name + '.png')).convert('RGBA'))[..., 3].astype(np.float64)
    m = a[:, lo:hi].mean(1) if axis == 0 else a[lo:hi, :].mean(0)
    idx = np.where(m > thresh)[0]
    return int(idx[-1]) + 1 if len(idx) else len(m)


def r2(x): return round(float(x), 2)


# ---------------------------------------------------------------------------------------------------------------------
def panel(key, out):
    if key not in lay: return
    L = lay[key]; px = L['pxcm']; w, h = L['cm']; ce = math.cos(math.radians(L['elev']))
    (x0, y0), (x1, y1) = L['tl'], L['br']
    M = 0.2
    mx = M * px; my = M * px * (y1 - y0) / (h * px)
    box = (x0 - mx, y0 - my, x1 + mx, y1 + my)
    W1, H1 = int(round((w + 2 * M) * OUTS[0])), int(round((h + 2 * M) * OUTS[0]))
    for k, OUT in enumerate(OUTS):
        Wk, Hk = W1 * (k + 1), H1 * (k + 1)
        a = resample(key, box, (Wk, Hk))
        S = int(round((1.5 + M) * OUTS[0])) * (k + 1); o = int(round(1.6 * OUT))
        a = detrend2(a, S, Wk - S, S, Hk - S)
        a = tile_mirror(a, S, Wk - S, 1, o); a = tile_mirror(a, S, Hk - S, 0, o)
        save(a, out + ('' if k == 0 else '@2x'))
        if k == 0:
            mid = unpremul(a)
            arr = np.asarray(mid.convert('RGB')).astype(np.float64)[S:Hk - S, S:Wk - S]
            mean = arr.reshape(-1, 3).mean(0)
    S1 = int(round((1.5 + M) * OUTS[0])); ins = r2(S1 / 2.4)
    META[out] = {'file': out + '.webp', 'x2': out + '@2x.webp', 'px': [W1, H1], 'px_per_pt': 2.4,
                 'pt': [r2(W1 / 2.4), r2(H1 / 2.4)], 'kind': 'nine',
                 'capInsets': {'top': ins, 'leading': ins, 'bottom': ins, 'trailing': ins}, 'resizingMode': 'tile',
                 'shadow_outset_pt': {'top': 2.0, 'leading': 2.0, 'bottom': 2.0, 'trailing': 2.0},
                 'content_padding_pt': 12.5, 'mean_tile_srgb': '#%02X%02X%02X' % tuple(int(round(c)) for c in mean),
                 '_mean': mean.tolist()}


def lum(rgb):
    c = np.asarray(rgb, np.float64) / 255.0
    c = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]


def contrast(hex_fg, rgb_bg):
    fg = [int(hex_fg[i:i + 2], 16) for i in (1, 3, 5)]
    a, b = lum(fg), lum(rgb_bg)
    return (max(a, b) + 0.05) / (min(a, b) + 0.05)


# ---------------------------------------------------------------------------------------------------------------------
def drop(name):
    """A picture this post no longer writes (a long strip has no @2x): removed, since the app prefers an @2x file."""
    p = os.path.join(PIC, name + '.webp')
    if os.path.exists(p): os.remove(p); print('removed', name + '.webp', flush=True)


def plank_long(L):
    """(11-10) The shop-wood shelf: one long strip that never repeats (ircapture_kit.py renders it whole, lit alike
    along its length), 1x only at 24 px a cm (3 px a point at the shelf's 8 pt a cm: more than a Retina screen's 2)."""
    key = 'plank'; px = L['pxcm']; ce = math.cos(math.radians(L['elev']))
    top = max(0.0, L['row_back'] - 1.0 * px * ce)
    bot = min(alpha_extent(key, 0, 0, L['size'][0], thresh=1.0) + 0.25 * px, L['size'][1])
    H1 = int(round((bot - top) / (px * ce) * OUTS[0])); bot = top + H1 / OUTS[0] * px * ce
    Lcm = L['x'][1] - L['x'][0]; W1 = int(round(Lcm * OUTS[0]))
    a = resample(key, (0, top, L['size'][0], bot), (W1, H1))
    a = feather(a, 'tb', int(round(0.5 * OUTS[0])))
    save(a, 'irc-plank'); drop('irc-plank@2x')
    def ypt(row): return r2((row - top) / (px * ce) * PT_CM)
    y_back, y_ft, y_fb = ypt(L['row_back']), ypt(L['row_front_top']), ypt(L['row_front_bot'])
    META['irc-plank'] = {'file': 'irc-plank.webp', 'x2': None, 'px': [W1, H1], 'px_per_pt': 2.4,
                         'pt': [r2(W1 / 2.4), r2(H1 / 2.4)], 'kind': 'strip-h',
                         'capInsets': {'top': 0, 'leading': 0, 'bottom': 0, 'trailing': 0}, 'resizingMode': 'tile',
                         'repeat_pt': r2(Lcm * PT_CM), 'how': 'crop to the length needed from its start (never resize); it repeats only past its end',
                         'y_pt': {'top_back_edge': y_back, 'front_top_edge': y_ft, 'front_bottom_edge': y_fb},
                         'thickness_pt': r2(y_fb - y_ft), 'top_surface_pt': r2(y_ft - y_back),
                         'shadow_outset_pt': {'top': y_back, 'leading': 0, 'bottom': r2(H1 / 2.4 - y_fb), 'trailing': 0},
                         'boards_cm': L.get('boards_cm'), 'measures_cm': {'thick': 2.6, 'depth': 12.0}}
    META['irc-plank']['elev'] = L['elev']
    if 'row_under_back' in L:                 # (11-10) seen from below: the underside under the front edge, to the wall
        yu = ypt(L['row_under_back'])
        META['irc-plank']['y_pt']['underside_back_edge'] = yu
        META['irc-plank']['underside_pt'] = r2(yu - y_fb)
        META['irc-plank']['shadow_outset_pt']['bottom'] = r2(META['irc-plank']['pt'][1] - yu)


def trim_long(which, L):
    key = 'trim-' + which; px = L['pxcm']; ce = math.cos(math.radians(L['elev']))
    if which == 'h':
        top = max(0.0, L['row_top'] - 0.6 * px * ce)
        bot = min(alpha_extent(key, 0, 0, L['size'][0], thresh=1.0) + 0.15 * px, L['size'][1])
        H1 = int(round((bot - top) / (px * ce) * OUTS[0])); bot = top + H1 / OUTS[0] * px * ce
        Lcm = L['x'][1] - L['x'][0]; W1 = int(round(Lcm * OUTS[0]))
        save(feather(resample(key, (0, top, L['size'][0], bot), (W1, H1)), 'tb', int(round(0.25 * OUTS[0]))), 'irc-trim-h')
        drop('irc-trim-h@2x')
        def ypt(row): return r2((row - top) / (px * ce) * PT_CM)
        y0, y1 = ypt(L['row_top']), ypt(L['row_bot'])
        META['irc-trim-h'] = {'file': 'irc-trim-h.webp', 'x2': None, 'px': [W1, H1], 'px_per_pt': 2.4,
                              'pt': [r2(W1 / 2.4), r2(H1 / 2.4)], 'kind': 'strip-h',
                              'capInsets': {'top': 0, 'leading': 0, 'bottom': 0, 'trailing': 0}, 'resizingMode': 'tile',
                              'repeat_pt': r2(Lcm * PT_CM), 'face_pt': {'y_top': y0, 'y_bottom': y1, 'w': r2(y1 - y0)},
                              'shadow_outset_pt': {'top': y0, 'leading': 0, 'bottom': r2(H1 / 2.4 - y1), 'trailing': 0}}
    else:
        left = max(0.0, L['px_left'] - 0.6 * px)
        right = min(alpha_extent(key, 1, 0, L['size'][1], thresh=1.0) + 0.15 * px, L['size'][0])
        W1 = int(round((right - left) / px * OUTS[0])); right = left + W1 / OUTS[0] * px
        Lcm = L['y'][1] - L['y'][0]; H1 = int(round(Lcm * OUTS[0]))
        save(feather(resample(key, (left, 0, right, L['size'][1]), (W1, H1)), 'lr', int(round(0.25 * OUTS[0]))), 'irc-trim-v')
        drop('irc-trim-v@2x')
        def xpt(col): return r2((col - left) / px * PT_CM)
        x0, x1 = xpt(L['px_left']), xpt(L['px_right'])
        META['irc-trim-v'] = {'file': 'irc-trim-v.webp', 'x2': None, 'px': [W1, H1], 'px_per_pt': 2.4,
                              'pt': [r2(W1 / 2.4), r2(H1 / 2.4)], 'kind': 'strip-v',
                              'capInsets': {'top': 0, 'leading': 0, 'bottom': 0, 'trailing': 0}, 'resizingMode': 'tile',
                              'repeat_pt': r2(Lcm * PT_CM), 'face_pt': {'x_left': x0, 'x_right': x1, 'w': r2(x1 - x0)},
                              'shadow_outset_pt': {'top': 0, 'leading': x0, 'bottom': 0, 'trailing': r2(W1 / 2.4 - x1)}}


def plank():
    key = 'plank'
    if key not in lay: return
    if lay[key].get('kind') == 'long': return plank_long(lay[key])
    L = lay[key]; px = L['pxcm']; ce = math.cos(math.radians(L['elev']))
    P_cm = L['x_tile'][1] - L['x_tile'][0]; F = 2.5
    xa0, xa1 = L['px_tile0'] - F * px, L['px_tile1']
    top = max(0.0, L['row_back'] - 1.0 * px * ce)                 # the wall's darkening just above the back edge
    bot = min(alpha_extent(key, 0, int(L['px_tile0']), int(L['px_tile1']), thresh=1.0) + 0.25 * px, L['size'][1])
    H1 = int(round((bot - top) / (px * ce) * OUTS[0]))
    bot = top + H1 / OUTS[0] * px * ce
    for k, OUT in enumerate(OUTS):
        Wk = int(round((P_cm + F) * OUT)); Hk = H1 * (k + 1)
        a = resample(key, (xa0, top, xa1, bot), (Wk, Hk))
        f = int(round(F * OUT))
        a = detrend_rows(a, f, Wk, 1)               # the key light's falloff along the 60 cm (about 15 %)
        a = tile_wrap(a, f, Wk, 1, f)[:, f:]
        a = feather(a, 'tb', int(round(0.5 * OUT)))
        save(a, 'irc-plank' + ('' if k == 0 else '@2x'))
    W1 = int(round(P_cm * OUTS[0]))
    def ypt(row): return r2((row - top) / (px * ce) * PT_CM)
    y_back, y_ft, y_fb = ypt(L['row_back']), ypt(L['row_front_top']), ypt(L['row_front_bot'])
    META['irc-plank'] = {'file': 'irc-plank.webp', 'x2': 'irc-plank@2x.webp', 'px': [W1, H1], 'px_per_pt': 2.4,
                         'pt': [r2(W1 / 2.4), r2(H1 / 2.4)], 'kind': 'strip-h',
                         'capInsets': {'top': 0, 'leading': 0, 'bottom': 0, 'trailing': 0}, 'resizingMode': 'tile',
                         'repeat_pt': r2(P_cm * PT_CM), 'how': 'repeat along x (one period is the whole picture); never resize vertically',
                         'y_pt': {'top_back_edge': y_back, 'front_top_edge': y_ft, 'front_bottom_edge': y_fb},
                         'thickness_pt': r2(y_fb - y_ft), 'top_surface_pt': r2(y_ft - y_back),
                         'shadow_outset_pt': {'top': y_back, 'leading': 0, 'bottom': r2(H1 / 2.4 - y_fb), 'trailing': 0},
                         'measures_cm': {'thick': 2.6, 'depth': 12.0, 'edge_round': 0.28}}


def box(name):
    key = 'box-' + name
    if key not in lay: return
    L = lay[key]; px = L['pxcm']; ce = math.cos(math.radians(L['elev']))
    left = max(0.0, L['px_left'] - 1.4 * px)                       # the wall's darkening left of the box
    right = min(alpha_extent(key, 1, 0, 10 ** 6, thresh=1.0) + 0.2 * px, L['size'][0])
    W1 = int((right - left) / px * OUTS[0]); right = left + W1 / OUTS[0] * px
    bot = L['row_plank_front_top']
    top0 = max(0.0, L['row_lid_back'] - 3.0 * px * ce)              # the wall's darkening above the lid
    H1 = int((bot - top0) / (px * ce) * OUTS[0]); top = bot - H1 / OUTS[0] * px * ce
    capL = (L['px_left'] - left) / px + 2.9; capR = (right - L['px_right']) / px + 3.0   # the ends whole, the right with its shadow
    for k, OUT in enumerate(OUTS):
        Wk, Hk = W1 * (k + 1), H1 * (k + 1)
        a = resample(key, (left, top, right, bot), (Wk, Hk))
        S0 = int(round(capL * OUTS[0])) * (k + 1); S1 = Wk - int(round(capR * OUTS[0])) * (k + 1)
        a = detrend_rows(a, S0, S1, 1)
        a = tile_mirror(a, S0, S1, 1, int(round(1.6 * OUT)))
        a = feather(a, 'tlr', int(round(0.6 * OUT)))
        save(a, 'irc-box-' + name + ('' if k == 0 else '@2x'))
    def ypt(row): return r2((row - top) / (px * ce) * PT_CM)
    def xpt(col): return r2((col - left) / px * PT_CM)
    capL_pt = r2(int(round(capL * OUTS[0])) / 2.4); capR_pt = r2(int(round(capR * OUTS[0])) / 2.4)
    fx0, fx1 = xpt(L['px_left']), xpt(L['px_right']); fy0, fy1 = ypt(L['row_face_top']), ypt(L['row_face_bot'])
    META['irc-box-' + name] = {
        'file': 'irc-box-%s.webp' % name, 'x2': 'irc-box-%s@2x.webp' % name, 'px': [W1, H1], 'px_per_pt': 2.4,
        'pt': [r2(W1 / 2.4), r2(H1 / 2.4)], 'kind': 'three-h',
        'capInsets': {'top': 0, 'leading': capL_pt, 'bottom': 0, 'trailing': capR_pt}, 'resizingMode': 'tile',
        'how': 'resize along x only (the middle repeats); draw at the picture\'s own height',
        'front_face_pt': {'x': fx0, 'y': fy0, 'w': r2(fx1 - fx0), 'h': r2(fy1 - fy0), 'trailing_from_right': r2(W1 / 2.4 - fx1)},
        'face_flat_inset_pt': r2(L['edge_in'] * PT_CM),
        'lid_pt': {'y_back': ypt(L['row_lid_back']), 'y_front': fy0},
        'feet_pt': {'center_in_from_face_ends': r2(L['foot_in'] * PT_CM), 'radius': r2(L['foot_r'] * PT_CM), 'gap_under_face': 4.0},
        'shadow_outset_pt': {'top': ypt(L['row_lid_back']), 'leading': fx0, 'bottom': r2(H1 / 2.4 - fy1), 'trailing': r2(W1 / 2.4 - fx1)},
        'plank_overlap_pt': None,                  # filled in below from the plank strip
        'measures_cm': {'face_h': 7.0, 'depth': 10.0, 'corner_r': 0.45, 'roll': 0.25, 'front_z': 11.0, 'feet_h': 0.4}}


def trim(which):
    key = 'trim-' + which
    if key not in lay: return
    if lay[key].get('kind') == 'long': return trim_long(which, lay[key])
    L = lay[key]; px = L['pxcm']; ce = math.cos(math.radians(L['elev'])); F = 1.8
    if which == 'h':
        P_cm = L['x_tile'][1] - L['x_tile'][0]
        xa0, xa1 = L['px_tile0'] - F * px, L['px_tile1']
        top = max(0.0, L['row_top'] - 0.6 * px * ce)
        bot = min(alpha_extent(key, 0, int(L['px_tile0']), int(L['px_tile1']), thresh=1.0) + 0.15 * px, L['size'][1])
        H1 = int(round((bot - top) / (px * ce) * OUTS[0])); bot = top + H1 / OUTS[0] * px * ce
        for k, OUT in enumerate(OUTS):
            Wk = int(round((P_cm + F) * OUT)); Hk = H1 * (k + 1); f = int(round(F * OUT))
            a = resample(key, (xa0, top, xa1, bot), (Wk, Hk))
            save(feather(tile_wrap(detrend_rows(a, f, Wk, 1), f, Wk, 1, f)[:, f:], 'tb', int(round(0.25 * OUT))), 'irc-trim-h' + ('' if k == 0 else '@2x'))
        W1 = int(round(P_cm * OUTS[0]))
        def ypt(row): return r2((row - top) / (px * ce) * PT_CM)
        y0, y1 = ypt(L['row_top']), ypt(L['row_bot'])
        META['irc-trim-h'] = {'file': 'irc-trim-h.webp', 'x2': 'irc-trim-h@2x.webp', 'px': [W1, H1], 'px_per_pt': 2.4,
                              'pt': [r2(W1 / 2.4), r2(H1 / 2.4)], 'kind': 'strip-h',
                              'capInsets': {'top': 0, 'leading': 0, 'bottom': 0, 'trailing': 0}, 'resizingMode': 'tile',
                              'repeat_pt': r2(P_cm * PT_CM), 'face_pt': {'y_top': y0, 'y_bottom': y1, 'w': r2(y1 - y0)},
                              'shadow_outset_pt': {'top': y0, 'leading': 0, 'bottom': r2(H1 / 2.4 - y1), 'trailing': 0}}
    else:
        P_cm = L['tile_y'][0] - L['tile_y'][1]
        ya0 = L['row_tile0'] - F * px * ce; ya1 = L['row_tile1']
        left = max(0.0, L['px_left'] - 0.6 * px)
        right = min(alpha_extent(key, 1, int(L['row_tile0']), int(L['row_tile1']), thresh=1.0) + 0.15 * px, L['size'][0])
        W1 = int(round((right - left) / px * OUTS[0])); right = left + W1 / OUTS[0] * px
        for k, OUT in enumerate(OUTS):
            Hk = int(round((P_cm + F) * OUT)); Wk = W1 * (k + 1); f = int(round(F * OUT))
            a = resample(key, (left, ya0, right, ya1), (Wk, Hk))
            save(feather(tile_wrap(detrend_rows(a, f, Hk, 0), f, Hk, 0, f)[f:], 'lr', int(round(0.25 * OUT))), 'irc-trim-v' + ('' if k == 0 else '@2x'))
        H1 = int(round(P_cm * OUTS[0]))
        def xpt(col): return r2((col - left) / px * PT_CM)
        x0, x1 = xpt(L['px_left']), xpt(L['px_right'])
        META['irc-trim-v'] = {'file': 'irc-trim-v.webp', 'x2': 'irc-trim-v@2x.webp', 'px': [W1, H1], 'px_per_pt': 2.4,
                              'pt': [r2(W1 / 2.4), r2(H1 / 2.4)], 'kind': 'strip-v',
                              'capInsets': {'top': 0, 'leading': 0, 'bottom': 0, 'trailing': 0}, 'resizingMode': 'tile',
                              'repeat_pt': r2(P_cm * PT_CM), 'face_pt': {'x_left': x0, 'x_right': x1, 'w': r2(x1 - x0)},
                              'shadow_outset_pt': {'top': 0, 'leading': x0, 'bottom': 0, 'trailing': r2(W1 / 2.4 - x1)}}


for _pn in ('panel-fine', 'panel-fine-b', 'panel-nam', 'panel-nam-b'): panel(_pn, 'rkit-' + _pn)


# (11-04) the six worn keys: key-<state>-<v>.png from ircapture_kit.py's key-<v> pieces, cropped as toolkit_post.py's
# keys (the outline plus 0.12 cm, the camera's shortening undone), 24 and 48 px a cm: rkit-key-<state>-<v>.webp and
# @2x, the same size and slices as rkit-key-<state> (13 px a side at 1x; the app's insets 5.42 pt)
KLAY = {}
for f in glob.glob(os.path.join(R, 'toolkit-keys-*.json')):
    KLAY.update(json.load(open(f))['out'])


def key(name):
    L = KLAY[name]; w, h = L['cm']; (x0, y0), (x1, y1) = L['tl'], L['br']; M = 0.12
    px = (x1 - x0) / w; mx = M * px; my = M * (y1 - y0) / h
    W1, H1 = int(round((w + 2 * M) * OUTS[0])), int(round((h + 2 * M) * OUTS[0]))
    for k, OUT in enumerate(OUTS):
        a = resample(name, (x0 - mx, y0 - my, x1 + mx, y1 + my), (W1 * (k + 1), H1 * (k + 1)))
        save(a, 'rkit-' + name + ('' if k == 0 else '@2x'))
    META['rkit-' + name] = {'file': 'rkit-%s.webp' % name, 'x2': 'rkit-%s@2x.webp' % name, 'px': [W1, H1], 'px_per_pt': 2.4,
                            'kind': 'nine', 'capInsets': {'top': 5.42, 'leading': 5.42, 'bottom': 5.42, 'trailing': 5.42},
                            'resizingMode': 'stretch', 'like': 'rkit-' + name.rsplit('-', 1)[0]}


for _k in sorted(KLAY): key(_k)
if KLAY:
    META['key-variants'] = {'variants': sorted({k.rsplit('-', 1)[1] for k in KLAY}),
                            'how': 'rkit-key-<state>-<v>: one of six keys, each its own wear; pick one per button by a '
                                   'stable hash of its label (so a button keeps its key); without them rkit-key-<state>'}
plank()
for b in ('bronze', 'oxblood'): box(b)
trim('h'); trim('v')

# the boxes on the plank: a box picture's bottom edge is the plank's front top edge
if 'irc-plank' in META:
    ft = META['irc-plank']['y_pt']['front_top_edge']
    for b in ('bronze', 'oxblood'):
        k = 'irc-box-' + b
        if k in META:
            META[k]['plank_overlap_pt'] = ft
            META[k]['place_on_plank'] = ('box.maxY = plank.minY + %.2f pt (the plank strip\'s front top edge): the box '
                                         'picture overlaps the strip\'s top %.2f pt; draw the box over the plank' % (ft, ft))
for k in ('rkit-panel-fine', 'rkit-panel-fine-b', 'rkit-panel-nam', 'rkit-panel-nam-b'):
    if k in META:
        mean = META[k].pop('_mean')
        META[k]['contrast_on_mean'] = {'#E6E1D4': r2(contrast('#E6E1D4', mean)), '#D9D2C2': r2(contrast('#D9D2C2', mean))}

doc = {'about': 'IR Capture\'s own rendered pieces (ircapture_kit.py, the desktop bench\'s Tools studio: orthographic, '
                '10 degrees above, key light up and to the left). Points at 10 pt a cm; px_per_pt is the 1x file\'s; '
                '@2x has twice the pixels. capInsets in points (top, leading, bottom, trailing). shadow_outset_pt: how far '
                'the picture runs past the object on each side (shadow and margin).',
       'renders': {k: {'pxcm': v['pxcm'], 'samples': v['samples'], 's': v.get('s')} for k, v in lay.items()},
       'pieces': META}
# (11-10) irc-shelf.json, the app's shelf layout, from the pieces (it was written by hand from irc-pieces.json): the
# shelf is drawn at 8 pt a cm (pxPerPoint 3.0 of the 1x files), boxTop and gapBelowPlank are layout choices and kept
def shelf_json():
    sp = os.path.join(O, 'irc-shelf.json')
    if not os.path.exists(sp): return
    old = json.load(open(sp)); allp = dict(json.load(open(os.path.join(O, 'irc-pieces.json')))['pieces']) if os.path.exists(os.path.join(O, 'irc-pieces.json')) else {}
    allp.update(META)
    pk, bx, th = allp.get('irc-plank'), allp.get('irc-box-bronze'), allp.get('irc-trim-h')
    if not (pk and bx and th): return
    k = 0.8                                                           # 10 pt a cm (the pieces) to the shelf's 8
    face = bx['front_face_pt']; fi = bx['face_flat_inset_pt']; Wb, Hb = bx['pt']
    new = dict(old)
    new.update({'plankHeight': r2(pk['pt'][1] * k), 'plankBelowBoxTop': r2((Hb - pk['y_pt']['front_top_edge']) * k),
                'plankFrontBottom': r2(pk['y_pt'].get('underside_back_edge', pk['y_pt']['front_bottom_edge']) * k), 'boxHeight': r2(Hb * k),
                'boxInsets': [0, r2(bx['capInsets']['leading'] * k), 0, r2(bx['capInsets']['trailing'] * k)],
                'boxFace': [r2((face['y'] + fi) * k), r2((face['x'] + fi) * k), r2((Hb - face['y'] - face['h'] + fi) * k),
                            r2((face['trailing_from_right'] + fi) * k)],
                'trimWidth': r2(th['pt'][1] * k)})
    if new != old:
        json.dump(new, open(sp, 'w'), indent=0); print('wrote', sp, {k2: new[k2] for k2 in new if new[k2] != old.get(k2)})


path = os.path.join(O, 'irc-pieces.json')
existing = json.load(open(path)) if os.path.exists(path) else None
if existing:                                  # keep pieces posted from another renders folder
    existing['pieces'].update(META); existing['renders'].update(doc['renders']); doc = existing
json.dump(doc, open(path, 'w'), indent=1)
print('wrote', path)
shelf_json()
