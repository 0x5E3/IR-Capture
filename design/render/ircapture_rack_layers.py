# ircapture_rack_layers.py: the rack bay's units for the app (2026-11-11, step 4 of the visual audit's order of work).
#
# ircapture_rack.py renders each unit whole, its live parts baked in (the proofs). Here a unit is rendered as a BASE with
# every live part in its resting state (lamps dark), then each live state as a crop of the same scene (render border:
# only that region is rendered, with everything else as in the base). ircapture_rack_post.py keeps only the pixels that
# changed (the lamp and its glow on the panel) and writes the kit's pictures and irc-rack.json.
#
#   cheeks     the rack's sides and top: shop-wood boards (ircapture_rack.unit_cheeks)
#   step-cab   1U bronze, four jewels: CONNECT, SET LEVELS, CAPTURE, RESULTS (done green, current amber, ahead dark)
#   step-nam   1U graphite anodised, five flush LEDs: SIGNAL, CONNECT, SET LEVELS, RECORD, UPLOAD (the NAM rack's family)
#
#   FONTS_DIR=Resources/SwellKit/fonts IRC_LIQUID_RELIEF=0.7 ~/bvenv/bin/python design/render/ircapture_rack_layers.py \
#       <out> <unit[,unit]> [px/cm] [samples]
# Run from the bench's design/render folder, as ircapture_rack.py.
import sys, os, json, time
_argv = sys.argv[:]
OUT = _argv[1] if len(_argv) > 1 else '/tmp/ircrl'
WHAT = _argv[2] if len(_argv) > 2 else 'step-cab'
PXCM = float(_argv[3]) if len(_argv) > 3 else 42.0
SAMPLES = int(_argv[4]) if len(_argv) > 4 else 64
sys.argv = [_argv[0], OUT, 'none', str(PXCM), str(SAMPLES)]
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ircapture_rack as R
sys.argv = _argv
import bpy
import parts as P
import toolkit as TK
import ircapture_kit as K

LAY = {'pxcm': PXCM, 'samples': SAMPLES, 'pt_per_cm': R.PT, 'units': {}}


def _save():
    json.dump(LAY, open(os.path.join(OUT, 'rack-layers-%s.json' % WHAT.replace(',', '+')), 'w'), indent=1)


def box_px(s, cam, x, y, rx, ry):
    """The pixel box (x0, y0, x1, y1 from the top left) round (x, y) +- (rx, ry) cm on the panel face, padded to 8 px."""
    a = TK.proj(s, cam, (x - rx, y + ry, 0.0)); b = TK.proj(s, cam, (x + rx, y - ry, 0.0))
    W, H = s.render.resolution_x, s.render.resolution_y
    x0 = int(min(a[0], b[0]) // 8 * 8); y0 = int(min(a[1], b[1]) // 8 * 8)
    x1 = int(-(-max(a[0], b[0]) // 8) * 8); y1 = int(-(-max(a[1], b[1]) // 8) * 8)
    return [max(0, x0), max(0, y0), min(W, x1), min(H, y1)]


def shoot_base(s, cam, name, w, h):
    bpy.context.view_layer.update()
    s.render.use_border = False
    t = time.time(); P.render(s, os.path.join(OUT, name + '.png'))
    return {'picture': name, 'size_px': [s.render.resolution_x, s.render.resolution_y], 'cm': [w, h],
            'tl': TK.proj(s, cam, (-w / 2, h / 2, 0.0)), 'br': TK.proj(s, cam, (w / 2, -h / 2, 0.0)),
            's': round(time.time() - t, 1)}


def shoot_crop(s, cam, name, box):
    bpy.context.view_layer.update()
    P.set_border(s, box)
    P.render(s, os.path.join(OUT, name + '.png'))
    s.render.use_border = False
    return {'picture': name, 'box_px': box}


# ---------------------------------------------------------------------------------------------------------------------
# the step strips

CAB_STEPS = ['CONNECT', 'SET LEVELS', 'CAPTURE', 'RESULTS']
NAM_STEPS = ['SIGNAL', 'CONNECT', 'SET LEVELS', 'RECORD', 'UPLOAD']


def build_step_cab(lit):
    """1U bronze (the proof's unit_step). lit: {lamp index: 'green' | 'amber'}; the rest dark amber."""
    K.set_seed('rack-step')
    s, cam, h = R.unit_scene(1)
    R.backing(h)
    R.rack_panel(1, 'bronze', 'step')
    x = -19.0; xs = []
    for i, n in enumerate(CAB_STEPS):
        col = lit.get(i, 'amber')
        R.jewel(x, 0.0, col, i in lit, r=0.55)
        e = R.engrave(n, 0, 0, 0.62)
        wcm = e.dimensions.x; e.location.x = x + 1.1 + wcm / 2 - 0.1 * wcm
        xs.append(x); x += 10.2
    return s, cam, h, xs


def build_step_nam(lit):
    """1U graphite anodised, flush LEDs (the NAM meters' and the cart's family)."""
    K.set_seed('rack-step-nam')
    s, cam, h = R.unit_scene(1)
    R.backing(h)
    pl, ph = R.rack_panel(1, 'alu', 'nstep')
    pl.data.materials.append(K.anodised('nstep', base='#2a2a2c'))
    x = -19.6; xs = []
    for i, n in enumerate(NAM_STEPS):
        col = lit.get(i, 'amber')
        R.flush_led(x, 0.0, col, i in lit, r=0.3, k=float(os.environ.get('IRC_STEP_LED_K', '1.1')))
        e = R.engrave(n, 0, 0, 0.62, color='#cfc9bd')
        wcm = e.dimensions.x; e.location.x = x + 0.85 + wcm / 2 - 0.1 * wcm
        xs.append(x); x += 8.45
    R.finish_glass()
    return s, cam, h, xs


def step_unit(key, build, n, glow_cm):
    s, cam, h, xs = build({})
    L = shoot_base(s, cam, 'rack-' + key, R.PW, h)
    L['u'] = 1; L['layers'] = {}
    LAY['units'][key] = L; _save()
    for i in range(n):
        for col in ('green', 'amber'):
            s, cam, h, xs = build({i: col})
            box = box_px(s, cam, xs[i], 0.0, glow_cm, glow_cm)
            nm = 'rack-%s-l%d-%s' % (key, i, col)
            L['layers']['l%d-%s' % (i, col)] = shoot_crop(s, cam, nm, box)
            _save()
    L['lamp_x_cm'] = xs


def unit_step_cab():
    step_unit('step-cab', build_step_cab, len(CAB_STEPS), 1.9)


def unit_step_nam():
    step_unit('step-nam', build_step_nam, len(NAM_STEPS), 0.9)


def unit_cheeks():
    R.unit_cheeks()
    LAY['cheeks'] = {k: R.LAY['out'][k] for k in ('trim-v', 'trim-h')}
    _save()


UNITS = {'step-cab': unit_step_cab, 'step-nam': unit_step_nam, 'cheeks': unit_cheeks}


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    for u in WHAT.split(','):
        t = time.time(); UNITS[u](); print('unit', u, '%.0fs' % (time.time() - t), flush=True)
