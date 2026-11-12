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
#   meters     5U meter bridge          results    7U take sheet, typed by the app
#   chart      6U hook-up drawing and card (whole)          preflight  4U BEFORE CAPTURE, typed by the app
#   patch      2U eight toggles MIC / OFF / REF            nammeters  3U NAM meter bridge (bars, LED digits, LEDs)
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
        # (11-11 late) saturated LEDs: Lowell found the first ones "a little pastel"
        R.flush_led(x, 0.0, col, i in lit, r=0.3, k=float(os.environ.get('IRC_STEP_LED_K', '0.6')),
                    sat=os.environ.get('IRC_STEP_LED_SAT', '1') == '1')
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


# ---------------------------------------------------------------------------------------------------------------------
# the meter bridge (5U): four channel modules in a frame (the first proof's unit_meters, approved)
#
# Built ONCE with every live part present and switchable, then shot in its states (the step strips rebuilt the scene
# for each state; with four modules that is too slow, and toggling in one scene gives the same pixels outside the part):
#   base         every module at rest: VU card unlit, no needle, gas window dark, eye dark, lamps dark, strips blank
#   m<i>-vu      module i's VU card lit (the lamp behind it)
#   m<i>-l<k>    module i's lamp k lit (LOW OK HIGH CLIP DIST)
#   b<i>         slot i holding a blank filler plate in place of its module (fewer than four inputs)
#   eye sheet    module 0's eye in each of rack.py's states (warm0..2, x00..x55), the inside of its bore only: the same
#                at every module, drawn by the app at each module's eye
#   needle       one needle alone (everything else hidden from the camera), standing at 0 degrees, turned by the app
# The app lights the gas segments on the window's geometry and writes the mic's name on the strip.

MLAMPS = R.LAMPS                            # (legend, colour)
METER_MODS = [dict(v='a', base='#1d1812', name='m0'), dict(v='b', base='#1a1610', name='m1'),
              dict(v='c', base='#1d1812', name='m2'), dict(v='d', base='#191612', name='m3')]
_GAS = []


def _capture_gas_window():
    """ircapture_rack.gas_digits keeps gas_window's layout to itself: record each window's cells as it is made."""
    GD = R.GD
    if getattr(GD, '_irc_wrapped', False): return
    orig = GD.gas_window
    def wrapped(RA, L, *a, **k):
        r = orig(RA, L, *a, **k); _GAS.append(dict(L[-1])); return r
    GD.gas_window = wrapped; GD._irc_wrapped = True


def _new_since(before):
    bpy.context.view_layer.update()
    return [o for o in bpy.data.objects if o not in before]


def _vu_parts(name):
    """ircapture_rack.vu without its needle, the card built lit with its lamp's strength switchable; the needle made
    apart (standing at 0 degrees, hidden). Returns (lamp strength node, needle)."""
    V = R.V
    K.set_seed('vu-' + name)
    BZ, WIN = V.BZ, V.WIN
    bz = R.rbox('vubezel', BZ['w'], BZ['h'], BZ['d'], 0.0, BZ['r'], roll=BZ['roll'])
    hole = R.rbox('vuhole', WIN['w'], WIN['h'], 4.0, -2.0, WIN['r']); hole.location.y = WIN['y']
    bpy.context.view_layer.update(); R.cut(bz, hole); R.chamfer(bz, 0.02, 2); TK.flat_faces(bz)
    bz.data.materials.append(V.phenolic('vubezel-' + name))
    well = R.rbox('vuwell', WIN['w'] + 0.3, WIN['h'] + 0.3, 0.3, V.Z_FACE - 0.33, 0.2); well.location.y = WIN['y']
    well.data.materials.append(R.mat('vuwell', R.srgb('#0e0d0c'), rough=0.7))
    cw, ch = WIN['w'] + 0.2, WIN['h'] + 0.2
    fp = os.path.join(OUT, 'vu-face-print.png')
    if not os.path.exists(fp): V.face_png(fp, cw, ch)
    bpy.ops.mesh.primitive_plane_add(size=1, location=(0, WIN['y'], V.Z_FACE)); card = bpy.context.active_object
    card.name = 'vucard'; card.scale = (cw, ch, 1); bpy.ops.object.transform_apply(scale=True)
    m = V.card_material(fp, cw, ch, True); card.data.materials.append(m)
    st = [n for n in m.node_tree.nodes if n.bl_idname == 'ShaderNodeMath' and n.operation == 'MULTIPLY'
          and not n.inputs[1].is_linked and n.outputs[0].links and n.outputs[0].links[0].to_socket.name == 'Emission Strength'][0]
    gl = R.rbox('vuglass', WIN['w'] + 0.12, WIN['h'] + 0.12, 0.14, V.Z_GLASS - 0.14, WIN['r']); gl.location.y = WIN['y']
    R.chamfer(gl, 0.012, 1); TK.flat_faces(gl); gl.data.materials.append(V.glass_mat()); gl.visible_shadow = False
    R.GLASS.append(gl)
    nm = R.mat('vuneedle', R.srgb('#121110'), rough=0.42, spec=0.35)
    Ln = V.NEEDLE_L + 0.4
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, V.Z_NEEDLE)); nd = bpy.context.active_object
    nd.name = 'vuneedle'; nd.scale = (0.05, Ln, 0.012); bpy.ops.object.transform_apply(scale=True)
    for v in nd.data.vertices: v.co.y = V.PIVOT_Y + v.co.y + (V.NEEDLE_L - 0.4) / 2
    nd.data.materials.append(nm)
    nd.hide_render = True
    return st, nd


def _blank_plate(name, base):
    """A blank filler plate the size of a channel module: the same stock and finish, its four screws, nothing in it."""
    K.set_seed('rack-blank-' + name)
    pl = R.rbox('bplate', R.MW, R.MH, R.MZ, -R.MZ, 0.18, roll=0.05)
    R.chamfer(pl, 0.015, 2); TK.flat_faces(pl)
    pl.data.materials.append(K.hammertone_fine(base=base, name='hf-blank-' + name))
    R.small_screws([(sx * (R.MW / 2 - 0.45), sy * (R.MH / 2 - 0.45)) for sx in (-1, 1) for sy in (-1, 1)], seed=K.seed_of(name) % 7 + 1)


def _module(mo, ox):
    """ircapture_rack.module at rest, its live parts kept: returns a dict of handles and positions (world cm)."""
    MW, MH, MZ, V = R.MW, R.MH, R.MZ, R.V
    nm = mo['name']
    K.set_seed('rack-mod-' + nm)
    before = set(bpy.data.objects)
    out = {'x': ox}
    with R.moved(ox, 0, MZ):
        pl = R.rbox('mplate', MW, MH, MZ, -MZ, 0.18, roll=0.05)
        yv = MH / 2 - 0.85 - V.BZ['h'] / 2
        yr = yv - V.BZ['h'] / 2 - 0.55 - 1.9
        n0 = len(_GAS)
        gw, gh = R.gas_digits(pl, -2.45, yr, '', nm)
        g = _GAS[n0]
        e = R.eye(pl, 3.35, yr, 'unlit', nm)
        R.chamfer(pl, 0.015, 2); TK.flat_faces(pl)
        pl.data.materials.append(K.hammertone_fine(base=mo['base'], name='hf-' + nm))
        R.small_screws([(sx * (MW / 2 - 0.45), sy * (MH / 2 - 0.45)) for sx in (-1, 1) for sy in (-1, 1)], seed=K.seed_of(nm) % 7)
        with R.moved(0, yv, 0): st, nd = _vu_parts(nm)
        R.engrave('PEAK  dBFS', -2.45, yr - gh / 2 - 0.5, 0.44, track=0.14)
        R.engrave('NOISE', 3.35, yr - 1.9 - 0.5, 0.44, track=0.14)
        yl = yr - 1.9 - 0.5 - 1.35
        lamps = []
        for i, (lab, col) in enumerate(MLAMPS):
            x = -4.3 + i * 2.15
            b0 = set(bpy.data.objects)
            R.jewel(x, yl, col, True, r=0.42)
            new = _new_since(b0)
            lens = [o for o in new if o.name.startswith('jlens')][0]
            light = [o for o in new if o.type == 'LIGHT'][0]
            bsdf = lens.active_material.node_tree.nodes['Principled BSDF']
            lamps.append(dict(bsdf=bsdf, hot=tuple(bsdf.inputs['Emission Color'].default_value), light=light, x=x, y=yl))
            R.engrave(lab, x, yl - 0.95, 0.44, track=0.12)
        ys = -MH / 2 + 0.55 + K.SCRIB['h'] / 2
        with R.moved(0, ys, 0): R.strip(mo['v'], 10.2, '', nm)
    out.update(st=st, needle=nd, eye=e, lamps=lamps, objs=_new_since(before), yv=yv, yr=yr, yl=yl, ys=ys,
               gas=dict(cells=[c for c in g['cells'][:4]], n=g['n']), strip_len=10.2)
    for L in lamps: L['x'] += ox
    return out


def _lamp(L, on):
    L['bsdf'].inputs['Emission Color'].default_value = L['hot'] if on else (0.0, 0.0, 0.0, 1.0)
    L['light'].hide_render = not on


def _share_finishes():
    """Four modules made each bezel's finish (VU, gas window, eye) four times: twelve sets of true-scale maps, and the
    bridge ran out of memory at 42 px/cm (11-11). The finish is the same stock in every module (the maps sit in object
    space, so each part still shows its own patch of wear): make each once and reuse it."""
    import finish_maps as FM
    if getattr(FM, '_irc_shared', False): return
    orig = FM.material
    memo = {}
    def shared(name, kind, color, k, seed, offset_key, *a, **kw):
        key = (kind, color, k, seed, offset_key, a, tuple(sorted(kw.items())))
        if key not in memo: memo[key] = orig(name, kind, color, k, seed, offset_key, *a, **kw)
        return memo[key]
    FM.material = shared; FM._irc_shared = True
    # the VU's and the gas window's bezels go through calm_up after finish_maps: share them whole, so it runs once
    for mod, fn in ((R.V, 'phenolic'), (K, 'gas_bezel_mat')):
        f0 = getattr(mod, fn); box = {}
        def once(*a, _f=f0, _b=box, **kw):
            if 'm' not in _b: _b['m'] = _f(*a, **kw)
            return _b['m']
        setattr(mod, fn, once)


def build_meters():
    _capture_gas_window()
    _share_finishes()
    K.set_seed('rack-meters')
    s, cam, h = R.unit_scene(5)
    R.backing(h)
    fr, hh = R.rack_panel(5, 'bronze', 'bridge')
    op = R.rbox('fopen', 4 * R.MW + 0.1, R.MH - 0.6, 4, -2, 0.1); bpy.context.view_layer.update(); R.cut(fr, op)
    fr.data.materials.append(K.hammertone_fine(base='#191612', name='hf-bridge'))
    mods, blanks = [], []
    for i, mo in enumerate(METER_MODS):
        ox = (i - 1.5) * (R.MW + 0.06)
        mods.append(_module(mo, ox))
        b0 = set(bpy.data.objects)
        with R.moved(ox, 0, R.MZ): _blank_plate(mo['name'], mo['base'])
        bl = _new_since(b0)
        for o in bl: o.hide_render = True
        blanks.append(bl)
    R.finish_glass()
    for m_ in mods:
        m_['st'].inputs[1].default_value = 0.0
        for L in m_['lamps']: _lamp(L, False)
    return s, cam, h, mods, blanks


def unit_meters():
    s, cam, h, mods, blanks = build_meters()
    L = shoot_base(s, cam, 'rack-meters', R.PW, h)
    L['u'] = 5; L['layers'] = {}
    LAY['units']['meters'] = L; _save()
    P_ = lambda x, y, z=0.0: TK.proj(s, cam, (x, y, z))
    V = R.V
    info = []
    for i, m_ in enumerate(mods):
        ox, MZ = m_['x'], R.MZ
        c = m_['gas']['cells']                   # module-local (x0, y0, x1, y1)
        a, b = P_(ox + c[0], m_['yr'] * 0 + c[3]), P_(ox + c[2], c[1])
        win = V.WIN
        wa = P_(ox - win['w'] / 2, m_['yv'] + win['y'] + win['h'] / 2); wb = P_(ox + win['w'] / 2, m_['yv'] + win['y'] - win['h'] / 2)
        sa = P_(ox - m_['strip_len'] / 2, m_['ys'] + K.SCRIB['h'] / 2); sb = P_(ox + m_['strip_len'] / 2, m_['ys'] - K.SCRIB['h'] / 2)
        info.append(dict(gas=[a[0], a[1], b[0], b[1]], gasN=m_['gas']['n'],
                         vuPivot=P_(ox, m_['yv'] + V.PIVOT_Y), vuWindow=[wa[0], wa[1], wb[0], wb[1]],
                         eye=P_(ox + 3.35, m_['yr']), strip=[sa[0], sa[1], sb[0], sb[1]],
                         lamps=[P_(Lm['x'], Lm['y']) for Lm in m_['lamps']]))
    L['meters'] = dict(modules=info, lamps=[l for l, _ in MLAMPS],
                       vuTable=[[d, round(V.vu_angle(d), 3)] for d in [-22, -20, -15, -10, -7, -5, -3, -2, -1, 0, 1, 2, 3, 3.4]])
    _save()
    # the lamps
    for i, m_ in enumerate(mods):
        for k, Lm in enumerate(m_['lamps']):
            _lamp(Lm, True)
            L['layers']['m%d-l%d' % (i, k)] = shoot_crop(s, cam, 'rack-meters-m%d-l%d' % (i, k), box_px(s, cam, Lm['x'], Lm['y'], 1.5, 1.5))
            _lamp(Lm, False); _save()
    # the VU lamps
    for i, m_ in enumerate(mods):
        m_['st'].inputs[1].default_value = float(os.environ.get('VU_LAMP', '1.0'))
        L['layers']['m%d-vu' % i] = shoot_crop(s, cam, 'rack-meters-m%d-vu' % i,
                                               box_px(s, cam, m_['x'], m_['yv'] + V.WIN['y'], V.WIN['w'] / 2 + 0.6, V.WIN['h'] / 2 + 0.6))
        m_['st'].inputs[1].default_value = 0.0; _save()
    # blank plates in place of the modules
    for i, m_ in enumerate(mods):
        hidden = []
        for o in m_['objs']:
            if not o.hide_render: o.hide_render = True; hidden.append(o)
        for o in blanks[i]: o.hide_render = False
        L['layers']['b%d' % i] = shoot_crop(s, cam, 'rack-meters-b%d' % i, box_px(s, cam, m_['x'], 0.0, R.MW / 2 + 0.6, R.MH / 2 + 0.6))
        for o in blanks[i]: o.hide_render = True
        for o in hidden: o.hide_render = False
        _save()
    # the eye's states (module 0), its bore only
    import rack as RA
    e = mods[0]['eye']; ex, ey = mods[0]['x'] + 3.35, mods[0]['yr']
    ebox = box_px(s, cam, ex, ey, 1.3, 1.3)
    L['eye'] = dict(center=P_(ex, ey), bore_cm=1.5 * 0.8, box_px=ebox, states=[], pictures=[])
    only = os.environ.get('IRC_EYE_STATES')                  # a comma list for a quick check; all by default
    for st in [x for x in RA.EYE_STATES if x != 'unlit' and (not only or x in only.split(','))]:
        e.set(st)
        nm = 'rack-meters-eye-' + st
        shoot_crop(s, cam, nm, ebox)
        L['eye']['states'].append(st); L['eye']['pictures'].append(nm)
        _save()
    e.set('unlit')
    # the needle alone, at 0 degrees, nothing else seen
    m0 = mods[0]
    vis = []
    for o in s.objects:
        if o.type == 'MESH' and o is not m0['needle'] and o.visible_camera:
            o.visible_camera = False; vis.append(o)
    m0['needle'].hide_render = False
    nb = box_px(s, cam, m0['x'], m0['yv'] + V.PIVOT_Y + (V.NEEDLE_L) / 2, 0.4, V.NEEDLE_L / 2 + 0.6)
    shoot_crop(s, cam, 'rack-meters-needle', nb)
    L['needle'] = dict(picture='rack-meters-needle', box_px=nb, pivot=P_(m0['x'], m0['yv'] + V.PIVOT_Y))
    m0['needle'].hide_render = True
    for o in vis: o.visible_camera = True
    _save()


# ---------------------------------------------------------------------------------------------------------------------
# the results (7U): the take sheet in its card frame, the unit's own keys under it (the first proof's unit_results)
#
# The sheet is rendered as the PRINTED FORM only: letterhead, field labels, the table's headings and rules, the CHECKED
# box. Everything that belongs to a take is put on it by the app over the lit paper (multiplied, so the paper's shading
# and tooth show through the ink): the typed entries (Courier Prime, as the proofs typed them), the coloured-pencil dabs
# for the channels' colours, red-pencil rings round a figure to look at, and the verdict's rubber stamp in the CHECKED box
# (stamp pictures from ircapture_rack_post.py). A per-take render is not possible on a customer's Mac; a printed form
# filled in by hand is how such sheets are made anyway.
#   base         the form blank, the keys up
#   k<i>-down    key i pressed (FINDER, RE-EXPORT, RECORD AGAIN)
# FORM (sheet cm: x from its left edge, y down from its top; typed entries by their baselines) goes to irc-rack.json so
# the app types where the rules are. It is the one place the layout lives.

TYPED_CM = 0.74                                         # the typed entries' size (Courier Prime: capitals 6 pt on screen)
RES_W, RES_H = 40.0, 21.4
RES_KEYS = ('finder', 'reexport', 'record-again')


def _form():
    m = 1.3; asc = 0.78 * TYPED_CM
    t0, rh, rows = 6.45, 1.3, 5
    y1 = t0 + rows * rh + 0.75
    lines = lambda k: [round(y1 + 0.78 + asc + i * 1.05, 3) for i in range(k)]
    return {
        'w': RES_W, 'h': RES_H, 'margin': m, 'typedCm': TYPED_CM, 'advance': 0.6,     # Courier: every character 0.6 em
        'title': 'CAB IR  TAKE SHEET',
        'fields': [dict(key=k, label=l, x0=m + a, x1=m + b - 0.5, baseline=4.3) for k, l, a, b in
                   (('capture', 'CAPTURE', 0.0, 10.2), ('date', 'DATE', 10.2, 14.9), ('interface', 'INTERFACE', 14.9, 22.6),
                    ('rate', 'RATE', 22.6, 25.9))],
        'checked': [28.0, 0.6, RES_W - m, 4.75],
        'table': dict(headY=5.6, rule=t0, rowH=rh, rows=rows, baseline0=round(t0 + 0.27 + asc, 3), dabX=m + 0.5,
                      nameX=m + 1.2, cols=[dict(key=k, label=l, x=m + x) for k, l, x in
                                           (('channel', 'CHANNEL', 0.0), ('peak', 'PEAK dBFS', 9.6), ('noise', 'NOISE dB', 14.4),
                                            ('tail', 'TAIL ms', 19.0), ('h2', 'H2 dB', 23.3), ('h3', 'H3 dB', 27.0),
                                            ('arrival', 'ARRIVAL ms', 30.6))], right=RES_W - m),
        'files': dict(labelY=y1, x0=m + 0.1, x1=m + 17.0, baselines=lines(6)),
        'notes': dict(labelY=y1, x0=m + 18.2, x1=RES_W - m, baselines=lines(6)),
    }


FORM = _form()


def take_form(path, px=120):
    """The printed form, nothing typed on it: oxblood ink on cream stock, the paper's tooth and aged edges."""
    from PIL import Image, ImageDraw, ImageFont, ImageFilter
    import numpy as np
    F_ = FORM; w, h = F_['w'], F_['h']
    W, H = int(w * px), int(h * px)
    rng = np.random.default_rng(5)
    im = Image.new('RGB', (W, H), (246, 234, 200)); d = ImageDraw.Draw(im)
    F = lambda name, cm: ImageFont.truetype(os.path.join(R.FONTS, name), int(cm * px))
    ox = (104, 30, 24); rule = (150, 120, 104)
    fh = F('BarlowSemiCondensed-700-normal.ttf', 0.95); # the labels' capitals 0.45 cm: 6.3 pt on screen, over MIN_CAP_PT (the proof's were 0.35 cm, under it)
    fl = F('BarlowSemiCondensed-600-normal.ttf', 0.45 / 0.7)
    cm = lambda v: int(round(v * px)); hair = max(1, cm(0.02))

    def spaced(x, y, text, font, fill, track=0.14):
        tr = track * font.size
        for c in text:
            d.text((x, y), c, font=font, fill=fill); x += font.getlength(c) + tr

    m = F_['margin']; cx0, cy0, cx1, cy1 = F_['checked']
    spaced(cm(m), cm(0.95), F_['title'], fh, ox)
    d.line([(cm(m), cm(2.25)), (cm(cx0 - 0.8), cm(2.25))], fill=ox, width=cm(0.07))
    d.line([(cm(m), cm(2.4)), (cm(cx0 - 0.8), cm(2.4))], fill=ox, width=hair)
    for f in F_['fields']:
        spaced(cm(f['x0'] + 0.1), cm(2.95), f['label'], fl, rule)
        d.line([(cm(f['x0']), cm(4.7)), (cm(f['x1']), cm(4.7))], fill=rule, width=hair)
    # the CHECKED box: where the verdict is stamped
    d.rectangle([cm(cx0), cm(cy0), cm(cx1), cm(cy1)], outline=ox, width=cm(0.035))
    spaced(cm(cx0 + 0.2), cm(cy0 + 0.18), 'CHECKED', fl, rule)
    T = F_['table']; L_, R_ = m, T['right']
    for c in T['cols']: spaced(cm(c['x'] + 0.1), cm(T['headY']), c['label'], fl, rule)
    d.line([(cm(L_), cm(T['rule'])), (cm(R_), cm(T['rule']))], fill=ox, width=max(1, cm(0.035)))
    for r in range(T['rows']):
        y = T['rule'] + (r + 1) * T['rowH']
        d.line([(cm(L_), cm(y)), (cm(R_), cm(y))], fill=rule, width=hair)
    for c in T['cols'][1:]:
        d.line([(cm(c['x'] - 0.25), cm(T['headY'] - 0.1)), (cm(c['x'] - 0.25), cm(T['rule'] + T['rows'] * T['rowH']))], fill=rule, width=hair)
    for key, lab in (('files', 'LOAD THESE'), ('notes', 'NOTES')):
        B = F_[key]
        spaced(cm(B['x0']), cm(B['labelY']), lab, fl, rule)
        for b in B['baselines']:
            d.line([(cm(B['x0'] - 0.1), cm(b + 0.32)), (cm(B['x1']), cm(b + 0.32))], fill=rule, width=hair)
    # paper: tooth, a soft blotchiness, aged edges (as the proof's take sheet)
    a = np.asarray(im, np.float32)
    tooth = np.asarray(Image.fromarray((rng.random((H, W)) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.0)), np.float32) / 255
    a *= (0.975 + 0.05 * tooth)[..., None]
    blot = np.asarray(Image.fromarray((rng.random((H // 8, W // 8)) * 255).astype(np.uint8)).resize((W, H), Image.BICUBIC).filter(ImageFilter.GaussianBlur(40)), np.float32) / 255
    a *= (0.96 + 0.08 * blot)[..., None]
    yy_, xx_ = np.mgrid[0:H, 0:W]
    e = np.maximum(np.abs(xx_ - W / 2) / (W / 2), np.abs(yy_ - H / 2) / (H / 2))
    age = np.clip((e - 0.8) / 0.2, 0, 1) ** 1.8
    a = a * (1 - 0.09 * age[..., None]) * np.array([1.0, 0.98, 0.93])[None, None, :] ** age[..., None]
    Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)).save(path)


def build_results():
    import ircapture_legends as LG
    K.set_seed('rack-results')
    u = 7
    s, cam, h = R.unit_scene(u)
    R.backing(h)
    R.rack_panel(u, 'bronze', 'results')
    sw, sh = RES_W, RES_H
    kh = LG.SIZES['std']['cap_h'] + 2 * TK.KEY['bezel']
    block = sh + 2 * 0.55 + 0.9 + kh                          # sheet and its frame, a gap, the keys
    ysh = block / 2 - 0.55 - sh / 2
    fp = os.path.join(OUT, 'take-form-print.png')
    if not os.path.exists(fp): take_form(fp)
    with R.moved(0, ysh, 0): R.sheet(sw, sh, fp, 'take', curl=0.35)
    cm_ = R.SG.black_cast('cardframe')
    for sy in (1, -1):
        ch = R.rbox('cframe', sw + 1.6, 0.9, 0.22, 0.0, 0.08, roll=0.05); ch.location.y = ysh + sy * (sh / 2 + 0.1)
        R.chamfer(ch, 0.012, 1); ch.data.materials.append(cm_)
    R.small_screws([(sx * (sw / 2 + 0.45), ysh + sy * (sh / 2 + 0.1)) for sx in (-1, 1) for sy in (-1, 1)], r=0.17)
    yk = -block / 2 + kh / 2
    x = -sw / 2; keys = []
    for lid in RES_KEYS:
        wk = K.legend_width(LG.LEGENDS[lid][0], 'std') + 2 * TK.KEY['bezel']
        b0 = set(bpy.data.objects)
        with R.moved(x + wk / 2, yk, 0): R.key(lid)
        cap = [o for o in _new_since(b0) if o.name.split('.')[0] == 'cap'][0]
        dn = cap.copy(); bpy.context.scene.collection.objects.link(dn)
        dn.location.z -= 0.12; dn.hide_render = True                # pressed: the cap 1.2 mm down in its well
        keys.append(dict(id=lid, x=x + wk / 2, y=yk, w=wk, h=kh, up=cap, down=dn))
        x += wk + 0.5
    R.engrave('RESULTS', sw / 2 - 2.6, yk, 0.62)
    return s, cam, h, ysh, keys


def unit_results():
    s, cam, h, ysh, keys = build_results()
    L = shoot_base(s, cam, 'rack-results', R.PW, h)
    L['u'] = 7; L['layers'] = {}
    P_ = lambda x, y: TK.proj(s, cam, (x, y, 0.0))
    a, b = P_(-RES_W / 2, ysh + RES_H / 2), P_(RES_W / 2, ysh - RES_H / 2)
    kr = []
    for k in keys:
        p, q = P_(k['x'] - k['w'] / 2, k['y'] + k['h'] / 2), P_(k['x'] + k['w'] / 2, k['y'] - k['h'] / 2)
        kr.append(dict(id=k['id'], rect=[p[0], p[1], q[0], q[1]]))
    L['results'] = dict(sheet=[a[0], a[1], b[0], b[1]], form=FORM, keys=kr)
    LAY['units']['results'] = L; _save()
    for i, k in enumerate(keys):
        k['up'].hide_render = True; k['down'].hide_render = False
        L['layers']['k%d-down' % i] = shoot_crop(s, cam, 'rack-results-k%d-down' % i,
                                                  box_px(s, cam, k['x'], k['y'], k['w'] / 2 + 0.4, k['h'] / 2 + 0.4))
        k['up'].hide_render = False; k['down'].hide_render = True
        _save()


# ---------------------------------------------------------------------------------------------------------------------
# the chart panel (6U): the hook-up drawing and the BEFORE YOU START card, each in its card frame (the third proof's
# unit_chart, approved). Nothing on it changes, so it is rendered whole: a base and no layers.

def unit_chart():
    import ircapture_rack as R_
    K.set_seed('rack-chart')
    s, cam, h = R.unit_scene(6)
    R.backing(h)
    R.rack_panel(6, 'bronze', 'chart')
    dw, dh, cw_, chh = 26.0, 20.0, 14.6, 20.0
    gap_ = 2.2
    xd = -(dw + gap_ + cw_) / 2 + dw / 2; xc = xd + dw / 2 + gap_ + cw_ / 2
    ysh = 0.9
    fd = os.path.join(OUT, 'wiring-print.png'); R.wiring_drawing(fd, dw, dh, px=120)
    fc = os.path.join(OUT, 'card-print.png'); R.instruction_card(fc, cw_, chh, px=120)
    with R.moved(xd, ysh, 0): R.sheet(dw, dh, fd, 'wiring', curl=0.25)
    with R.moved(xc, ysh, 0): R.sheet(cw_, chh, fc, 'card', curl=0.0)
    R.card_frame(dw, dh, ysh, xd, 'cf1'); R.card_frame(cw_, chh, ysh, xc, 'cf2')
    R.engrave('HOOK-UP', -dw / 2 + xd + 2.0, -h / 2 + 1.25, 0.5)
    L = shoot_base(s, cam, 'rack-chart', R.PW, h)
    L['u'] = 6; L['layers'] = {}
    LAY['units']['chart'] = L; _save()


# ---------------------------------------------------------------------------------------------------------------------
# the pre-flight (4U): BEFORE CAPTURE, a printed form in its card frame (the third proof's unit_preflight, approved),
# rendered blank as the take sheet is. The app types each line (the item and its reading), ticks it in pencil, rings a
# line to look at in red pencil (a cross in the OK column when it stops the capture), and pencils a word beside a noisy
# room. PF_FORM is the one place its layout lives (sheet cm, entries by their baselines).

PF_W, PF_H = 40.0, 13.4


def _pf_form():
    m = 1.3; asc = 0.78 * TYPED_CM
    rule, rh, rows = 3.75, 1.25, 7
    return {
        'w': PF_W, 'h': PF_H, 'margin': m, 'typedCm': TYPED_CM, 'advance': 0.6,
        'title': 'BEFORE CAPTURE', 'headY': 2.85, 'rule': rule, 'rowH': rh, 'rows': rows,
        'baseline0': round(rule + 0.27 + asc, 3),
        'cols': [dict(key=k, label=l, x=m + x) for k, l, x in (('item', 'ITEM', 0.0), ('reading', 'READING', 8.6), ('ok', 'OK', 34.6))],
        'right': PF_W - m,
    }


PF_FORM = _pf_form()


def preflight_form(path, px=120):
    """The printed form, nothing typed on it: the take sheet's stock and ink."""
    from PIL import Image, ImageDraw, ImageFont
    import numpy as np
    F_ = PF_FORM; w, h = F_['w'], F_['h']
    W, H = int(w * px), int(h * px)
    im = Image.new('RGB', (W, H), (246, 234, 200)); d = ImageDraw.Draw(im)
    F = lambda name, cm_: ImageFont.truetype(os.path.join(R.FONTS, name), int(cm_ * px))
    ox = (104, 30, 24); rule = (150, 120, 104)
    fh = F('BarlowSemiCondensed-700-normal.ttf', 0.95)
    fl = F('BarlowSemiCondensed-600-normal.ttf', 0.45 / 0.7)              # capitals 0.45 cm: 6.3 pt on screen
    cm = lambda v: int(round(v * px)); hair = max(1, cm(0.02))

    def spaced(x, y, text, font, fill, track=0.14, right=False):
        tr = track * font.size
        if right: x -= sum(font.getlength(c) for c in text) + tr * (len(text) - 1)
        for c in text:
            d.text((x, y), c, font=font, fill=fill); x += font.getlength(c) + tr

    m = F_['margin']; R_ = F_['right']
    spaced(cm(m), cm(0.95), F_['title'], fh, ox)
    spaced(cm(R_), cm(1.3), 'PRE-FLIGHT', fl, ox, 0.16, right=True)
    d.line([(cm(m), cm(2.25)), (cm(R_), cm(2.25))], fill=ox, width=cm(0.07))
    d.line([(cm(m), cm(2.4)), (cm(R_), cm(2.4))], fill=ox, width=hair)
    for c in F_['cols']: spaced(cm(c['x'] + 0.1), cm(F_['headY']), c['label'], fl, rule)
    d.line([(cm(m), cm(F_['rule'])), (cm(R_), cm(F_['rule']))], fill=ox, width=max(1, cm(0.035)))
    for r in range(F_['rows']):
        y = F_['rule'] + (r + 1) * F_['rowH']
        d.line([(cm(m), cm(y)), (cm(R_), cm(y))], fill=rule, width=hair)
    for c in F_['cols'][1:]:
        d.line([(cm(c['x'] - 0.25), cm(F_['headY'] - 0.1)), (cm(c['x'] - 0.25), cm(F_['rule'] + F_['rows'] * F_['rowH']))], fill=rule, width=hair)
    R.age_paper(im, np.random.default_rng(6)).save(path)


def unit_preflight():
    K.set_seed('rack-preflight')
    s, cam, h = R.unit_scene(4)
    R.backing(h)
    R.rack_panel(4, 'bronze', 'preflight')
    ysh = 0.7
    fp = os.path.join(OUT, 'preflight-form-print.png')
    if not os.path.exists(fp): preflight_form(fp)
    with R.moved(0, ysh, 0): R.sheet(PF_W, PF_H, fp, 'preflight', curl=0.25)
    R.card_frame(PF_W, PF_H, ysh)
    R.engrave('PRE-FLIGHT', -PF_W / 2 + 2.2, -h / 2 + 1.1, 0.5)
    L = shoot_base(s, cam, 'rack-preflight', R.PW, h)
    L['u'] = 4; L['layers'] = {}
    P_ = lambda x, y: TK.proj(s, cam, (x, y, 0.0))
    a, b = P_(-PF_W / 2, ysh + PF_H / 2), P_(PF_W / 2, ysh - PF_H / 2)
    L['preflight'] = dict(sheet=[a[0], a[1], b[0], b[1]], form=PF_FORM)
    LAY['units']['preflight'] = L; _save()


# ---------------------------------------------------------------------------------------------------------------------
# the patch unit (2U): the interface's inputs, a three-way bat toggle each (the first proof's unit_patch, approved):
# MIC thrown up, OFF level, REF thrown down. Built once and shot in its states, as the meter bridge:
#   base         inputs 1 to 8, every toggle level (OFF)
#   t<i>-mic     toggle i thrown up            t<i>-ref    toggle i thrown down
#   p<i>         slot i holding a black nylon hole plug in place of its toggle (an interface with fewer inputs)
#   n<i>-b<k>    slot i's number engraved for bank k (k = 1..3: inputs 9 to 16, 17 to 24, 25 to 32), one unit a bank
# Interfaces with more than 32 inputs keep the old inputs grid.

PATCH_N, PATCH_BANKS = 8, 4
PATCH_X0, PATCH_DX, PATCH_TY = -14.6, 4.75, -0.35
PATCH_ROWS = {'mic': 0.85, 'off': -0.35, 'ref': -1.55}        # the legends' centres: where a click throws the toggle
PATCH_THROW = {'mic': 1, 'off': 0, 'ref': -1}
PATCH_DEG = float(os.environ.get('IRC_PATCH_DEG', '30'))          # the throw (the proof's 24 read weakly straight on)


def _toggle(x, y, ch):
    """ircapture_rack.toggle, its parts kept: the bat apart so it can be thrown between shots."""
    with R.moved(x, y, 0):
        nut = R.lathe('tnut', [(0.62, 0.0), (0.62, 0.16), (0.56, 0.2), (0.34, 0.2)], 6, smooth=False); nut.data.materials.append(ch)
        nut.rotation_euler = (0, 0, R.math.radians(30 + 7 * (K.seed_of('tn%.1f' % x) % 5)))
        col = R.lathe('tcol', [(0.36, 0.0), (0.36, 0.42), (0.3, 0.5), (0.16, 0.5)], 48); col.data.materials.append(ch)
        bat = R.lathe('tbat', [(0.13, 0.0), (0.16, 0.6), (0.21, 1.4), (0.25, 1.85), (0.24, 2.05), (0.15, 2.18), (0.0, 2.2)], 48)
        bat.data.materials.append(ch)
        bat.location = (0, 0, 0.3)
    return [nut, col], bat


def _plug(x, y):
    """A black nylon snap-in hole plug: a low dome on a thin flange."""
    m = R.mat('plug', R.srgb('#0d0c0b'), rough=0.45, spec=0.35)
    p = R.lathe('plug', [(0.58, 0.0), (0.58, 0.05), (0.52, 0.08), (0.45, 0.16), (0.3, 0.21), (0.0, 0.23)], 64)
    p.location = (x, y, 0); p.data.materials.append(m)
    p.hide_render = True
    return p


def unit_patch():
    K.set_seed('rack-patch')
    s, cam, h = R.unit_scene(2)
    R.backing(h)
    R.rack_panel(2, 'black', 'patch')
    R.engrave('INPUTS', -19.4, 2.6, 0.5)
    ch = R.SG.nickel('tgl', seed=4)
    slots = []
    for i in range(PATCH_N):
        x = PATCH_X0 + i * PATCH_DX
        fixed, bat = _toggle(x, PATCH_TY, ch)
        nums = [R.engrave(str(k * PATCH_N + i + 1), x, 2.6, 0.62) for k in range(PATCH_BANKS)]
        for o in nums[1:]: o.hide_render = True
        R.engrave('MIC', x + 1.55, PATCH_ROWS['mic'], 0.44, track=0.12); R.engrave('OFF', x + 1.55, PATCH_ROWS['off'], 0.44, track=0.12)
        R.engrave('REF', x + 1.55, PATCH_ROWS['ref'], 0.44, track=0.12)
        slots.append(dict(x=x, fixed=fixed, bat=bat, nums=nums, plug=_plug(x, PATCH_TY)))
    L = shoot_base(s, cam, 'rack-patch', R.PW, h)
    L['u'] = 2; L['layers'] = {}
    P_ = lambda x, y: TK.proj(s, cam, (x, y, 0.0))
    L['patch'] = dict(n=PATCH_N, banks=PATCH_BANKS,
                      toggles=[P_(sl['x'], PATCH_TY) for sl in slots],
                      rows={k: P_(0, y)[1] for k, y in PATCH_ROWS.items()},
                      column=[P_(-PATCH_DX / 2, 0)[0], P_(PATCH_DX / 2, 0)[0]])
    LAY['units']['patch'] = L; _save()
    for i, sl in enumerate(slots):
        x = sl['x']
        box = box_px(s, cam, x, PATCH_TY - 0.1, 1.4, 1.75)
        for k in ('mic', 'ref'):
            sl['bat'].rotation_euler = (R.math.radians(-PATCH_DEG * PATCH_THROW[k]), 0, 0)
            L['layers']['t%d-%s' % (i, k)] = shoot_crop(s, cam, 'rack-patch-t%d-%s' % (i, k), box)
            sl['bat'].rotation_euler = (0, 0, 0); _save()
        for o in sl['fixed'] + [sl['bat']]: o.hide_render = True
        sl['plug'].hide_render = False
        L['layers']['p%d' % i] = shoot_crop(s, cam, 'rack-patch-p%d' % i, box)
        sl['plug'].hide_render = True
        for o in sl['fixed'] + [sl['bat']]: o.hide_render = False
        _save()
        nb = box_px(s, cam, x, 2.6, 0.9, 0.6)
        for k in range(1, PATCH_BANKS):
            sl['nums'][0].hide_render = True; sl['nums'][k].hide_render = False
            L['layers']['n%d-b%d' % (i, k)] = shoot_crop(s, cam, 'rack-patch-n%d-b%d' % (i, k), nb)
            sl['nums'][k].hide_render = True; sl['nums'][0].hide_render = False
            _save()


# ---------------------------------------------------------------------------------------------------------------------
# the NAM meter bridge (3U): the third proof's unit_nammeters, built once with its live parts switchable
#
# Four graphite channel modules in a graphite frame. Each: twenty LED bars, -40 to 0 dBFS in 2 dB steps (green to -6,
# amber to -2, red) behind smoked glass; the peak on four red seven-segment LED cells behind a red filter; LOW / OK /
# HIGH / CLIP as flush LEDs; the scribble strip. The LEDs are the saturated kind (flush_led's sat, the NAM step strip's):
# the emission nearly a primary, hotter in the middle of each bar or segment than at its edge.
#   base        every bar, segment and LED dark, the strips blank
#   m<i>-bars   module i's twenty bars all lit: the app shows the bars up to the level (and the peak-hold bar) through
#               a mask of their columns, as a real bargraph lights a run of bars
#   m<i>-dig    module i's cells with every segment and point lit: the app shows the lit segments through a mask of
#               their outlines (`cells` in irc-rack.json), as the gas digits are lit on the render's geometry
#   m<i>-l<k>   module i's LED k (LOW OK HIGH CLIP)
#   b<i>        a blank filler plate in slot i (taken whole by the post)

NBAR = dict(n=20, w=0.34, h=1.25, pitch=0.465)
NDIG = dict(n=4, hgt=1.4, x=-1.85, win=(6.3, 2.2))
NAM_SLOTS = [('N1', 'a'), ('N2', 'b'), ('N3', 'c'), ('N4', 'd')]
NAM_LED_K = float(os.environ.get('IRC_NAM_LED_K', '0.6'))      # the flush LEDs (as the NAM step strip)
NAM_BAR_K = float(os.environ.get('IRC_NAM_BAR_K', '4.2'))      # the bars: behind smoked glass
NAM_DIG_K = float(os.environ.get('IRC_NAM_DIG_K', '1.6'))      # the digits: behind the red filter
SAT_HOT = {'green': '#08ff26', 'amber': '#ff8a00', 'red': '#ff1000'}
SAT_DARK = {'green': '#07120a', 'amber': '#150b04', 'red': '#170504'}


def _sat_mat(name, col, on, k, rx, ry):
    """A saturated LED's diffuser (flush_led's sat, for a bar or a segment rx x ry cm half-sizes): dark resin; lit, the
    emission nearly a primary, 1.35 k at the middle falling to 0.55 k at the edges, a faint mottle in the diffuser."""
    m = R.mat(name, R.srgb(SAT_DARK[col]), rough=0.3, coat=0.3, coat_rough=0.08,
              emit=R.srgb(SAT_HOT[col]) if on else None, emit_strength=k if on else 0.0)
    if on:
        nt = m.node_tree; b = nt.nodes['Principled BSDF']; co = R.obj_coords(nt)
        sep = R.node(nt, 'ShaderNodeSeparateXYZ'); nt.links.new(co, sep.inputs[0])
        dx = R.node(nt, 'ShaderNodeMath', operation='DIVIDE'); nt.links.new(sep.outputs['X'], dx.inputs[0]); dx.inputs[1].default_value = rx
        dy = R.node(nt, 'ShaderNodeMath', operation='DIVIDE'); nt.links.new(sep.outputs['Y'], dy.inputs[0]); dy.inputs[1].default_value = ry
        cxy = R.node(nt, 'ShaderNodeCombineXYZ'); nt.links.new(dx.outputs[0], cxy.inputs['X']); nt.links.new(dy.outputs[0], cxy.inputs['Y'])
        ln = R.node(nt, 'ShaderNodeVectorMath', operation='LENGTH'); nt.links.new(cxy.outputs[0], ln.inputs[0])
        st = R.node(nt, 'ShaderNodeMapRange', **{'From Min': 0.0, 'From Max': 1.0, 'To Min': 1.35 * k, 'To Max': 0.55 * k})
        st.interpolation_type = 'SMOOTHSTEP'; nt.links.new(ln.outputs['Value'], st.inputs['Value'])
        mt = R.node(nt, 'ShaderNodeMapRange', **{'From Min': 0.3, 'From Max': 0.7, 'To Min': 0.9, 'To Max': 1.08})
        nt.links.new(R.noise(nt, co, 90.0, 2.0, 0.5), mt.inputs['Value'])
        mm = R.node(nt, 'ShaderNodeMath', operation='MULTIPLY'); nt.links.new(st.outputs['Result'], mm.inputs[0]); nt.links.new(mt.outputs['Result'], mm.inputs[1])
        nt.links.new(mm.outputs[0], b.inputs['Emission Strength'])
    return m


def _nam_bars(plate, cx, cy, name):
    """bargraph() with its bars switchable: returns (bars [(object, lit material, dark material, x)], window w, h)."""
    n, bw, bh, pp = NBAR['n'], NBAR['w'], NBAR['h'], NBAR['pitch']
    ww, wh = n * pp + 0.5, bh + 0.7
    ho = R.rbox('bgh', ww, wh, R.T + 2, -R.T - 1, 0.08); ho.location = (cx, cy, 0)
    bpy.context.view_layer.update(); R.cut(plate, ho)
    bz = R.rbox('bgbz', ww + 0.8, wh + 0.8, 0.16, 0.0, 0.14, roll=0.05); bz.location = (cx, cy, 0)
    R.cut(bz, R.prism('bgbh', [(px + cx, py + cy, pz) for px, py, pz in R._rring(ww / 2, wh / 2, 0.08, 0.0, 0, n_arc=8)], -2, 2))
    R.chamfer(bz, 0.015, 2); bz.data.materials.append(R.SG.black_cast('bgbz' + name))
    bk = R.rbox('bgback', ww, wh, 0.05, -0.75, 0.0); bk.location = (cx, cy, 0)
    bk.data.materials.append(R.mat('bgback', R.srgb('#070707'), rough=0.7))
    ms = {}
    bars = []
    for i in range(n):
        c = R.bar_colour(i)
        if c not in ms:
            ms[c] = (_sat_mat('nbar-on-' + c, c, True, NAM_BAR_K, bw / 2, bh / 2), _sat_mat('nbar-off-' + c, c, False, 0, bw / 2, bh / 2))
        o = R.rbox('bar', bw, bh, 0.06, -0.7, 0.03); x = cx - (n - 1) * pp / 2 + i * pp; o.location = (x, cy, 0)
        o.data.materials.append(ms[c][1])
        bars.append((o, ms[c][0], ms[c][1], x))
    g = R.rbox('smoke', ww + 0.1, wh + 0.1, 0.05, -0.1, 0.0); g.location = (cx, cy, 0)
    g.data.materials.append(R.mat('smoke', R.srgb('#6a665e'), rough=0.05, transm=1.0, ior=1.0, spec=0.0))
    g.visible_shadow = False; R.GLASS.append(g)
    return bars, ww + 0.8, wh + 0.8


def _nam_cells(cx, cy, z, on_m, off_m):
    """led_digits() with every segment kept: four cells, all segments dark. Returns the segments [(object, outline)]
    (outline: the segment's corners in world cm) and each cell's segments by name (a..g, p)."""
    hgt = NDIG['hgt']; n = NDIG['n']
    pitch = hgt * 0.74; w = hgt * 0.5; t = hgt * 0.12; sl = R.math.tan(R.math.radians(8))
    x0 = cx - pitch * (n - 1) / 2
    segs, cells = [], []
    for i in range(n):
        x_ = x0 + i * pitch
        cell = {}
        geo = {'a': (0, hgt / 2, True), 'g': (0, 0, True), 'd': (0, -hgt / 2, True),
               'f': (-w / 2, hgt / 4, False), 'b': (w / 2, hgt / 4, False), 'e': (-w / 2, -hgt / 4, False), 'c': (w / 2, -hgt / 4, False)}
        for k_, (sx, sy, horiz) in geo.items():
            sw_, sh_ = (w - t, t) if horiz else (t, hgt / 2 - t)
            o = R.rbox('seg', sw_, sh_, 0.02, z, t * 0.45)
            ox_, oy_ = x_ + sx + sy * sl, cy + sy
            o.location = (ox_, oy_, 0)
            corners = [(-sw_ / 2, -sh_ / 2), (sw_ / 2, -sh_ / 2), (sw_ / 2, sh_ / 2), (-sw_ / 2, sh_ / 2)]
            if not horiz:
                for v in o.data.vertices: v.co.x += v.co.y * sl
                corners = [(px + py * sl, py) for px, py in corners]
            o.data.materials.append(off_m)
            cell[k_] = len(segs); segs.append((o, [(ox_ + px, oy_ + py) for px, py in corners]))
        s_ = t * 1.1; px_, py_ = x_ + w / 2 + t * 1.4 - hgt / 2 * sl, cy - hgt / 2
        o = R.rbox('dp', s_, s_, 0.02, z, t * 0.5); o.location = (px_, py_, 0)
        o.data.materials.append(off_m)
        cell['p'] = len(segs); segs.append((o, [(px_ - s_ / 2, py_ - s_ / 2), (px_ + s_ / 2, py_ - s_ / 2), (px_ + s_ / 2, py_ + s_ / 2), (px_ - s_ / 2, py_ + s_ / 2)]))
        cells.append(cell)
    return segs, cells


def _nam_module(name, v, ox):
    """ircapture_rack.nam_module at rest, its live parts kept."""
    MW, MZ, NMH = R.MW, R.MZ, R.NMH
    K.set_seed('rack-nmod-' + name)
    before = set(bpy.data.objects)
    with R.moved(ox, 0, MZ):
        pl = R.rbox('nplate', MW, NMH, MZ, -MZ, 0.18, roll=0.05)
        yb = NMH / 2 - 1.65
        bars, bgw, bgh = _nam_bars(pl, 0.0, yb, name)
        yp = yb - bgh / 2 - 1.15 - 1.4
        pw_, ph_ = NDIG['win']
        zd = R.red_window(pl, NDIG['x'], yp, pw_, ph_, name)
        R.chamfer(pl, 0.015, 2); TK.flat_faces(pl)
        pl.data.materials.append(K.anodised('nmod-' + name, base='#2e2e30'))
        R.small_screws([(sx * (MW / 2 - 0.45), sy * (NMH / 2 - 0.45)) for sx in (-1, 1) for sy in (-1, 1)], seed=K.seed_of(name) % 7)
        t = NDIG['hgt'] * 0.12
        on_m = _sat_mat('dseg-on', 'red', True, NAM_DIG_K, t / 2, t / 2)
        off_m = R.mat('dseg-off', R.srgb('#1a0605'), rough=0.3, coat=0.5, coat_rough=0.05)
        segs, cells = _nam_cells(NDIG['x'], yp, zd, on_m, off_m)
        n, pp = NBAR['n'], NBAR['pitch']
        for db in (-40, -20, -12, -8, -4, 0):
            i = (db + 40) / 2 - 0.5
            x = -(n - 1) * pp / 2 + i * pp
            R.engrave(str(db), max(-(n - 1) * pp / 2, min((n - 1) * pp / 2, x)), yb - bgh / 2 - 0.5, 0.38, track=0.06)
        R.engrave('PEAK  dBFS', NDIG['x'], yp - ph_ / 2 - 0.9, 0.44, track=0.14)
        leds = []
        for i, (lab, col) in enumerate(R.NLAMPS):
            lx = 2.85 + (i % 2) * 1.7; ly = yp + 0.62 - (i // 2) * 1.55
            b0 = set(bpy.data.objects)
            R.flush_led(lx, ly, col, True, k=NAM_LED_K, sat=True)
            lens = [o for o in _new_since(b0) if o.name.startswith('led') and not o.name.startswith('ledcol')][0]
            hot = lens.data.materials[0]
            dark = R.mat('ledS%s-dark' % col, R.srgb({'green': '#0c2010', 'amber': '#2a1606', 'red': '#2a0806'}[col]),
                         rough=0.32, coat=0.3, coat_rough=0.08)
            lens.data.materials[0] = dark
            leds.append(dict(lens=lens, hot=hot, dark=dark, x=ox + lx, y=ly))
            R.engrave(lab, lx, ly - 0.62, 0.38, track=0.1)
        ys = -NMH / 2 + 0.55 + K.SCRIB['h'] / 2
        with R.moved(0, ys, 0): R.strip(v, 10.2, '', name)
    return dict(x=ox, bars=[(o, a, b, x + ox) for o, a, b, x in bars], yb=yb, bar_h=NBAR['h'],
                segs=[(o, [(px + ox, py) for px, py in pts]) for o, pts in segs], cells=cells, on_m=on_m, off_m=off_m,
                yp=yp, leds=leds, ys=ys, strip_len=10.2, objs=_new_since(before))


def _nam_blank(name, ox):
    K.set_seed('rack-nblank-' + name)
    b0 = set(bpy.data.objects)
    with R.moved(ox, 0, R.MZ):
        pl = R.rbox('nplate', R.MW, R.NMH, R.MZ, -R.MZ, 0.18, roll=0.05)
        R.chamfer(pl, 0.015, 2); TK.flat_faces(pl); pl.data.materials.append(K.anodised('nblank-' + name, base='#2a2a2c'))
        R.small_screws([(sx * (R.MW / 2 - 0.45), sy * (R.NMH / 2 - 0.45)) for sx in (-1, 1) for sy in (-1, 1)], seed=K.seed_of(name) % 7 + 2)
    bl = _new_since(b0)
    for o in bl: o.hide_render = True
    return bl


def build_nammeters():
    K.set_seed('rack-nmeters')
    s, cam, h = R.unit_scene(3)
    R.backing(h)
    fr, hh = R.rack_panel(3, 'alu', 'nbridge')
    op = R.rbox('fopen', 4 * R.MW + 0.1, R.NMH - 0.6, 4, -2, 0.1); bpy.context.view_layer.update(); R.cut(fr, op)
    fr.data.materials.append(K.anodised('nbridge', base='#232325'))
    mods, blanks = [], []
    for i, (nm, v) in enumerate(NAM_SLOTS):
        ox = (i - 1.5) * (R.MW + 0.06)
        mods.append(_nam_module(nm, v, ox))
        blanks.append(_nam_blank(nm, ox))
    R.finish_glass()
    return s, cam, h, mods, blanks


def _nam_light(m_, what, on):
    if what == 'bars':
        for o, hot, dark, _ in m_['bars']: o.data.materials[0] = hot if on else dark
    elif what == 'dig':
        for o, _ in m_['segs']: o.data.materials[0] = m_['on_m'] if on else m_['off_m']


def unit_nammeters():
    s, cam, h, mods, blanks = build_nammeters()
    if os.environ.get('IRC_NAM_TEST'):                         # every live part lit, for judging the brightness
        for m_ in mods:
            _nam_light(m_, 'bars', True); _nam_light(m_, 'dig', True)
            for Ld in m_['leds']: Ld['lens'].data.materials[0] = Ld['hot']
        shoot_base(s, cam, 'rack-nammeters-test', R.PW, h); return
    L = shoot_base(s, cam, 'rack-nammeters', R.PW, h)
    L['u'] = 3; L['layers'] = {}
    LAY['units']['nammeters'] = L; _save()
    P_ = lambda x, y: TK.proj(s, cam, (x, y, 0.0))
    info = []
    for m_ in mods:
        bw2, bh2 = NBAR['pitch'] / 2, m_['bar_h'] / 2
        bars = []
        for _, _, _, x in m_['bars']:
            a, b = P_(x - bw2, m_['yb'] + bh2), P_(x + bw2, m_['yb'] - bh2)
            bars.append([a[0], a[1], b[0], b[1]])
        segs = [[P_(px, py) for px, py in pts] for _, pts in m_['segs']]
        sa = P_(m_['x'] - m_['strip_len'] / 2, m_['ys'] + K.SCRIB['h'] / 2); sb = P_(m_['x'] + m_['strip_len'] / 2, m_['ys'] - K.SCRIB['h'] / 2)
        info.append(dict(bars=bars, segs=segs, cells=m_['cells'], leds=[P_(Ld['x'], Ld['y']) for Ld in m_['leds']],
                         strip=[sa[0], sa[1], sb[0], sb[1]]))
    L['nammeters'] = dict(modules=info, lamps=[l for l, _ in R.NLAMPS], db0=-40.0, dbStep=2.0,
                          colours=[R.bar_colour(i) for i in range(NBAR['n'])])
    _save()
    bw = (NBAR['n'] * NBAR['pitch'] + 0.5) / 2 + 0.6
    for i, m_ in enumerate(mods):
        _nam_light(m_, 'bars', True)
        L['layers']['m%d-bars' % i] = shoot_crop(s, cam, 'rack-nammeters-m%d-bars' % i, box_px(s, cam, m_['x'], m_['yb'], bw, 1.6))
        _nam_light(m_, 'bars', False); _save()
        _nam_light(m_, 'dig', True)
        L['layers']['m%d-dig' % i] = shoot_crop(s, cam, 'rack-nammeters-m%d-dig' % i,
                                                box_px(s, cam, m_['x'] + NDIG['x'], m_['yp'], NDIG['win'][0] / 2 + 0.3, NDIG['win'][1] / 2 + 0.3))
        _nam_light(m_, 'dig', False); _save()
        for k, Ld in enumerate(m_['leds']):
            Ld['lens'].data.materials[0] = Ld['hot']
            L['layers']['m%d-l%d' % (i, k)] = shoot_crop(s, cam, 'rack-nammeters-m%d-l%d' % (i, k), box_px(s, cam, Ld['x'], Ld['y'], 0.9, 0.9))
            Ld['lens'].data.materials[0] = Ld['dark']; _save()
    for i, m_ in enumerate(mods):
        hidden = []
        for o in m_['objs']:
            if not o.hide_render: o.hide_render = True; hidden.append(o)
        for o in blanks[i]: o.hide_render = False
        L['layers']['b%d' % i] = shoot_crop(s, cam, 'rack-nammeters-b%d' % i, box_px(s, cam, m_['x'], 0.0, R.MW / 2 + 0.6, R.NMH / 2 + 0.6))
        for o in blanks[i]: o.hide_render = True
        for o in hidden: o.hide_render = False
        _save()


UNITS = {'step-cab': unit_step_cab, 'step-nam': unit_step_nam, 'cheeks': unit_cheeks, 'meters': unit_meters,
         'results': unit_results, 'chart': unit_chart, 'preflight': unit_preflight, 'patch': unit_patch,
         'nammeters': unit_nammeters}


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    for u in WHAT.split(','):
        t = time.time(); UNITS[u](); print('unit', u, '%.0fs' % (time.time() - t), flush=True)
