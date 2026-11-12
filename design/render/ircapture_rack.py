# ircapture_rack.py: the rack bay, straight on (2026-11-11, proof).
#
# Lowell, 11-11: the alphanumeric readouts "need work ... some are nice displays and some are still digits on the
# screen"; the visuals should "make sense as in maybe someone would actually hodgepodge a real audio rack together that
# way" and in perspective: "more straight on for stuff that scrolls vertically". So the scrolling area becomes a 19 inch
# rack bay, every step a whole-U unit bolted in, seen straight on (elevation 0), in the Tools studio (the same lights and
# room as every IR Capture piece). One scale: 14 pt a cm (a 19 inch panel 676 pt wide; the window's minimum is 780 pt).
#
# This script renders each unit WHOLE, with its live parts baked in (needles, lit lamps, digits, typed sheet), as a proof
# for Lowell to judge the idea. For the app the same builders are to be split into a base picture and live layers.
#
#   step      1U  the job's steps: four jewel lamps and engraved legends
#   patch     2U  the interface's inputs: a three-way toggle each (MIC / OFF / REF)
#   meters    5U  the meter bridge: four channel modules (VU, peak dBFS on gas digits, noise eye, lamp row, scribble strip)
#   gap       1U  an empty space: the rails and their holes, the dark inside
#   results   7U  a chart panel: the typed take sheet in a card frame, FINDER and RE-EXPORT keys
#
#   FONTS_DIR=Resources/SwellKit/fonts ~/bvenv/bin/python design/render/ircapture_rack.py <out> <unit[,unit]|all> [px/cm] [samples]
# Units: 1 = 1 cm; a unit's panel face is z = 0 (module plates stand in front of it), y up, the unit centred on the origin.
import sys, os, math, json, time
_argv = sys.argv[:]
OUT = _argv[1] if len(_argv) > 1 else '/tmp/ircrack'
WHAT = _argv[2] if len(_argv) > 2 else 'all'
PXCM = float(_argv[3]) if len(_argv) > 3 else 28.0
SAMPLES = int(_argv[4]) if len(_argv) > 4 else 32
sys.argv = [_argv[0], OUT, 'rack', str(PXCM), str(SAMPLES)]
import ircapture_kit as K
sys.argv = [_argv[0], OUT, str(PXCM), str(SAMPLES)]
import ircapture_vu as V
sys.argv = _argv
import bpy
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import toolkit as TK
import shelf_gear as SG
import parts as P
import gas_disp as GD
from parts import mat, srgb, lathe, _rring
from gear_kit import rbox, cut, chamfer, node, mix_into, noise, mul, add_bump, surface_wear, obj_coords, cyl_cutter, screw
from instrument import grimy, prism
for M in (TK, K, V):
    M.OUT, M.PXCM, M.SAMPLES = OUT, PXCM, SAMPLES
os.makedirs(OUT, exist_ok=True)
FONTS = V.FONTS
ELEV = float(os.environ.get('IRC_RACK_ELEV', '0'))
TK.ELEV = ELEV; K.use_elev(ELEV)

U = 4.445
PW = 48.26                      # a 19 inch panel
EAR_X = 23.255                  # the rails' hole centres, 46.51 cm apart
T = 0.3                         # panel stock
PT = 14.0                       # points a cm on screen
GLOSS_OFF = tuple(os.environ.get('IRC_RACK_GLOSS_OFF', 'top,topL').split(','))
LAY = {'pxcm': PXCM, 'elev': ELEV, 'samples': SAMPLES, 'pt_per_cm': PT, 'out': {}}


# ---------------------------------------------------------------------------------------------------------------------
# helpers

class moved:
    """Everything made inside is built about the origin with its panel face at z = 0, then moved by (dx, dy, dz)."""
    def __init__(self, dx=0.0, dy=0.0, dz=0.0): self.d = (dx, dy, dz)
    def __enter__(self): self.before = set(bpy.data.objects); return self
    def __exit__(self, *a):
        bpy.context.view_layer.update()
        for o in set(bpy.data.objects) - self.before:
            if o.parent is None:
                o.location.x += self.d[0]; o.location.y += self.d[1]; o.location.z += self.d[2]


def unit_scene(u, pad=0.35, w=PW):
    h = u * U
    s, cam = TK.scene(w, h, pad)
    # straight on, a flat glossy face mirrors what is right in front of it: the studio's top softbox (z 250, nearly on the
    # camera's axis), which washed the panel to a pale grey. It still lights; it is only not seen in reflections (as the
    # shelf from below, ircapture_kit.scene_now). The room in the world still is.
    for o in s.objects:
        if o.name.split('.')[0] in GLOSS_OFF:
            try: o.visible_glossy = False
            except Exception: pass
    return s, cam, h


def shoot(s, cam, name, w, h, extra=None):
    bpy.context.view_layer.update()
    lay = {'size': [s.render.resolution_x, s.render.resolution_y], 'cm': [w, h],
           'tl': TK.proj(s, cam, (-w / 2, h / 2, 0.0)), 'br': TK.proj(s, cam, (w / 2, -h / 2, 0.0))}
    if extra: lay.update(extra)
    t = time.time(); P.render(s, os.path.join(OUT, name + '.png')); lay['s'] = round(time.time() - t, 1)
    LAY['out'][name] = lay
    json.dump(LAY, open(os.path.join(OUT, 'rack-%s.json' % name), 'w'), indent=1)


def backing(h, w=PW):
    """The dark inside of the rack behind a unit, seen only through its openings (no shadow catcher: a catcher plane at
    the panel's back cut through the displays behind it)."""
    b = rbox('inside', w - 0.5, h - 0.5, 0.1, -11.0, 0.01); b.data.materials.append(mat('inside', srgb('#050505'), rough=0.9)); return b


def slot_cutter(x, y, w=1.0, h=0.62):
    c = prism('slot', _rring(w / 2, h / 2, h / 2 - 0.01, 0.0, 0, n_arc=10), -2, 2); c.location = (x, y, 0); return c


def rack_panel(u, finish='bronze', name='unit', w=PW):
    """A rack panel u units tall (less the usual 0.8 mm), its ears slotted, a rack screw with a cup washer in each slot."""
    h = u * U - 0.08
    o = rbox(name, w, h, T, -T, 0.12, roll=0.06)
    ys = [h / 2 - 0.635 - 0.04, -(h / 2 - 0.635 - 0.04)] if u > 1 else [0.0]
    if u >= 4:
        yi = h / 2 - 0.675 - U * ((u - 1) // 2)
        ys = [h / 2 - 0.675, yi, -yi, -(h / 2 - 0.675)]
    for sx in (-1, 1):
        for y in ys:
            bpy.context.view_layer.update(); cut(o, slot_cutter(sx * EAR_X, y))
    chamfer(o, 0.015, 2); TK.flat_faces(o)
    if finish == 'bronze': o.data.materials.append(K.hammertone_fine(name='hf-' + name))
    elif finish == 'black': o.data.materials.append(wrinkle_black('wr-' + name))
    elif finish == 'grey': o.data.materials.append(K.hammertone_fine(base='#191612', name='hg-' + name))
    ni = TK.nickel(); wm = mat('cupw', srgb('#0f0e0d'), rough=0.55, spec=0.3)
    for sx in (-1, 1):
        for y in ys:
            wsh = lathe('cup', [(0.62, 0.0), (0.62, 0.03), (0.52, 0.09), (0.36, 0.1), (0.34, 0.02)], 64)
            wsh.location = (sx * EAR_X, y, 0); wsh.data.materials.append(wm)
            with moved(0, 0, 0.03): screw(sx * EAR_X, y, ni)
    return o, h


def wrinkle_black(name):
    m = mat(name, srgb('#121110'), rough=0.5, spec=0.35)
    nt = m.node_tree; co = obj_coords(nt)
    add_bump(m, noise(nt, co, 34.0, 4.0, 0.7), 0.35, 0.006)
    mix_into(m, 'Roughness', mul(nt, noise(nt, co, 2.0, 3.0, 0.6, lo=0.35, hi=0.7), 0.4), 0.38, 'FLOAT')
    surface_wear(m, dust=0.35, smudge=0.3, scuff=0.3)
    return grimy(m, dirt='#2a2620', amount=0.3, dist=0.1)


def engrave(text, x, y, cap_cm, z=0.0, color='#d8d0bd', track=0.16, kind='cap', wear=True):
    """A legend engraved and filled on a face at z, centred on (x, y), its capitals cap_cm tall (shelf_gear.engrave_ink)."""
    f = SG.font(kind, 200); capH = f.getbbox('H')[3] - f.getbbox('H')[1]
    wsum = (sum(f.getlength(c) for c in text) / capH + track * (len(text) - 1)) * cap_cm
    wcm = wsum / 0.8 + 0.2; hcm = cap_cm * 2.2
    mk = SG.legend_mask(text, wcm, hcm, cap_cm, ppcm=max(120, int(3 * PXCM)), track=track, kind=kind)
    bpy.ops.mesh.primitive_plane_add(size=1, location=(x, y, z + 0.004)); o = bpy.context.active_object; o.name = 'engr'
    o.scale = (wcm, hcm, 1); bpy.ops.object.transform_apply(scale=True)
    m = mat('engr', srgb(color), rough=0.6, spec=0.3); nt = m.node_tree; b = nt.nodes['Principled BSDF']
    t = SG.img_tex(nt, 'engrm', mk, False, 'CLIP')
    uv = nt.nodes.new('ShaderNodeTexCoord'); nt.links.new(uv.outputs['UV'], t.inputs['Vector'])
    co = obj_coords(nt)
    a = mul(nt, t.outputs['Color'], noise(nt, co, 30.0, 3.0, 0.6, lo=-0.5 if not wear else 0.12, hi=0.34)) if wear else t.outputs['Color']
    nt.links.new(a, b.inputs['Alpha'])
    mix_into(m, 'Base Color', mul(nt, noise(nt, co, 12.0, 3.0, 0.6, lo=0.4, hi=0.8), 0.35), (*srgb('#8f8572'), 1))
    try: m.blend_method = 'HASHED'
    except Exception: pass
    o.data.materials.append(m); o.visible_shadow = False
    return o


LAMP = {'green': ('#0c2a12', '#18f060', '#30ff60'), 'amber': ('#4a2606', '#ff9418', '#ffa040'), 'red': ('#3c0705', '#ff2410', '#ff4030'),
        'white': ('#3a3428', '#ffe2b0', '#ffd9a0')}


def jewel(x, y, colour, lit, r=0.5, z=0.0):
    """A pilot lamp: a dull nickel bezel and a faceted glass jewel (shelf_gear.piece_lamp's), lit or dark."""
    sc = r / 0.92
    bz = lathe('jbezel', [(0.92, 0.0), (0.92, 0.2), (0.88, 0.26), (0.76, 0.28), (0.7, 0.36), (0.66, 0.42), (0.6, 0.43),
                          (0.56, 0.38), (0.55, 0.2)], 120,
               lambda t, i, rr, zz: 1.0 - 0.025 * (0.5 + 0.5 * math.cos(40 * t)) ** 2 if i in (1, 2) else 1.0)
    bz.location = (x, y, z); bz.scale = (sc, sc, sc); bz.data.materials.append(SG.nickel('jbez', seed=int(abs(x * 7 + y * 3)) % 9))
    dark, hot, glow = LAMP[colour]
    lens = mat('lens' + colour + str(lit), srgb(dark), rough=0.3, coat=0.5, coat_rough=0.03, spec=0.4)
    nt = lens.node_tree; b = nt.nodes['Principled BSDF']; co = obj_coords(nt)
    add_bump(lens, noise(nt, co, 26.0 / sc, 3.0, 0.6, lo=0.25, hi=0.75), 0.2, 0.002)
    if lit:
        b.inputs['Emission Color'].default_value = (*srgb(hot), 1)
        off = node(nt, 'ShaderNodeVectorMath', operation='SUBTRACT'); off.inputs[1].default_value = (0.0, 0.12, 0.0)
        nt.links.new(co, off.inputs[0])
        ln = node(nt, 'ShaderNodeVectorMath', operation='LENGTH'); nt.links.new(off.outputs[0], ln.inputs[0])
        st = node(nt, 'ShaderNodeMapRange', **{'From Min': 0.0, 'From Max': 0.6, 'To Min': 1.5, 'To Max': 0.55})
        st.interpolation_type = 'SMOOTHSTEP'; nt.links.new(ln.outputs['Value'], st.inputs['Value'])
        nt.links.new(st.outputs['Result'], b.inputs['Emission Strength'])
        Lp = bpy.data.lights.new('lglow', 'POINT'); Lp.energy = 0.35 * sc * sc * 2.2; Lp.color = srgb(glow); Lp.shadow_soft_size = 0.3 * sc
        g = bpy.data.objects.new('lglow', Lp); bpy.context.scene.collection.objects.link(g); g.location = (x, y, z + 0.9 * sc)
    o = lathe('jlens', [(0.56, 0.2), (0.56, 0.34), (0.45, 0.4), (0.25, 0.45), (0.0, 0.47)], 96)
    o.location = (x, y, z); o.scale = (sc, sc, sc); o.data.materials.append(lens)


# ---------------------------------------------------------------------------------------------------------------------
# parts (each built about the origin, its mounting face z = 0; wrap in moved() to place it)

def small_screws(pts, r=0.19, seed=3):
    RA = K._RackAdapter(T, OUT); m = SG.nickel('sscrew', seed=seed)
    for x, y in pts: RA.phillips(x, y, 0.0, r, m, 'pscrew')


def vu(db, lit=True, name='vu'):
    """ircapture_vu.py's meter with its needle in place at db VU."""
    K.set_seed('vu-' + name)
    BZ, WIN = V.BZ, V.WIN
    bz = rbox('vubezel', BZ['w'], BZ['h'], BZ['d'], 0.0, BZ['r'], roll=BZ['roll'])
    hole = rbox('vuhole', WIN['w'], WIN['h'], 4.0, -2.0, WIN['r']); hole.location.y = WIN['y']
    bpy.context.view_layer.update(); cut(bz, hole); chamfer(bz, 0.02, 2); TK.flat_faces(bz)
    bz.data.materials.append(V.phenolic('vubezel-' + name))
    well = rbox('vuwell', WIN['w'] + 0.3, WIN['h'] + 0.3, 0.3, V.Z_FACE - 0.33, 0.2); well.location.y = WIN['y']
    well.data.materials.append(mat('vuwell', srgb('#0e0d0c'), rough=0.7))
    cw, ch = WIN['w'] + 0.2, WIN['h'] + 0.2
    fp = os.path.join(OUT, 'vu-face-print.png')
    if not os.path.exists(fp): V.face_png(fp, cw, ch)
    bpy.ops.mesh.primitive_plane_add(size=1, location=(0, WIN['y'], V.Z_FACE)); card = bpy.context.active_object
    card.name = 'vucard'; card.scale = (cw, ch, 1); bpy.ops.object.transform_apply(scale=True)
    card.data.materials.append(V.card_material(fp, cw, ch, lit))
    gl = rbox('vuglass', WIN['w'] + 0.12, WIN['h'] + 0.12, 0.14, V.Z_GLASS - 0.14, WIN['r']); gl.location.y = WIN['y']
    chamfer(gl, 0.012, 1); TK.flat_faces(gl); gl.data.materials.append(V.glass_mat()); gl.visible_shadow = False
    GLASS.append(gl)
    nm = mat('vuneedle', srgb('#121110'), rough=0.42, spec=0.35)
    a = math.radians(V.vu_angle(max(-22.0, min(3.4, db))))
    Ln = V.NEEDLE_L + 0.4
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, V.Z_NEEDLE)); nd = bpy.context.active_object
    nd.name = 'vuneedle'; nd.scale = (0.05, Ln, 0.012); bpy.ops.object.transform_apply(scale=True)
    ca, sa = math.cos(a), math.sin(a)
    for v in nd.data.vertices:
        x, y = v.co.x, v.co.y + (V.NEEDLE_L - 0.4) / 2          # from the pivot
        v.co.x = x * ca + y * sa; v.co.y = V.PIVOT_Y - x * sa + y * ca
    nd.data.materials.append(nm)


def gas_digits(plate, cx, cy, text, name, pitch=1.05):
    """ircapture_kit.piece_gas('dig') in this plate at (cx, cy), larger (pitch: a digit cell's height in cm), its text lit."""
    n = K.GAS_DIG_N
    dw = n * pitch * 0.78 + 0.25
    tmp = os.path.join(OUT, 'gas', '_aspect'); os.makedirs(tmp, exist_ok=True)
    wp, hp = GD.seg7_maps(os.path.join(tmp, 'b.png'), os.path.join(tmp, 'e.png'), n)
    dh = dw * hp / wp
    ww, wh = dw + 0.6, dh + 0.6
    hole = rbox('ghole', ww, wh, T + 2, -T - 1, 0.08); hole.location.x = cx; hole.location.y = cy
    bpy.context.view_layer.update(); cut(plate, hole)
    bw = 0.5
    bez = rbox('gbezel', ww + 2 * bw, wh + 2 * bw, 0.14, 0.0, 0.12, roll=0.05); bez.location.x = cx; bez.location.y = cy
    bh = rbox('gbezh', ww - 0.04, wh - 0.04, 1.0, -0.5, 0.06); bh.location.x = cx; bh.location.y = cy
    bpy.context.view_layer.update(); cut(bez, bh); chamfer(bez, 0.02, 2); TK.flat_faces(bez)
    bez.data.materials.append(K.gas_bezel_mat())
    RA = K._RackAdapter(T, os.path.join(OUT, 'gas'))
    old = GD.DEMO, GD.demo_text
    GD.DEMO = bool(text); GD.demo_text = lambda eid: [text]
    L = []
    try:
        GD.gas_window(RA, L, 'gas-' + name, 'seg7', cx - ww / 2, cy - wh / 2, cx + ww / 2, cy + wh / 2, SG.nickel('gscrew', seed=3),
                      K.seed_of(name) % 7, n=n)
    finally:
        GD.DEMO, GD.demo_text = old
    for o in bpy.data.objects:
        if o.name.endswith('pane') or o.name.endswith('env'): o.visible_shadow = False
    return ww + 2 * bw, wh + 2 * bw


_RACK = []


def rack_mod():
    if not _RACK:
        a = sys.argv; sys.argv = [a[0], FONTS, OUT]
        import rack as RA
        sys.argv = a; _RACK.append(RA)
    return _RACK[0]


def eye(plate, x, y, state, name, es=0.8):
    """ircapture_eye.py's black-ringed magic eye (rack.py's Eye) in this plate."""
    RA = rack_mod(); RA.set_eye(es)
    bpy.context.view_layer.update(); cut(plate, cyl_cutter(1.6 * es, x, y, -5, 5))
    import finish_maps as FM
    ring = FM.material('eyebezel-' + name, 'powder', '#0d0c0b', 0.45, 4212, 'irc-eye-bezel', bare='#3b2c22', dirt='#1e1b17',
                       dirt_k=0.35, coat_rough=0.5)
    e = RA.Eye(x, y, ring, name); e.set(state)
    for o in bpy.data.objects:
        if o.type == 'MESH' and o.name.split('.')[0] == 'eyeenv' and o not in GLASS: GLASS.append(o)
    return e


def strip(v, L, text, name):
    """ircapture_kit.piece_scribble's masking tape, L cm long, the name hand-lettered on it (Swell Marker)."""
    look = dict(K.SCRIB_LOOK[v]); look['len'] = L
    H = K.SCRIB['h']
    rng = K.set_seed('scribble-' + name)
    al, crepe, tone, _ = K.tape_maps(L, H, look, rng)
    nx, ny = 200, 8
    bpy.ops.mesh.primitive_grid_add(x_subdivisions=nx, y_subdivisions=ny, size=1, location=(0, 0, 0))
    o = bpy.context.active_object; o.name = 'tape'
    o.scale = (L, H, 1); bpy.ops.object.transform_apply(scale=True)
    for vt in o.data.vertices:
        x = vt.co.x
        d = (x - (L / 2 - look['lift_len'])) if not look.get('lift_left') else ((-L / 2 + look['lift_len']) - x)
        z = 0.004
        if look['lift'] > 0 and d > 0: z += look['lift'] * (d / look['lift_len']) ** 1.7
        vt.co.z = z
    bpy.ops.object.shade_smooth()
    aged = look['age']
    base = np.array(srgb('#fbefc8')) * (1 - aged) + np.array(srgb('#f1dca0')) * aged
    m = mat('tape-' + name, tuple(base), rough=0.78, spec=0.25)
    nt = m.node_tree; b = nt.nodes['Principled BSDF']
    try: b.inputs['Sheen Weight'].default_value = 0.3; b.inputs['Sheen Roughness'].default_value = 0.6
    except Exception: pass
    uv = nt.nodes.new('ShaderNodeUVMap')
    # the lettering: a marker's ink, a little uneven, half a degree off level
    ppcm = 120; h, w = al.shape
    im = Image.new('L', (w, h), 0); d = ImageDraw.Draw(im)
    size = 0.95
    while True:
        f = ImageFont.truetype(os.path.join(FONTS, 'SwellMarker-400-normal.ttf'), int(size * ppcm * 1.25))
        if f.getlength(text) < (L - 1.6) * ppcm or size < 0.5: break
        size -= 0.05
    d.text((0.75 * ppcm, h / 2), text, font=f, fill=255, anchor='lm')
    im = im.rotate(0.5 * (1 if K.seed_of(name) % 2 else -1), resample=Image.BICUBIC)
    ink = np.asarray(im, np.float32) / 255
    ink = ink * (0.82 + 0.18 * K.blur(rng.random((h, w)).astype(np.float32), 3.0) * 2).clip(0, 1)
    t_al = SG.img_tex(nt, 'tal' + name, al, False, 'CLIP'); t_cr = SG.img_tex(nt, 'tcr' + name, crepe, False, 'CLIP')
    t_to = SG.img_tex(nt, 'tto' + name, tone, False, 'CLIP'); t_ink = SG.img_tex(nt, 'tink' + name, ink.astype(np.float32), False, 'CLIP')
    for t in (t_al, t_cr, t_to, t_ink): nt.links.new(uv.outputs['UV'], t.inputs['Vector'])
    nt.links.new(t_al.outputs['Color'], b.inputs['Alpha'])
    add_bump(m, t_cr.outputs['Color'], 0.1, 0.002)
    dark = node(nt, 'ShaderNodeMapRange', **{'From Min': 0.5, 'From Max': 1.3}); dark.clamp = True
    nt.links.new(t_to.outputs['Color'], dark.inputs['Value'])
    mix_into(m, 'Base Color', mul(nt, dark.outputs['Result'], 0.3), (*srgb('#c2a872'), 1))
    mix_into(m, 'Base Color', mul(nt, t_ink.outputs['Color'], 0.93), (*srgb('#17151a'), 1))
    try: m.blend_method = 'HASHED'
    except Exception: pass
    m = grimy(m, dirt='#8a7754', amount=0.04 + 0.08 * aged, dist=0.05)
    o.data.materials.append(m)
    return o


def key(lid, lit=False, down=False, text=None, size=None):
    """ircapture_kit.piece_legend's printed key. Returns its outer size."""
    import ircapture_legends as LG
    t0, s0, names = LG.LEGENDS[lid]
    text = text or t0; size = size or s0
    z = LG.SIZES[size]; v = LG.variant(names[0]); look = K.KEY_LOOK[v]
    h = z['cap_h']; w = K.legend_width(text, size)
    bz = TK.KEY['bezel'] * (1.3 if size == 'big' else 1.0); r = TK.KEY['r'] * (1.4 if size == 'big' else 1.0)
    rng = K.set_seed('legend-' + lid)
    bez = rbox('kbezel', w + 2 * bz, h + 2 * bz, 0.25, 0.0, r + bz * 0.6, roll=0.06)
    bpy.context.view_layer.update()
    cut(bez, prism('khole', _rring((w + 0.06) / 2, (h + 0.06) / 2, r, 0.0, 0, n_arc=8), -2, 2))
    chamfer(bez, 0.02, 2); bez.data.materials.append(SG.black_cast('kbez'))
    well = rbox('kwell', w + 0.1, h + 0.1, 0.3, -0.3, 0.05); well.data.materials.append(mat('kwell', (0.01, 0.009, 0.008), rough=0.8))
    zc = 0.03 if down else 0.15
    cap = rbox('cap', w, h, 0.3, zc, r, roll=0.07, seg=4); TK.flat_faces(cap)
    cap.data.materials.append(K.cap_mat_blank(lit, 'cap-%s-%d' % (lid, lit), w, h, look, rng, legend=(text, z['cap_cm'])))
    if lit:
        L = bpy.data.lights.new('kglow', 'POINT'); L.energy = 0.3 * (1 - 0.15 * look.get('aged', 0.3)) * (w * h) / (4.4 * 1.8)
        L.color = srgb('#ffa040'); L.shadow_soft_size = 0.6 * max(1.0, w / 4.4)
        g = bpy.data.objects.new('kglow', L); bpy.context.scene.collection.objects.link(g); g.location = (0, 0, zc + 0.9)
    return w + 2 * bz, h + 2 * bz


def toggle(pos):
    """A bat-handle toggle switch seen end on: a hex nut, a collar, the handle thrown up (+1), level (0) or down (-1)."""
    ch = SG.nickel('tgl', seed=4)
    nut = lathe('tnut', [(0.62, 0.0), (0.62, 0.16), (0.56, 0.2), (0.34, 0.2)], 6, smooth=False); nut.data.materials.append(ch)
    nut.rotation_euler = (0, 0, math.radians(30))
    col = lathe('tcol', [(0.36, 0.0), (0.36, 0.42), (0.3, 0.5), (0.16, 0.5)], 48); col.data.materials.append(ch)
    bat = lathe('tbat', [(0.13, 0.0), (0.16, 0.6), (0.21, 1.4), (0.25, 1.85), (0.24, 2.05), (0.15, 2.18), (0.0, 2.2)], 48)
    bat.data.materials.append(ch)
    bat.location = (0, 0, 0.3); bat.rotation_euler = (math.radians(-24 * pos), 0, 0)


def paper_mat(name, img_path, rough=0.7):
    m = mat(name, (1, 1, 1), rough=rough, spec=0.2)
    nt = m.node_tree; b = nt.nodes['Principled BSDF']
    tc = nt.nodes.new('ShaderNodeTexCoord')
    ti = nt.nodes.new('ShaderNodeTexImage'); ti.image = bpy.data.images.load(img_path); ti.extension = 'EXTEND'
    nt.links.new(tc.outputs['UV'], ti.inputs['Vector']); nt.links.new(ti.outputs['Color'], b.inputs['Base Color'])
    add_bump(m, noise(nt, obj_coords(nt), 0.25, 3.0, 0.5), 0.25, 0.02)       # the sheet not quite flat
    # (11-11, the second proof: paper came out a little grey under the white light) a faint self-lit share of its own
    # colour, as ircapture_tape.img_plane's labels: not visible as a glow
    k = float(os.environ.get('IRC_PAPER_LIFT', '0.22'))
    if k > 0:
        nt.links.new(ti.outputs['Color'], b.inputs['Emission Color']); b.inputs['Emission Strength'].default_value = k
    return m


def sheet(w, h, img_path, name='sheet', z=0.03, curl=0.0):
    nx, ny = 60, 40
    bpy.ops.mesh.primitive_grid_add(x_subdivisions=nx, y_subdivisions=ny, size=1, location=(0, 0, 0))
    o = bpy.context.active_object; o.name = name; o.scale = (w, h, 1); bpy.ops.object.transform_apply(scale=True)
    for vt in o.data.vertices:
        zz = z
        if curl:
            d = max(0.0, (vt.co.x - (w / 2 - 6.0)) / 6.0) * max(0.0, ((-vt.co.y) - (h / 2 - 5.0)) / 5.0)
            zz += curl * d ** 1.5
        vt.co.z = zz
    bpy.ops.object.shade_smooth()
    o.data.materials.append(paper_mat('paper-' + name, img_path))
    return o


GLASS = []


def finish_glass():
    """The studio's softboxes kept off every flat pane and dome (the VU's and the eye's rule)."""
    if GLASS: V.unlink_cards_from(GLASS)
    cards = ('key', 'top', 'rim', 'ceil', 'side', 'keyL', 'topL', 'over')
    eyes = [o for o in GLASS if o.name.split('.')[0] == 'eyeenv']
    if eyes:
        ex = bpy.data.collections.get('vu_glass_rx')
        for o in bpy.context.scene.objects:
            if o.type == 'LIGHT' and o.name.split('.')[0] in cards: o.light_linking.receiver_collection = ex
    del GLASS[:]


# ---------------------------------------------------------------------------------------------------------------------
# the typed sheet (a printed form, filled in on a typewriter, stamped, ticked in pencil)

TYPED = os.environ.get('IRC_TYPED_FONT', os.path.join(os.path.dirname(os.path.abspath(__file__)), 'fonts', 'CourierPrime-400.ttf'))


def take_sheet(path, w, h, px=110):
    W, H = int(w * px), int(h * px)
    rng = np.random.default_rng(5)
    paper = np.array([246, 234, 200], np.float32)
    im = Image.new('RGB', (W, H), tuple(int(c) for c in paper)); d = ImageDraw.Draw(im)
    F = lambda name, cm: ImageFont.truetype(os.path.join(FONTS, name) if not name.startswith('/') else name, int(cm * px))
    ox = (104, 30, 24); rule = (150, 120, 104); ink = (34, 32, 44)
    fh = F('BarlowSemiCondensed-700-normal.ttf', 0.95); fl = F('BarlowSemiCondensed-600-normal.ttf', 0.5)
    ft = F(TYPED, 0.74); fts = F(TYPED, 0.66)
    cm = lambda v: int(v * px)

    def spaced(x, y, text, font, fill, track=0.1, anchor='l'):
        tr = track * font.size
        wsum = sum(font.getlength(c) for c in text) + tr * (len(text) - 1)
        if anchor == 'r': x -= wsum
        if anchor == 'm': x -= wsum / 2
        for c in text:
            d.text((x, y), c, font=font, fill=fill); x += font.getlength(c) + tr

    def typed(x, y, text, font=None, jitter=True):
        font = font or ft
        adv = font.getlength('M')
        for c in text:
            dy = rng.normal(0, 0.012 * px) if jitter else 0
            dens = int(np.clip(rng.normal(0, 14), -30, 30))
            col = tuple(int(np.clip(v + dens, 0, 255)) for v in ink)
            d.text((x, y + dy), c, font=font, fill=col); x += adv

    m = 1.3
    # the letterhead
    spaced(cm(m), cm(0.95), 'CAB IR  TAKE SHEET', fh, ox, 0.14)
    spaced(W - cm(m), cm(1.25), 'ONE CAPTURE  ·  EVERY RATE', fl, ox, 0.16, 'r')
    d.line([(cm(m), cm(2.25)), (W - cm(m), cm(2.25))], fill=ox, width=cm(0.07))
    d.line([(cm(m), cm(2.4)), (W - cm(m), cm(2.4))], fill=ox, width=max(1, cm(0.02)))
    # the heading boxes
    y = 2.95
    boxes = [('CAPTURE', 'Mesa_4x12_V30', 0.0, 14.5), ('DATE', '11 NOV 26', 14.5, 21.5), ('INTERFACE', 'Scarlett 18i20', 21.5, 30.4),
             ('RATE', '96 kHz', 30.4, w - 2 * m)]
    for lab, val, x0, x1 in boxes:
        spaced(cm(m + x0 + 0.1), cm(y), lab, fl, rule, 0.14)
        typed(cm(m + x0 + 0.1), cm(y + 0.72), val)
        d.line([(cm(m + x0), cm(y + 1.75)), (cm(m + x1 - 0.5), cm(y + 1.75))], fill=rule, width=max(1, cm(0.02)))
    # the table
    y0 = 5.6
    cols = [('CHANNEL', 0.0), ('PEAK dBFS', 9.6), ('NOISE dB', 14.4), ('TAIL ms', 19.0), ('H2 dB', 23.3), ('H3 dB', 27.0), ('ARRIVAL ms', 30.6)]
    for lab, x in cols: spaced(cm(m + x + 0.1), cm(y0), lab, fl, rule, 0.14)
    rows = [('Close  SM57', '-11.6', '-108', ' 36', '-45', '-52', ' 0.17'),
            ('Room   R121', '-10.5', ' -84', '451', '-46', '-51', ' 8.77'),
            ('Reference', '-21.1', '-122', '360', '  -', '  -', '    -')]
    rh = 1.42
    d.line([(cm(m), cm(y0 + 0.85)), (W - cm(m), cm(y0 + 0.85))], fill=ox, width=max(1, cm(0.035)))
    for r, row in enumerate(rows):
        yy = y0 + 1.12 + r * rh
        for (lab, x), val in zip(cols, row): typed(cm(m + x + (1.2 if r < 2 and lab == 'CHANNEL' else 0.1)), cm(yy), val)
        d.line([(cm(m), cm(yy + rh - 0.27)), (W - cm(m), cm(yy + rh - 0.27))], fill=rule, width=max(1, cm(0.02)))
    for lab, x in cols[1:]:
        d.line([(cm(m + x - 0.25), cm(y0 - 0.1)), (cm(m + x - 0.25), cm(y0 + 0.85 + 3 * rh))], fill=rule, width=max(1, cm(0.02)))
    # the channels' colours: a dab of coloured pencil
    for r, col in enumerate(((226, 132, 60), (94, 140, 196))):
        yy = y0 + 1.12 + r * rh
        for k in range(60):
            a, b = rng.normal(0, 0.2), rng.normal(0, 0.16)
            d.line([(cm(m + 0.5 + a - 0.12), cm(yy + 0.42 + b + 0.1)), (cm(m + 0.5 + a + 0.12), cm(yy + 0.42 + b - 0.1))],
                   fill=tuple(int(c * rng.uniform(0.85, 1.0)) for c in col), width=max(1, cm(0.03)))
    # the files
    y1 = y0 + 0.85 + 3 * rh + 0.75
    spaced(cm(m + 0.1), cm(y1), 'LOAD THESE', fl, rule, 0.14)
    typed(cm(m + 0.1), cm(y1 + 0.78), 'Mesa_4x12_V30_SM57.wav')
    typed(cm(m + 0.1), cm(y1 + 1.86), 'Mesa_4x12_V30_R121.wav')
    typed(cm(m + 0.1), cm(y1 + 3.15), '48 kHz  24-bit  500 ms', fts)
    spaced(cm(m + 19.1), cm(y1), 'NOTES', fl, rule, 0.14)
    for k, t in enumerate(('86 files. Reference used.', 'Room: no minimum-phase', 'version is made.')):
        typed(cm(m + 19.1), cm(y1 + 0.78 + k * 1.08), t, fts)
        d.line([(cm(m + 19.0), cm(y1 + 1.62 + k * 1.08)), (cm(m + 28.6), cm(y1 + 1.62 + k * 1.08))], fill=rule, width=max(1, cm(0.02)))
    # paper: tooth, a soft fold shadow, aged edges
    a = np.asarray(im, np.float32)
    tooth = np.asarray(Image.fromarray((rng.random((H, W)) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.0)), np.float32) / 255
    a *= (0.975 + 0.05 * tooth)[..., None]
    blot = np.asarray(Image.fromarray((rng.random((H // 8, W // 8)) * 255).astype(np.uint8)).resize((W, H), Image.BICUBIC).filter(ImageFilter.GaussianBlur(40)), np.float32) / 255
    a *= (0.96 + 0.08 * blot)[..., None]
    yy_, xx_ = np.mgrid[0:H, 0:W]
    e = np.maximum(np.abs(xx_ - W / 2) / (W / 2), np.abs(yy_ - H / 2) / (H / 2))
    age = np.clip((e - 0.8) / 0.2, 0, 1) ** 1.8
    a = a * (1 - 0.09 * age[..., None]) * np.array([1.0, 0.98, 0.93])[None, None, :] ** age[..., None]
    im = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))
    # the stamp: green ink, a double box, turned, the ink uneven and broken
    sw, sh = cm(9.2), cm(2.5)
    st = Image.new('L', (sw, sh), 0); sd = ImageDraw.Draw(st)
    sd.rectangle([cm(0.1), cm(0.1), sw - cm(0.1), sh - cm(0.1)], outline=255, width=cm(0.13))
    sd.rectangle([cm(0.33), cm(0.33), sw - cm(0.33), sh - cm(0.33)], outline=255, width=max(1, cm(0.04)))
    fs = F('BarlowSemiCondensed-700-normal.ttf', 1.3)
    tr = 0.14 * fs.size; txt = 'EXCELLENT'
    wsum = sum(fs.getlength(c) for c in txt) + tr * (len(txt) - 1); x = (sw - wsum) / 2
    bb = fs.getbbox('H')
    for c in txt:
        sd.text((x, sh / 2 - (bb[1] + bb[3]) / 2), c, font=fs, fill=255); x += fs.getlength(c) + tr
    n1 = np.asarray(Image.fromarray((rng.random((sh, sw)) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(2.2)), np.float32) / 255
    n2 = np.asarray(Image.fromarray((rng.random((sh // 6 + 1, sw // 6 + 1)) * 255).astype(np.uint8)).resize((sw, sh), Image.BICUBIC), np.float32) / 255
    sa = np.asarray(st, np.float32) / 255 * np.clip((n1 - 0.36) * 6, 0, 1) * (0.55 + 0.45 * n2)
    st = Image.fromarray((sa * 235).astype(np.uint8)).rotate(-5.5, resample=Image.BICUBIC, expand=True)
    im.paste(Image.new('RGB', st.size, (30, 122, 74)), (W - cm(m) - st.size[0] + cm(0.2), cm(y1 + 0.75)), st)
    im.save(path)


# ---------------------------------------------------------------------------------------------------------------------
# units

def unit_step(current=1, done=(0,)):
    """1U: the job's steps. Done: green; the current step: amber; ahead: dark."""
    K.set_seed('rack-step')
    s, cam, h = unit_scene(1)
    backing(h)
    rack_panel(1, 'bronze', 'step')
    names = ['CONNECT', 'SET LEVELS', 'CAPTURE', 'RESULTS']
    x = -19.0
    for i, n in enumerate(names):
        col = 'green' if i in done else 'amber'
        jewel(x, 0.0, col, i in done or i == current, r=0.55)
        e = engrave(n, 0, 0, 0.62)
        wcm = e.dimensions.x; e.location.x = x + 1.1 + wcm / 2 - 0.1 * wcm
        x += 10.2
    shoot(s, cam, 'unit-step', PW, h)


def unit_patch():
    """2U: the interface's inputs, a three-way toggle each: MIC up, OFF level, REF down."""
    K.set_seed('rack-patch')
    s, cam, h = unit_scene(2)
    backing(h)
    rack_panel(2, 'black', 'patch')
    engrave('INPUTS', -19.4, 2.6, 0.5)
    pos = [1, 1, 1, -1, 0, 0, 0, 0]
    for i in range(8):
        x = -14.6 + i * 4.75
        with moved(x, -0.35, 0): toggle(pos[i])
        engrave(str(i + 1), x, 2.6, 0.62)
        engrave('MIC', x + 1.55, 0.85, 0.44, track=0.12); engrave('OFF', x + 1.55, -0.35, 0.44, track=0.12)
        engrave('REF', x + 1.55, -1.55, 0.44, track=0.12)
    shoot(s, cam, 'unit-patch', PW, h)


MODS = [dict(name='SM57 CAP EDGE', v='a', db=-0.4, peak='-6.0', lamps=('OK',), eye='x34', base='#1d1812'),
        dict(name='R121 CENTER', v='b', db=-9.0, peak='-15.0', lamps=('LOW',), eye='x30', base='#1a1610'),
        dict(name='ROOM 3 M', v='c', db=3.3, peak='-0.1', lamps=('HIGH', 'CLIP', 'DIST'), eye='x18', base='#1d1812'),
        dict(name='REFERENCE', v='d', db=-22.0, peak='', lamps=('LOW',), eye='x38', base='#191612')]
LAMPS = [('LOW', 'amber'), ('OK', 'green'), ('HIGH', 'amber'), ('CLIP', 'red'), ('DIST', 'amber')]
MW, MH, MZ = 11.1, 21.3, 0.3


def module(mo):
    K.set_seed('rack-mod-' + mo['name'])
    pl = rbox('mplate', MW, MH, MZ, -MZ, 0.18, roll=0.05)
    yv = MH / 2 - 0.85 - V.BZ['h'] / 2
    yr = yv - V.BZ['h'] / 2 - 0.55 - 1.9
    gw, gh = gas_digits(pl, -2.45, yr, mo['peak'], mo['name'])
    eye(pl, 3.35, yr, mo['eye'], mo['name'])
    chamfer(pl, 0.015, 2); TK.flat_faces(pl)
    pl.data.materials.append(K.hammertone_fine(base=mo['base'], name='hf-' + mo['name']))
    small_screws([(sx * (MW / 2 - 0.45), sy * (MH / 2 - 0.45)) for sx in (-1, 1) for sy in (-1, 1)], seed=K.seed_of(mo['name']) % 7)
    with moved(0, yv, 0): vu(mo['db'], True, mo['name'])
    engrave('PEAK  dBFS', -2.45, yr - gh / 2 - 0.5, 0.44, track=0.14)
    engrave('NOISE', 3.35, yr - 1.9 - 0.5, 0.44, track=0.14)
    yl = yr - 1.9 - 0.5 - 1.35
    for i, (lab, col) in enumerate(LAMPS):
        x = -4.3 + i * 2.15
        jewel(x, yl, col, lab in mo['lamps'], r=0.42)
        engrave(lab, x, yl - 0.95, 0.44, track=0.12)
    ys = -MH / 2 + 0.55 + K.SCRIB['h'] / 2
    with moved(0, ys, 0): strip(mo['v'], 10.2, mo['name'], mo['name'])


def unit_meters():
    """5U: the meter bridge, a frame with four channel modules."""
    K.set_seed('rack-meters')
    s, cam, h = unit_scene(5)
    backing(h)
    fr, hh = rack_panel(5, 'bronze', 'bridge')
    op = rbox('fopen', 4 * MW + 0.1, MH - 0.6, 4, -2, 0.1); bpy.context.view_layer.update(); cut(fr, op)
    fr.data.materials.append(K.hammertone_fine(base='#191612', name='hf-bridge'))
    for i, mo in enumerate(MODS):
        with moved((i - 1.5) * (MW + 0.06), 0, MZ): module(mo)
    finish_glass()
    shoot(s, cam, 'unit-meters', PW, h)


def unit_gap():
    """1U left empty: the rails, their holes, the dark inside the rack."""
    K.set_seed('rack-gap')
    s, cam, h = unit_scene(1)
    bk = rbox('inside', PW, h + 1, 0.1, -9.0, 0.01); bk.data.materials.append(mat('inside', srgb('#060606'), rough=0.9))
    zn = SG.nickel('rail', seed=6)
    for sx in (-1, 1):
        r = rbox('rail', 1.9, h + 1, 0.25, -T - 0.25 - 0.02, 0.02)
        r.location.x = sx * EAR_X
        for y in (-1.5875, 0.0, 1.5875):
            c = rbox('rh', 0.95, 0.95, 2, -2, 0.03); c.location.x = sx * EAR_X; c.location.y = y
            bpy.context.view_layer.update(); cut(r, c)
        chamfer(r, 0.01, 1); r.data.materials.append(mat('railm', srgb('#23221f'), rough=0.5, metal=0.6))
    shoot(s, cam, 'unit-gap', PW, h)


def unit_results():
    """6U: a chart panel. The take sheet in a card frame; FINDER and RE-EXPORT under it."""
    K.set_seed('rack-results')
    s, cam, h = unit_scene(6)
    backing(h)
    rack_panel(6, 'bronze', 'results')
    sw, sh = 40.0, 17.0
    ysh = h / 2 - 1.5 - sh / 2
    fp = os.path.join(OUT, 'take-sheet-print.png'); take_sheet(fp, sw, sh)
    with moved(0, ysh, 0): sheet(sw, sh, fp, 'take', curl=0.35)
    # the card frame: a folded steel channel over the sheet's top and bottom edges, a screw at each end
    cm_ = SG.black_cast('cardframe')
    for sy in (1, -1):
        ch = rbox('cframe', sw + 1.6, 0.9, 0.22, 0.0, 0.08, roll=0.05); ch.location.y = ysh + sy * (sh / 2 + 0.1)
        chamfer(ch, 0.012, 1); ch.data.materials.append(cm_)
    small_screws([(sx * (sw / 2 + 0.45), ysh + sy * (sh / 2 + 0.1)) for sx in (-1, 1) for sy in (-1, 1)], r=0.17)
    yk = ysh - sh / 2 - 0.1 - 0.45 - 0.75 - 1.4
    x = -sw / 2
    for lid in ('finder', 'reexport', 'record-again'):
        import ircapture_legends as LG
        wk = K.legend_width(LG.LEGENDS[lid][0], 'std') + 2 * TK.KEY['bezel']
        with moved(x + wk / 2, yk, 0): key(lid)
        x += wk + 0.5
    engrave('RESULTS', sw / 2 - 2.6, yk, 0.62)
    shoot(s, cam, 'unit-results', PW, h)


# ---------------------------------------------------------------------------------------------------------------------
# the reel deck as a rack unit (11-11, second proof)
#
# The audit (section 3): the old deck's three chrome levers looked like transport keys and did nothing, while its real
# keys were ivory caps stuck on the plate; flat grey flanges, a flat brown pack, legends too small. Here the deck is a
# rack-mount recorder of its own: 8U, a warm brushed plate (another maker's unit in a hodgepodge rack), two 7 inch reels
# side by side, the head block under them, its own transport keys in one row along the bottom (CHECK LEVELS, CAPTURE with
# its REC jewel, STOP: the printed keys, nothing else that looks pressable), the drum counter between the reels. The
# flanges are spun aluminium (an anisotropic sheen round the hub, so they shade with the light), the packs wound tape.

DECK = dict(u=8, rx=11.6, ry=6.4, ty=-6.2, heads=(-4.5, -1.0, 2.5), cap=4.6, gl=-8.0, gr=6.8, tr=(9.4, -3.8),
            ky=-13.0, cy=12.0)


def _tape():
    if 'ircapture_tape' not in sys.modules:
        a = sys.argv; sys.argv = [a[0], OUT, 'none', str(PXCM), str(SAMPLES)]
        import ircapture_tape
        sys.argv = a
    return sys.modules['ircapture_tape']


def spun_alu(name='spun'):
    """A reel's flange: spun aluminium. Turned rings and an anisotropic sheen whose grain runs round the hub, so the
    light lies on it as a broad radial streak (the old reels' plain metal mirrored the dark room straight on: flat grey)."""
    m = mat(name, srgb('#a8a296'), rough=0.3, metal=1.0, spec=0.5, aniso=0.75)
    nt = m.node_tree; b = nt.nodes['Principled BSDF']; co = obj_coords(nt)
    tg = node(nt, 'ShaderNodeTangent'); tg.direction_type = 'RADIAL'; tg.axis = 'Z'
    nt.links.new(tg.outputs['Tangent'], b.inputs['Tangent'])
    wv = node(nt, 'ShaderNodeTexWave', Scale=9.0); wv.wave_type = 'RINGS'; wv.rings_direction = 'Z'
    try: wv.inputs['Distortion'].default_value = 0.6; wv.inputs['Detail'].default_value = 4.0
    except Exception: pass
    nt.links.new(co, wv.inputs['Vector'])
    add_bump(m, wv.outputs['Fac'], 0.06, 0.001)
    mix_into(m, 'Roughness', mul(nt, wv.outputs['Fac'], 0.4), 0.16, 'FLOAT')
    mix_into(m, 'Base Color', mul(nt, noise(nt, co, 0.35, 3.0, 0.55, lo=0.35, hi=0.75), 0.4), (*srgb('#9d978a'), 1))
    surface_wear(m, dust=0.25, smudge=0.45, scuff=0.5)
    return grimy(m, dirt='#3b3428', amount=0.35, dist=0.08)


def deck_alu(name='deckplate'):
    """The deck's plate: ircapture_tape.brushed_alu's grain (three scales of streaks along x, an anisotropic sheen across
    the plate), but aged and duller: straight on, a bright brushed plate mirrors the room behind the camera and the
    11-04 colours read a flat pale grey whatever the base (first test, 11-11). Less metal, more roughness, darker
    streaks: old aluminium that has been handled for thirty years."""
    k = float(os.environ.get('IRC_DECK_DIM', '0.62'))
    def c(h): return tuple(v * k for v in srgb(h))
    m = mat(name, c('#a99772'), rough=0.42, metal=0.72, spec=0.45, aniso=0.5)
    nt = m.node_tree; b = nt.nodes['Principled BSDF']; co = obj_coords(nt)
    tg = node(nt, 'ShaderNodeTangent'); tg.direction_type = 'RADIAL'; tg.axis = 'Y'
    nt.links.new(tg.outputs['Tangent'], b.inputs['Tangent'])
    def streak(sx, sc, lo, hi):
        mp = node(nt, 'ShaderNodeMapping'); mp.inputs['Scale'].default_value = (sx, 1.0, 1.0); nt.links.new(co, mp.inputs[0])
        return noise(nt, mp.outputs[0], sc, 5.0, 0.7, lo=lo, hi=hi)
    stroke = streak(0.02, 2.5, 0.3, 0.7); hair = streak(0.006, 12.0, 0.35, 0.65); fine = streak(0.004, 60.0, 0.3, 0.7)
    add_bump(m, hair, 0.35, 0.003); add_bump(m, fine, 0.2, 0.0015)
    mix_into(m, 'Roughness', mul(nt, hair, 0.8), 0.56, 'FLOAT')
    mix_into(m, 'Base Color', mul(nt, stroke, 0.4), (*c('#a4967a'), 1))
    mix_into(m, 'Base Color', mul(nt, hair, 0.5), (*c('#d2c6ac'), 1))
    mix_into(m, 'Base Color', mul(nt, fine, 0.25), (*c('#a99c82'), 1))
    mix_into(m, 'Base Color', mul(nt, noise(nt, co, 0.3, 3.0, 0.55, lo=0.35, hi=0.75), 0.5), (*c('#7d7058'), 1))
    surface_wear(m, dust=0.4, smudge=0.55, scuff=0.35)
    return grimy(m, dirt='#3b3428', amount=0.55, dist=0.1)


def wound_oxide(name='wound'):
    """The pack's face: brown oxide wound layer on layer; each wind a hair lighter or darker, so the pack reads as tape
    (no bump and no smooth normals: either shaded the old pack black)."""
    m = mat(name, srgb('#8a6342'), rough=0.42, spec=0.45)
    nt = m.node_tree; co = obj_coords(nt)
    wv = node(nt, 'ShaderNodeTexWave', Scale=40.0); wv.wave_type = 'RINGS'; wv.rings_direction = 'Z'
    try: wv.inputs['Distortion'].default_value = 1.5; wv.inputs['Detail'].default_value = 2.0
    except Exception: pass
    nt.links.new(co, wv.inputs['Vector'])
    band = node(nt, 'ShaderNodeTexWave', Scale=2.2); band.wave_type = 'RINGS'; band.rings_direction = 'Z'
    try: band.inputs['Distortion'].default_value = 3.0
    except Exception: pass
    nt.links.new(co, band.inputs['Vector'])
    mix_into(m, 'Base Color', mul(nt, wv.outputs['Fac'], 0.22), (*srgb('#5f412a'), 1))
    mix_into(m, 'Base Color', mul(nt, band.outputs['Fac'], 0.18), (*srgb('#a37a52'), 1))
    mix_into(m, 'Roughness', mul(nt, wv.outputs['Fac'], 0.3), 0.6, 'FLOAT')
    return m


def counter(x, y, text, T_, plate):
    """The tape counter: a black bezel and four drum wheels, white figures (the deck's own SECONDS LEFT)."""
    cw, chh = 6.2, 2.0
    blk = SG.black_cast('cbez')
    ho = rbox('cwin', cw + 0.1, chh + 0.1, T + 2, -T - 1, 0.1); ho.location = (x, y, 0)
    bpy.context.view_layer.update(); cut(plate, ho)
    bz = rbox('cbez', cw + 0.6, chh + 0.6, 0.3, 0.0, 0.3, roll=0.1); bz.location = (x, y, 0)
    cut(bz, prism('chole', [(px + x, py + y, pz) for px, py, pz in _rring(cw / 2, chh / 2, 0.15, 0.0, 0, n_arc=8)], -2, 2))
    chamfer(bz, 0.02, 2); bz.data.materials.append(blk)
    wm = mat('wheel', srgb('#141211'), rough=0.5, coat=0.2)
    for i, d in enumerate(text):
        dx = x - 2.25 + i * 1.5
        # a drum: curved, so its figure rolls off a little top and bottom
        bpy.ops.mesh.primitive_cylinder_add(radius=1.05, depth=1.25, vertices=64, location=(dx, y, -0.95))
        dr = bpy.context.active_object; dr.name = 'drum'; dr.rotation_euler = (0, math.radians(90), 0)
        dr.data.materials.append(wm); bpy.ops.object.shade_smooth()
        T_.ink(d, dx, y, 0.12, 0.95, color='#ece6d6', kind='BarlowSemiCondensed-600-normal.ttf', track=0.0, w=1.2)
    return cw + 0.6, chh + 0.6


def unit_deck(prog=None, rec=True):
    """8U: the reel deck. The proof's state: a capture running (CAPTURE lit, REC lit), 40 % of the take done."""
    T_ = _tape()
    prog = float(os.environ.get('IRC_DECK_PROG', '0.4')) if prog is None else prog
    K.set_seed('rack-deck')
    s, cam, h = unit_scene(DECK['u'])
    backing(h)
    pl, ph = rack_panel(DECK['u'], 'alu', 'deck')
    # (straight on the plate mirrors the room behind the camera; at the 11-04 colour it washed to a pale grey) older,
    # warmer, duller aluminium
    D = '#1e1a15'                       # the legends on the plate: filled dark, as on the old deck
    ni = TK.nickel(); ch = SG.chrome('chr', seed=3); blk = SG.black_cast('bc'); alu = spun_alu(); tp = wound_oxide()
    rx, ry, ty = DECK['rx'], DECK['ry'], DECK['ty']
    hub, full = T_.REEL['hub'], T_.REEL['pack_full']
    A = full * full - hub * hub
    rs = math.sqrt(hub * hub + A * (1 - prog)); rt = math.sqrt(hub * hub + A * prog)
    hx = DECK['heads']; cx_ = DECK['cap']; gl, gr = DECK['gl'], DECK['gr']; trx, try_ = DECK['tr']
    # everything below was laid out on the old deck's plate face at z = 0.25; here the panel's face is z = 0
    with moved(0, 0, -0.25):
        zt0, zt1 = T_.reel(-rx, ry, rs, 0.3, alu, tp, ch, blk)
        T_.reel(rx, ry, rt, 1.4, alu, tp, ch, blk)
        # the head block
        base = rbox('hbase', 22.0, 5.6, 0.6, 0.25, 0.4, roll=0.12); base.location = (-0.7, ty + 3.2, 0)
        chamfer(base, 0.02, 2); base.data.materials.append(K.hammertone_fine(base='#191612', hi='#2e271e', name='hbase'))
        hood = rbox('hood', 12.4, 2.4, 1.6, 0.85, 0.6, roll=0.35); hood.location = (hx[1], ty + 4.9, 0)
        chamfer(hood, 0.02, 2); hood.data.materials.append(blk)
        mu = T_.mu_metal()
        for x in hx:
            hd = rbox('head', 2.3, 2.4, 2.2, 0.85, 0.9, roll=0.2); hd.location = (x, ty + 1.2, 0); hd.data.materials.append(mu)
            gap = rbox('gap', 0.05, 0.7, 0.02, 3.04, 0.0); gap.location = (x, ty + 0.4, 0)
            gap.data.materials.append(mat('gapblk', srgb('#151210'), rough=0.5))
            sh = rbox('shield', 2.8, 0.35, 2.4, 0.85, 0.12, roll=0.05); sh.location = (x, ty + 2.55, 0); sh.data.materials.append(ch)
        # (first test) chrome seen end on mirrors the dark room: the posts' and rollers' tops read as black blobs.
        # Turned satin metal (the flanges' own) instead.
        for gx in (gl, gr):
            T_.cyl('post', 0.55, 0.85, zt1 + 0.25, gx, ty + 0.55, 64, alu)
            for z in (zt0 - 0.06, zt1 + 0.06): T_.cyl('pfl', 0.8, z - 0.05, z + 0.05, gx, ty + 0.55, 64, alu)
        T_.cyl('capstan', 0.22, 0.85, zt1 + 0.4, cx_, ty + 0.22, 48, mu)
        T_.cyl('pinch', 1.05, 0.9, zt1 + 0.25, cx_, ty - 1.07, 128, T_.black_rubber())
        T_.cyl('pinchcap', 0.4, zt1 + 0.25, zt1 + 0.4, cx_, ty - 1.07, 64, alu)
        # the tension arms: each pivots on a boss below and outboard of its roller
        for sx in (-1, 1):
            ax, ay = sx * trx, try_
            px_, py_ = sx * (trx + 2.0), try_ - 2.6
            L = math.hypot(ax - px_, ay - py_); ang = math.atan2(ay - py_, ax - px_)
            a = rbox('tarm', L + 0.7, 0.7, 0.3, 0.9, 0.3, roll=0.1)          # on top of the head base
            a.location = ((ax + px_) / 2, (ay + py_) / 2, 0); a.rotation_euler = (0, 0, ang); a.data.materials.append(blk)
            T_.cyl('tpiv', 0.6, 0.85, 1.4, px_, py_, 48, ni)
            T_.cyl('troll', 0.7, 1.2, zt1 + 0.15, ax, ay, 64, alu)
        circles = [((-rx, ry), rs, -1), ((-trx, try_), 0.7, +1), ((gl, ty + 0.55), 0.55, +1)]
        circles += [((x, ty + 0.9), 0.9, +1) for x in hx]
        circles += [((cx_, ty + 0.22), 0.22, +1), ((gr, ty + 0.55), 0.55, +1), ((trx, try_), 0.7, +1), ((rx, ry), rt, -1)]
        tape = T_.ribbon('tape', T_.tape_path(circles), zt0, zt1, tp)
        # straight on the tape is seen edge on (its width runs into the plate): a hair widened so the path reads
        tape.modifiers['th'].thickness = 0.07; tape.modifiers['th'].offset = 0.0
    # the head names on the hood's face, engraved and filled (each at least MIN_CAP_PT on screen)
    for word, x in zip(('ERASE', 'RECORD', 'PLAY'), hx): engrave(word, x, ty + 4.9, 0.44, z=2.2, track=0.12)
    # the counter between the reels
    cw, chh = counter(0.0, DECK['cy'], '%04d' % int(os.environ.get('IRC_DECK_SECS', '32')), T_, pl)
    engrave('SECONDS LEFT', 0.0, DECK['cy'] - chh / 2 - 0.7, 0.44, track=0.14, color=D)
    pl.data.materials.append(deck_alu())         # after the counter's window: gear_kit.cut() clears the materials
    # the transport: the deck's own keys in one row, the REC jewel beside CAPTURE
    import ircapture_legends as LG
    ky = DECK['ky']
    row = [('check', False), ('capture', rec), ('rec', rec), ('stop', False)]
    widths = []
    for lid, _ in row:
        widths.append(1.6 if lid == 'rec' else K.legend_width(LG.LEGENDS[lid][0], 'std') + 2 * TK.KEY['bezel'])
    gap_ = 0.7
    x = -0.7 - (sum(widths) + gap_ * (len(row) - 1)) / 2
    for (lid, lit), wk in zip(row, widths):
        if lid == 'rec':
            jewel(x + wk / 2, ky, 'red', lit, r=0.5)
            engrave('REC', x + wk / 2, ky + 1.55, 0.44, track=0.12, color=D)
        else:
            with moved(x + wk / 2, ky, 0): key(lid, lit=lit)
        x += wk + gap_
    engrave('RECORDER', 19.0, ky, 0.62, color=D)
    finish_glass()
    a = TK.proj(s, cam, (-rx, ry, 0)); b = TK.proj(s, cam, (rx, ry, 0))
    shoot(s, cam, 'unit-deck', PW, h, {'reel_c_px': [a, b], 'prog': prog})


def unit_cheeks():
    """The rack's sides and top: rough shop-wood boards on edge (ircapture_kit.piece_trim_shop), 1.9 cm, straight on."""
    # (11-11, second proof) the zinc screw heads read as bright white dots straight on: the boards' screws black
    import shop_wood as SWD
    if not getattr(SWD, '_irc_black', False):
        _ds = SWD.drywall_screw
        SWD.drywall_screw = lambda *a, **k: _ds(*a, **dict(k, finish='black'))
        SWD._irc_black = True
    K.TRIM['w'] = 1.9; K.TRIM['proud'] = 1.2
    K.LONG['trim_v'] = float(os.environ.get('IRC_CHEEK_CM', '76')); K.LONG['trim_h'] = 56.0
    K.piece_trim_shop('v'); K.piece_trim_shop('h')
    LAY['out'].update({k: K.LAY['out'][k] for k in ('trim-v', 'trim-h')})
    json.dump(LAY, open(os.path.join(OUT, 'rack-cheeks.json'), 'w'), indent=1)


# ---------------------------------------------------------------------------------------------------------------------
# the third proof (11-11, evening): the chart panel, the pre-flight sheet, the cart machine and the NAM meters
#
# Paper: drawn here as pictures (for the app: line drawings on paper and the typing drawn in code, the paper and its frame
# rendered). Every sheet sits in a card frame, as the take sheet does. The NAM side is the solid-state family: graphite
# anodised plates, flush LEDs, red seven-segment LED digits behind a red filter, an LED bargraph behind smoked glass.

def age_paper(im, rng, tint=(1.0, 0.98, 0.93)):
    """take_sheet's paper: tooth, a soft blotchiness, the edges a little darker and warmer."""
    a = np.asarray(im, np.float32); H, W = a.shape[:2]
    tooth = np.asarray(Image.fromarray((rng.random((H, W)) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.0)), np.float32) / 255
    a *= (0.975 + 0.05 * tooth)[..., None]
    blot = np.asarray(Image.fromarray((rng.random((H // 8, W // 8)) * 255).astype(np.uint8)).resize((W, H), Image.BICUBIC)
                      .filter(ImageFilter.GaussianBlur(40)), np.float32) / 255
    a *= (0.96 + 0.08 * blot)[..., None]
    yy_, xx_ = np.mgrid[0:H, 0:W]
    e = np.maximum(np.abs(xx_ - W / 2) / (W / 2), np.abs(yy_ - H / 2) / (H / 2))
    age = np.clip((e - 0.8) / 0.2, 0, 1) ** 1.8
    a = a * (1 - 0.09 * age[..., None]) * np.array(tint)[None, None, :] ** age[..., None]
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))


class Pen:
    """Drawing on a sheet in cm: px a cm, y down from the sheet's top."""
    def __init__(self, w, h, px, paper, seed):
        self.px = px; self.W, self.H = int(w * px), int(h * px)
        self.im = Image.new('RGB', (self.W, self.H), paper); self.d = ImageDraw.Draw(self.im)
        self.rng = np.random.default_rng(seed)

    def c(self, v): return int(round(v * self.px))
    def p(self, x, y): return (self.c(x), self.c(y))

    def font(self, name, cm):
        return ImageFont.truetype(name if name.startswith('/') else os.path.join(FONTS, name), max(6, int(cm * self.px)))

    def spaced(self, x, y, text, font, fill, track=0.1, anchor='l'):
        tr = track * font.size; xx = self.c(x)
        wsum = sum(font.getlength(ch) for ch in text) + tr * (len(text) - 1)
        if anchor == 'r': xx -= wsum
        if anchor == 'm': xx -= wsum / 2
        bb = font.getbbox('H'); yy = self.c(y) - (bb[1] + bb[3]) / 2
        for ch in text:
            self.d.text((xx, yy), ch, font=font, fill=fill); xx += font.getlength(ch) + tr

    def typed(self, x, y, text, font, ink=(34, 32, 44)):
        adv = font.getlength('M'); xx = self.c(x); bb = font.getbbox('H'); y0 = self.c(y) - (bb[1] + bb[3]) / 2
        for ch in text:
            dy = self.rng.normal(0, 0.012 * self.px); dens = int(np.clip(self.rng.normal(0, 14), -30, 30))
            self.d.text((xx, y0 + dy), ch, font=font, fill=tuple(int(np.clip(v + dens, 0, 255)) for v in ink)); xx += adv
        return x + len(text) * adv / self.px

    def line(self, pts, fill, w, wobble=0.0):
        q = [(self.c(x) + (self.rng.normal(0, wobble * self.px) if wobble else 0),
              self.c(y) + (self.rng.normal(0, wobble * self.px) if wobble else 0)) for x, y in pts]
        self.d.line(q, fill=fill, width=max(1, self.c(w)), joint='curve')

    def pencil(self, pts, fill, w, n=3, jit=0.03):
        """A soft pencil stroke: a few overlapping passes, uneven."""
        for k in range(n):
            col = tuple(int(c * self.rng.uniform(0.9, 1.06)) for c in fill)
            self.line([(x + self.rng.normal(0, jit), y + self.rng.normal(0, jit)) for x, y in pts], col, w * self.rng.uniform(0.7, 1.0))

    def arrow(self, x0, y0, x1, y1, fill, w=0.04, head=0.32):
        self.line([(x0, y0), (x1, y1)], fill, w)
        a = math.atan2(y1 - y0, x1 - x0)
        for s in (1, -1):
            b = a + math.pi - s * 0.42
            self.line([(x1, y1), (x1 + head * math.cos(b), y1 + head * math.sin(b))], fill, w)

    def box(self, x0, y0, x1, y1, fill, w=0.05, r=0.25):
        self.d.rounded_rectangle([self.c(x0), self.c(y0), self.c(x1), self.c(y1)], radius=self.c(r), outline=fill, width=max(1, self.c(w)))


def wiring_drawing(path, w, h, px=110):
    """Cab IR's hook-up, inked on graph paper: interface, amp (into its FX return), cab, two mics, the 20 dB pad from the
    speaker terminals, the monitors crossed out. A pencilled note where people go wrong."""
    P_ = Pen(w, h, px, (241, 237, 222), 11); d = P_.d
    g1, g2 = (190, 210, 204), (160, 190, 184)
    for i in range(int(w / 0.5) + 1):
        x = i * 0.5; d.line([P_.p(x, 0), P_.p(x, h)], fill=g2 if i % 5 == 0 else g1, width=1)
    for i in range(int(h / 0.5) + 1):
        y = i * 0.5; d.line([P_.p(0, y), P_.p(w, y)], fill=g2 if i % 5 == 0 else g1, width=1)
    ink = (36, 34, 48); ox = (104, 30, 24); grey = (92, 90, 96)
    # (11-11 late night) the small labels' capitals 0.45 cm (6.3 pt on screen), over MIN_CAP_PT: the proof's were 0.35 cm
    fL = P_.font('BarlowSemiCondensed-700-normal.ttf', 0.66); fS = P_.font('BarlowSemiCondensed-600-normal.ttf', 0.45 / 0.7)
    lab = lambda x, y, t, f=fL, a='m', col=ink: P_.spaced(x, y, t, f, col, 0.12, a)
    # the interface
    P_.box(1.5, 4.5, 8.0, 15.5, ink, 0.07); lab(4.75, 5.4, 'INTERFACE')
    ports = [('OUT 1', 7.0), ('IN 1', 9.5), ('IN 2', 11.0), ('IN 8', 13.6)]
    for t, y in ports:
        d.ellipse([P_.c(7.55), P_.c(y - 0.22), P_.c(8.0 + 0.0), P_.c(y + 0.22)], outline=ink, width=max(1, P_.c(0.05)))
        lab(7.2, y, t, fS, 'r')
    # the amp, into its FX return
    P_.box(11.5, 2.5, 18.0, 6.5, ink, 0.07); lab(14.75, 3.4, 'AMP')
    lab(12.0, 4.6, 'FX RETURN', fS, 'l'); lab(17.6, 5.6, 'SPEAKER', fS, 'r')
    P_.arrow(8.0, 7.0, 10.0, 7.0, ink); P_.line([(10.0, 7.0), (10.0, 4.6), (11.45, 4.6)], ink, 0.04); P_.arrow(11.0, 4.6, 11.5, 4.6, ink)
    # the speaker line to the cab
    P_.line([(18.0, 5.6), (20.4, 5.6)], ink, 0.07)
    # the cab: a box, a cone
    P_.box(20.4, 2.5, 25.0, 12.5, ink, 0.07, 0.15); lab(22.7, 3.3, 'CAB')
    for r_, wd in ((1.7, 0.06), (0.55, 0.05)):
        d.ellipse([P_.c(22.7 - r_), P_.c(8.0 - r_), P_.c(22.7 + r_), P_.c(8.0 + r_)], outline=ink, width=max(1, P_.c(wd)))
    # the mics in front of the cab, their cables back to inputs 1 and 2
    for (mx, my, t, iy) in ((19.0, 8.3, 'MIC 1', 9.5), (19.0, 11.6, 'MIC 2', 11.0)):
        d.rounded_rectangle([P_.c(mx - 1.3), P_.c(my - 0.35), P_.c(mx), P_.c(my + 0.35)], radius=P_.c(0.3), outline=ink, width=max(1, P_.c(0.05)))
        lab(mx - 0.95, my - 0.95, t, fS)
        P_.line([(mx - 1.3, my), (mx - 2.2, my), (mx - 2.2, iy), (8.5, iy)], ink, 0.04); P_.arrow(9.0, iy, 8.05, iy, ink)
    # the reference: the speaker terminals through the pad to input 8 (dashed: optional)
    def dash(pts):
        for (xa, ya), (xb, yb) in zip(pts, pts[1:]):
            L = math.hypot(xb - xa, yb - ya); n = max(1, int(L / 0.45))
            for k in range(0, n, 2):
                t0, t1 = k / n, min(1, (k + 1) / n)
                P_.line([(xa + (xb - xa) * t0, ya + (yb - ya) * t0), (xa + (xb - xa) * t1, ya + (yb - ya) * t1)], ink, 0.04)
    d.ellipse([P_.c(19.1), P_.c(5.45), P_.c(19.4), P_.c(5.75)], fill=ink)
    dash([(19.25, 5.75), (19.25, 14.1), (16.6, 14.1)]); dash([(11.4, 14.1), (8.6, 14.1), (8.6, 13.6), (8.1, 13.6)])
    P_.box(11.5, 13.0, 16.5, 15.2, ink, 0.06); lab(14.0, 13.8, '20 dB PAD'); lab(14.0, 14.6, 'OPTIONAL', fS, col=grey)
    lab(16.9, 14.85, 'SPEAKER TERMINALS', fS, 'l', grey)
    # the monitors, crossed out
    P_.box(2.0, 16.6, 4.4, 19.2, ink, 0.05, 0.12)
    for r_ in (0.6, 0.22): d.ellipse([P_.c(3.2 - r_), P_.c(18.2 - r_), P_.c(3.2 + r_), P_.c(18.2 + r_)], outline=ink, width=max(1, P_.c(0.04)))
    P_.pencil([(1.6, 16.3), (4.8, 19.5)], (150, 40, 34), 0.09); P_.pencil([(4.8, 16.3), (1.6, 19.5)], (150, 40, 34), 0.09)
    lab(5.0, 17.9, 'MONITORS OFF', fL, 'l')
    # the pencilled warning at the amp's input
    pen = (88, 86, 92)
    fM = P_.font('SwellMarker-400-normal.ttf', 0.62)
    d.text((P_.c(8.4), P_.c(0.55)), 'FX return, not the guitar input!', font=fM, fill=pen)
    P_.pencil([(12.4, 1.55), (12.1, 2.35), (12.0, 4.0)], pen, 0.05, 2)
    # the title block
    P_.box(17.6, h - 3.0, w - 0.8, h - 0.8, ox, 0.06, 0.05)
    P_.spaced(17.9, h - 2.35, 'CAB IR  HOOK-UP', P_.font('BarlowSemiCondensed-700-normal.ttf', 0.62), ox, 0.14)
    P_.spaced(17.9, h - 1.4, 'DWG 1  ·  CAB IR', P_.font('BarlowSemiCondensed-600-normal.ttf', 0.45 / 0.7), ox, 0.06)
    age_paper(P_.im, P_.rng).save(path)


def instruction_card(path, w, h, px=110):
    """The card beside the drawing: what to do before and during CHECK LEVELS, typed on a manila card under a printed
    heading. (11-11 late night) typed at 0.74 cm, capitals 6 pt on screen (the proof's 0.6 cm were under MIN_CAP_PT); the
    level check's steps, a checklist beside the pre-flight list until now, folded in as 6 and 7."""
    P_ = Pen(w, h, px, (232, 214, 172), 12)
    ox = (104, 30, 24)
    P_.spaced(1.0, 1.25, 'BEFORE YOU START', P_.font('BarlowSemiCondensed-700-normal.ttf', 0.72), ox, 0.14)
    P_.d.line([P_.p(1.0, 2.0), P_.p(w - 1.0, 2.0)], fill=ox, width=P_.c(0.06))
    ft = P_.font(TYPED, 0.74)
    lines = [('1.', 'Mute the studio monitors.'),
             ('2.', 'An output to the amp\'s FX'), ('', 'return or power amp in.'), ('', 'Not the guitar input.'),
             ('3.', 'Amp master low to start.'),
             ('4.', 'Mics to the inputs. Set'), ('', 'each one to MIC.'),
             ('5.', 'Optional: the speaker'), ('', 'terminals through the'), ('', '20 dB pad to a line input.'), ('', 'Set it to REF.'),
             ('6.', 'Wear ear protection. Warm'), ('', 'a tube amp up for 20 min.'),
             ('7.', 'CHECK LEVELS. Turn each'), ('', 'preamp until OK lights.')]
    y = 2.95
    for num, t in lines:
        if num and y > 3.0: y += 0.22
        if num: P_.typed(0.85, y, num, ft)
        P_.typed(1.85, y, t, ft); y += 0.86
    age_paper(P_.im, P_.rng, (1.0, 0.97, 0.9)).save(path)


def preflight_sheet(path, w, h, px=110):
    """The pre-flight list: a printed form typed in, ticked in pencil, the noisy room ringed in red pencil."""
    P_ = Pen(w, h, px, (246, 234, 200), 13); d = P_.d
    ox = (104, 30, 24); rule = (150, 120, 104)
    fh = P_.font('BarlowSemiCondensed-700-normal.ttf', 0.8); fl = P_.font('BarlowSemiCondensed-600-normal.ttf', 0.48)
    ft = P_.font(TYPED, 0.66)
    m = 1.3
    P_.spaced(m, 1.05, 'BEFORE CAPTURE', fh, ox, 0.14)
    P_.spaced(w - m, 1.15, 'PRE-FLIGHT', fl, ox, 0.16, 'r')
    d.line([P_.p(m, 1.85), P_.p(w - m, 1.85)], fill=ox, width=P_.c(0.07))
    d.line([P_.p(m, 1.98), P_.p(w - m, 1.98)], fill=ox, width=max(1, P_.c(0.02)))
    cols = [('ITEM', 0.0), ('READING', 8.6), ('OK', 34.6)]
    for t, x in cols: P_.spaced(m + x + 0.1, 2.65, t, fl, rule, 0.14)
    rows = [('Mics', '2: SM57, R121', True), ('Reference', 'Input 8', True), ('Sample rate', '96 kHz', True),
            ('Levels', 'All inputs OK', True), ('Sweep level', '-12 dBFS, set automatically', True),
            ('Room noise', 'Room at -38 dBFS: noisy', False)]
    rh = 1.42; y0 = 3.75
    for i, (a, b, ok) in enumerate(rows):
        y = y0 + i * rh
        P_.typed(m + 0.1, y, a, ft); P_.typed(m + 8.7, y, b, ft)
        d.line([P_.p(m, y + 0.72), P_.p(w - m, y + 0.72)], fill=rule, width=max(1, P_.c(0.02)))
        tx = m + 35.1
        if ok:
            j = P_.rng.normal(0, 0.06, 4)
            P_.pencil([(tx + j[0], y + j[1]), (tx + 0.35, y + 0.4), (tx + 1.15 + j[2], y - 0.55 + j[3])], (70, 68, 74), 0.07)
    for x in (8.6, 34.6): d.line([P_.p(m + x - 0.25, 2.2), P_.p(m + x - 0.25, y0 + len(rows) * rh - 0.7)], fill=rule, width=max(1, P_.c(0.02)))
    # the red-pencil ring round the noisy line, and its note
    y = y0 + 5 * rh; red = (176, 40, 34)
    pts = []
    for k in range(80):
        t = 2 * math.pi * k / 79 * 1.08 - 0.3
        pts.append((m + 18.3 + 10.4 * math.cos(t), y + 0.03 + 0.78 * math.sin(t)))
    P_.pencil(pts, red, 0.07, 3, 0.02)
    fM = P_.font('SwellMarker-400-normal.ttf', 0.62)
    d.text((P_.c(m + 29.4), P_.c(y - 0.55)), 'fridge? fan?', font=fM, fill=red)
    age_paper(P_.im, P_.rng).save(path)


def card_frame(sw, sh, ysh, xsh=0.0, name='cardframe'):
    """take sheet's frame: a folded steel channel over the sheet's top and bottom edges, a screw at each end."""
    cm_ = SG.black_cast(name)
    for sy in (1, -1):
        ch = rbox('cframe', sw + 1.6, 0.9, 0.22, 0.0, 0.08, roll=0.05); ch.location = (xsh, ysh + sy * (sh / 2 + 0.1), 0)
        chamfer(ch, 0.012, 1); ch.data.materials.append(cm_)
    small_screws([(xsh + sx * (sw / 2 + 0.45), ysh + sy * (sh / 2 + 0.1)) for sx in (-1, 1) for sy in (-1, 1)], r=0.17)


def unit_chart():
    """6U: the chart panel. The hook-up drawing and the card beside it, each in its card frame."""
    K.set_seed('rack-chart')
    s, cam, h = unit_scene(6)
    backing(h)
    rack_panel(6, 'bronze', 'chart')
    dw, dh, cw_, chh = 26.0, 20.0, 14.6, 20.0
    gap_ = 2.2
    xd = -(dw + gap_ + cw_) / 2 + dw / 2; xc = xd + dw / 2 + gap_ + cw_ / 2
    ysh = 0.9
    fd = os.path.join(OUT, 'wiring-print.png'); wiring_drawing(fd, dw, dh)
    fc = os.path.join(OUT, 'card-print.png'); instruction_card(fc, cw_, chh)
    with moved(xd, ysh, 0): sheet(dw, dh, fd, 'wiring', curl=0.25)
    with moved(xc, ysh, 0): sheet(cw_, chh, fc, 'card', curl=0.0)
    card_frame(dw, dh, ysh, xd, 'cf1'); card_frame(cw_, chh, ysh, xc, 'cf2')
    engrave('HOOK-UP', -dw / 2 + xd + 2.0, -h / 2 + 1.25, 0.5)
    shoot(s, cam, 'unit-chart', PW, h)


def unit_preflight():
    """4U: the pre-flight list in its card frame."""
    K.set_seed('rack-preflight')
    s, cam, h = unit_scene(4)
    backing(h)
    rack_panel(4, 'bronze', 'preflight')
    sw, sh = 40.0, 12.8
    ysh = 0.55
    fp = os.path.join(OUT, 'preflight-print.png'); preflight_sheet(fp, sw, sh)
    with moved(0, ysh, 0): sheet(sw, sh, fp, 'preflight', curl=0.25)
    card_frame(sw, sh, ysh)
    engrave('PRE-FLIGHT', -sw / 2 + 2.2, -h / 2 + 1.1, 0.5)
    shoot(s, cam, 'unit-preflight', PW, h)


# the solid-state parts

def led_m(name, col, on, k=4.0, off='#100a08'):
    return mat(name, srgb(col if on else off), rough=0.3, coat=0.5, coat_rough=0.05,
               emit=srgb(col) if on else None, emit_strength=k if on else 0.0)


SEG7 = {'0': 'abcdef', '1': 'bc', '2': 'abdeg', '3': 'abcdg', '4': 'bcfg', '5': 'acdfg', '6': 'acdefg', '7': 'abc',
        '8': 'abcdefg', '9': 'abcdfg', '-': 'g', ' ': ''}


def led_digits(x, y, text, hgt, z, on_m, off_m, pitch=None):
    """Red seven-segment LED digits (the cart timer's family), every segment present, unlit ones dark; '.' lights the
    point after the digit before it. Returns the cells' total width."""
    cells = []
    for ch in text:
        if ch == '.' and cells: cells[-1][1] = True
        else: cells.append([ch, False])
    pitch = pitch or hgt * 0.74
    w = hgt * 0.5; t = hgt * 0.12; sl = math.tan(math.radians(8))
    x0 = x - pitch * (len(cells) - 1) / 2
    for i, (ch, dp) in enumerate(cells):
        cx = x0 + i * pitch
        segs = {'a': (0, hgt / 2, True), 'g': (0, 0, True), 'd': (0, -hgt / 2, True),
                'f': (-w / 2, hgt / 4, False), 'b': (w / 2, hgt / 4, False), 'e': (-w / 2, -hgt / 4, False), 'c': (w / 2, -hgt / 4, False)}
        for k_, (sx, sy, horiz) in segs.items():
            sw_, sh_ = (w - t, t) if horiz else (t, hgt / 2 - t)
            o = rbox('seg', sw_, sh_, 0.02, z, t * 0.45)
            o.location = (cx + sx + sy * sl, y + sy, 0)
            if not horiz:
                for v in o.data.vertices: v.co.x += v.co.y * sl
            o.data.materials.append(on_m if k_ in SEG7.get(ch, '') else off_m)
        o = rbox('dp', t * 1.1, t * 1.1, 0.02, z, t * 0.5); o.location = (cx + w / 2 + t * 1.4 - hgt / 2 * sl, y - hgt / 2, 0)
        o.data.materials.append(on_m if dp else off_m)
    return pitch * len(cells)


def red_window(plate, cx, cy, ww, wh, name):
    """A black bezelled window with a red filter over a dark back: the LED digits sit in it."""
    ho = rbox('rwh', ww, wh, T + 2, -T - 1, 0.08); ho.location = (cx, cy, 0)
    bpy.context.view_layer.update(); cut(plate, ho)
    bz = rbox('rwbz', ww + 0.8, wh + 0.8, 0.16, 0.0, 0.14, roll=0.05); bz.location = (cx, cy, 0)
    cut(bz, prism('rwbh', [(px + cx, py + cy, pz) for px, py, pz in _rring(ww / 2, wh / 2, 0.08, 0.0, 0, n_arc=8)], -2, 2))
    chamfer(bz, 0.015, 2); bz.data.materials.append(SG.black_cast('rwbz' + name))
    bk = rbox('rwback', ww, wh, 0.05, -0.75, 0.0); bk.location = (cx, cy, 0)
    bk.data.materials.append(mat('rwback', srgb('#0a0605'), rough=0.7))
    f = rbox('rwfilt', ww + 0.1, wh + 0.1, 0.05, -0.1, 0.0); f.location = (cx, cy, 0)
    f.data.materials.append(mat('rwfilt', srgb('#d02a18'), rough=0.06, transm=1.0, ior=1.0, spec=0.0))
    f.visible_shadow = False; GLASS.append(f)
    return -0.7          # the digits' z


def flush_led(x, y, col, on, r=0.26, k=3.5, sat=False):
    """A flush 5 mm LED in a black collar. k: the lit emission (under AgX a strong one washes to white)."""
    T_ = _tape()
    T_.cyl('ledcol', r + 0.14, 0.0, 0.1, x, y, 48, SG.black_cast('ledcol'))
    dark = {'green': '#0c2010', 'amber': '#2a1606', 'red': '#2a0806', 'white': '#24201a'}[col]
    hot = {'green': '#38f070', 'amber': '#ffa028', 'red': '#ff2a14', 'white': '#fff0d0'}[col]
    if sat:
        # (11-11 late, Lowell: the NAM strip's LEDs "a little pastel") under the Standard view a lit colour with any red
        # and blue in it clips to a pale tint, and a lens whose base is the hot colour adds the studio's white light on
        # top. Saturated: the emission nearly a primary, the lens's own colour dark, its coat thinner.
        # Blender 5's Standard view also rolls bright values off toward white, so the emission is kept low (k about
        # 0.5 to 0.8), hotter in the middle of the lens than at its rim, as a diffused 5 mm LED.
        hot = {'green': '#08ff26', 'amber': '#ff8a00', 'red': '#ff1000', 'white': '#fff0d0'}[col]
        m = mat('ledS' + col + str(on) + str(k), srgb(dark), rough=0.32, coat=0.3, coat_rough=0.08,
                emit=srgb(hot) if on else None, emit_strength=k if on else 0.0)
        if on:
            nt = m.node_tree; b = nt.nodes['Principled BSDF']; co = obj_coords(nt)
            sep = node(nt, 'ShaderNodeSeparateXYZ'); nt.links.new(co, sep.inputs[0])
            cx = node(nt, 'ShaderNodeCombineXYZ'); nt.links.new(sep.outputs['X'], cx.inputs['X']); nt.links.new(sep.outputs['Y'], cx.inputs['Y'])
            ln = node(nt, 'ShaderNodeVectorMath', operation='LENGTH'); nt.links.new(cx.outputs[0], ln.inputs[0])
            st = node(nt, 'ShaderNodeMapRange', **{'From Min': 0.0, 'From Max': r, 'To Min': 1.45 * k, 'To Max': 0.6 * k})
            st.interpolation_type = 'SMOOTHSTEP'; nt.links.new(ln.outputs['Value'], st.inputs['Value'])
            nt.links.new(st.outputs['Result'], b.inputs['Emission Strength'])
        T_.cyl('led', r, 0.0, 0.18, x, y, 48, m)
        return
    T_.cyl('led', r, 0.0, 0.18, x, y, 48, led_m('led' + col + str(on) + str(k), hot, on, k, dark))


BAR = dict(n=20, w=0.34, h=1.25, pitch=0.465)


def bar_colour(i):
    return 'green' if i < 17 else ('amber' if i < 19 else 'red')


def bargraph(plate, cx, cy, level_db, name):
    """The NAM level: twenty LED bars, -40 to 0 dBFS in 2 dB steps, behind smoked glass in a black bezel."""
    n, bw, bh, pp = BAR['n'], BAR['w'], BAR['h'], BAR['pitch']
    ww, wh = n * pp + 0.5, bh + 0.7
    ho = rbox('bgh', ww, wh, T + 2, -T - 1, 0.08); ho.location = (cx, cy, 0)
    bpy.context.view_layer.update(); cut(plate, ho)
    bz = rbox('bgbz', ww + 0.8, wh + 0.8, 0.16, 0.0, 0.14, roll=0.05); bz.location = (cx, cy, 0)
    cut(bz, prism('bgbh', [(px + cx, py + cy, pz) for px, py, pz in _rring(ww / 2, wh / 2, 0.08, 0.0, 0, n_arc=8)], -2, 2))
    chamfer(bz, 0.015, 2); bz.data.materials.append(SG.black_cast('bgbz' + name))
    bk = rbox('bgback', ww, wh, 0.05, -0.75, 0.0); bk.location = (cx, cy, 0)
    bk.data.materials.append(mat('bgback', srgb('#070707'), rough=0.7))
    lit = int(max(0, min(n, round((level_db + 40) / 2))))
    ms = {}
    for i in range(n):
        c = bar_colour(i); on = i < lit
        key_ = (c, on)
        if key_ not in ms:
            hot = {'green': '#38f070', 'amber': '#ffa028', 'red': '#ff2a14'}[c]
            dark = {'green': '#08140a', 'amber': '#160c04', 'red': '#180504'}[c]
            ms[key_] = led_m('bar%s%d' % key_, hot, on, 3.0, dark)
        o = rbox('bar', bw, bh, 0.06, -0.7, 0.03); o.location = (cx - (n - 1) * pp / 2 + i * pp, cy, 0)
        o.data.materials.append(ms[key_])
    g = rbox('smoke', ww + 0.1, wh + 0.1, 0.05, -0.1, 0.0); g.location = (cx, cy, 0)
    g.data.materials.append(mat('smoke', srgb('#6a665e'), rough=0.05, transm=1.0, ior=1.0, spec=0.0))
    g.visible_shadow = False; GLASS.append(g)
    return ww + 0.8, wh + 0.8


NAM_MODS = [dict(name='LINE OUT', v='a', db=-8.4, peak='-8.2', lamps=('OK',)),
            dict(name='SM57 CAP EDGE', v='b', db=-7.6, peak='-7.4', lamps=('OK',)),
            dict(name='R121 CENTER', v='c', db=-21.0, peak='-20.6', lamps=('LOW',)),
            None]
NLAMPS = [('LOW', 'amber'), ('OK', 'green'), ('HIGH', 'amber'), ('CLIP', 'red')]
NMH = 12.6


def nam_module(mo):
    K.set_seed('rack-nmod-' + (mo['name'] if mo else 'blank'))
    pl = rbox('nplate', MW, NMH, MZ, -MZ, 0.18, roll=0.05)
    if mo is None:                      # a blank filler plate in the empty slot
        chamfer(pl, 0.015, 2); TK.flat_faces(pl); pl.data.materials.append(K.anodised('nblank', base='#2a2a2c'))
        small_screws([(sx * (MW / 2 - 0.45), sy * (NMH / 2 - 0.45)) for sx in (-1, 1) for sy in (-1, 1)], seed=5)
        return
    yb = NMH / 2 - 1.65
    bgw, bgh = bargraph(pl, 0.0, yb, mo['db'], mo['name'])
    yp = yb - bgh / 2 - 1.15 - 1.4
    pw_, ph_ = 6.3, 2.2
    zd = red_window(pl, -1.85, yp, pw_, ph_, mo['name'])
    chamfer(pl, 0.015, 2); TK.flat_faces(pl)
    pl.data.materials.append(K.anodised('nmod-' + mo['name'], base='#2e2e30'))
    small_screws([(sx * (MW / 2 - 0.45), sy * (NMH / 2 - 0.45)) for sx in (-1, 1) for sy in (-1, 1)], seed=K.seed_of(mo['name']) % 7)
    on_m = led_m('dseg-on', '#ff3418', True, 5.0); off_m = led_m('dseg-off', '#ff3418', False, off='#1a0605')
    led_digits(-1.85, yp, '%5s' % mo['peak'], 1.4, zd, on_m, off_m)
    # the scale under the bars
    n, pp = BAR['n'], BAR['pitch']
    for db in (-40, -20, -12, -8, -4, 0):
        i = (db + 40) / 2 - 0.5
        x = -(n - 1) * pp / 2 + i * pp
        engrave(str(db), max(-(n - 1) * pp / 2, min((n - 1) * pp / 2, x)), yb - bgh / 2 - 0.5, 0.38, track=0.06)
    engrave('PEAK  dBFS', -1.85, yp - ph_ / 2 - 0.9, 0.44, track=0.14)
    # the lamps: a 2 x 2 block right of the digits
    for i, (lab, col) in enumerate(NLAMPS):
        lx = 2.85 + (i % 2) * 1.7; ly = yp + 0.62 - (i // 2) * 1.55
        flush_led(lx, ly, col, lab in mo['lamps'])
        engrave(lab, lx, ly - 0.62, 0.38, track=0.1)
    ys = -NMH / 2 + 0.55 + K.SCRIB['h'] / 2
    with moved(0, ys, 0): strip(mo['v'], 10.2, mo['name'], mo['name'])


def unit_nammeters():
    """3U: the NAM meter bridge: three channel modules (LED bargraph, red LED peak, LED lamps, scribble strip) and a
    blank plate in the fourth slot."""
    K.set_seed('rack-nmeters')
    s, cam, h = unit_scene(3)
    backing(h)
    fr, hh = rack_panel(3, 'alu', 'nbridge')
    op = rbox('fopen', 4 * MW + 0.1, NMH - 0.6, 4, -2, 0.1); bpy.context.view_layer.update(); cut(fr, op)
    fr.data.materials.append(K.anodised('nbridge', base='#232325'))
    for i, mo in enumerate(NAM_MODS):
        with moved((i - 1.5) * (MW + 0.06), 0, MZ): nam_module(mo)
    finish_glass()
    shoot(s, cam, 'unit-nammeters', PW, h)


def dome_lens(name, base, glow, lit):
    """A domed square lens: frosted resin; lit, brightest in the middle and falling off to the edges (no flat block)."""
    m = mat(name, srgb(base), rough=0.32, coat=0.6, coat_rough=0.06, spec=0.45)
    nt = m.node_tree; b = nt.nodes['Principled BSDF']; co = obj_coords(nt)
    add_bump(m, noise(nt, co, 160.0, 2.0, 0.5), 0.1, 0.001)
    if lit:
        b.inputs['Emission Color'].default_value = (*srgb(glow), 1)
        ln = node(nt, 'ShaderNodeVectorMath', operation='LENGTH'); nt.links.new(co, ln.inputs[0])
        st = node(nt, 'ShaderNodeMapRange', **{'From Min': 0.0, 'From Max': 1.5, 'To Min': 1.6, 'To Max': 0.35})
        st.interpolation_type = 'SMOOTHSTEP'; nt.links.new(ln.outputs['Value'], st.inputs['Value'])
        nt.links.new(st.outputs['Result'], b.inputs['Emission Strength'])
    surface_wear(m, smudge=0.5, scuff=0.25)
    return m


def unit_cart():
    """3U: the cart machine (Amp NAM's recorder), graphite anodised. The cart in its slot with the signal's map on its
    label; domed lit keys CHECK / RECORD / STOP; READY and the two cue LEDs; the red LED timer (time left)."""
    T_ = _tape()
    prog = float(os.environ.get('IRC_CART_PROG', '0.4'))
    K.set_seed('rack-cart')
    s, cam, h = unit_scene(3)
    backing(h)
    pl, ph = rack_panel(3, 'alu', 'cart')
    blk = SG.black_cast('bc')
    sx0, sy0, sw, sh = -9.6, 2.35, 16.2, 3.1
    cut(pl, prism('slot', [(x + sx0, y + sy0, z) for x, y, z in _rring(sw / 2, sh / 2, 0.25, 0.0, 0, n_arc=8)], -2, 2))
    # the timer's window
    tx, tyy = 5.2, -1.9
    zd = red_window(pl, tx, tyy, 6.6, 2.4, 'timer')
    pl.data.materials.append(K.anodised('cartface', base='#2a2a2c'))
    throat = rbox('throat', sw - 0.1, sh - 0.1, 0.1, -2.6, 0.2); throat.location = (sx0, sy0, 0)
    throat.data.materials.append(mat('throat', srgb('#0d0c0b'), rough=0.85))
    cw_, ch_ = 15.2, 2.45
    shell = rbox('cart', cw_, ch_, 4.0, -2.6, 0.18, roll=0.04); shell.location = (sx0, sy0 - 0.15, 0)
    shm = mat('cartshell', srgb('#2b2927'), rough=0.42, coat=0.25, coat_rough=0.25)
    add_bump(shm, noise(shm.node_tree, obj_coords(shm.node_tree), 90.0, 2.0, 0.5), 0.08, 0.001); surface_wear(shm, dust=0.4, smudge=0.5, scuff=0.5)
    shell.data.materials.append(grimy(shm, dirt='#3a3228', amount=0.35, dist=0.05))
    for gx in (-1, 1):
        for i in range(4):
            gr = rbox('grip', 0.06, ch_ - 0.7, 0.05, 1.4, 0.02); gr.location = (sx0 + gx * (cw_ / 2 - 0.45 - i * 0.16), sy0 - 0.15, 0)
            gr.data.materials.append(shm)
    lw, lh = 12.6, 1.9
    T_.HERE = os.path.dirname(os.path.abspath(__file__))       # the label's map: reference/nam_v3_map.json in this repo
    T_.img_plane('cartlabel', T_.cart_label_tex(lw, lh, 110), lw, lh, sx0, sy0 - 0.15, 1.402)
    phd = rbox('phead', 0.06, 0.95, 0.01, 1.404, 0.0)
    phd.location = (sx0 - lw / 2 + 0.25 + (lw - 0.5) * prog, sy0 - 0.15 - lh / 2 + 1.02 / 1.9 * lh, 0)
    phd.data.materials.append(mat('phm', srgb('#d01a10'), rough=0.5, emit=srgb('#ff2010'), emit_strength=0.6))
    # the keys: domed square lenses in black bezels, their names engraved under them
    ky = -3.0; ks = 2.3
    for lab, kx, base, glow, lit in (('CHECK', -15.2, '#b07a2c', '#ffa030', False), ('RECORD', -9.6, '#5a0c06', '#ff2a10', True),
                                     ('STOP', -4.0, '#c6bfae', '#fff0d0', False)):
        bz = rbox('kbz', ks + 0.55, ks + 0.55, 0.22, 0.0, 0.22, roll=0.06); bz.location = (kx, ky, 0)
        cut(bz, prism('kh', [(x + kx, y + ky, z) for x, y, z in _rring(ks / 2 + 0.04, ks / 2 + 0.04, 0.16, 0.0, 0, n_arc=8)], -2, 2))
        chamfer(bz, 0.02, 2); bz.data.materials.append(blk)
        # (first test) a deep roll creased the lens corner to corner: a shallow roll, flat faces, and the dome left to
        # the lens's light falling off to its edges
        cap = rbox('lens', ks, ks, 0.5, -0.1, 0.16, roll=0.06); TK.flat_faces(cap); cap.location = (kx, ky, 0)
        lm = dome_lens('lens' + lab, base, glow, lit); cap.data.materials.append(lm)
        # the dome: a cushion over the lens's top, smooth, so the light lies on it as a soft highlight
        a_ = ks / 2 - 0.05
        bpy.ops.mesh.primitive_grid_add(x_subdivisions=48, y_subdivisions=48, size=2 * a_, location=(kx, ky, 0.4))
        dm = bpy.context.active_object; dm.name = 'dome'
        for v in dm.data.vertices:
            u_, w_ = v.co.x / a_, v.co.y / a_
            v.co.z = 0.24 * max(0.0, 1 - u_ ** 4) * max(0.0, 1 - w_ ** 4)
        bpy.ops.object.shade_smooth(); dm.data.materials.append(lm)
        if lit:
            Lk = bpy.data.lights.new('kg', 'POINT'); Lk.energy = 0.3; Lk.color = srgb(glow); Lk.shadow_soft_size = 0.8
            g = bpy.data.objects.new('kg', Lk); s.collection.objects.link(g); g.location = (kx, ky, 1.4)
        engrave(lab, kx, ky - ks / 2 - 0.75, 0.44, track=0.14)
    # READY and the cues, right of the slot
    for i, (lab, col, on) in enumerate((('READY', 'green', True), ('CUE 1', 'amber', True), ('CUE 2', 'amber', True))):
        lx = 1.4 + i * 2.6
        flush_led(lx, 3.1, col, on); engrave(lab, lx, 2.25, 0.4, track=0.1)
    # the timer: time left in the take, M:SS
    left = int(round(190 * (1 - prog)))
    on_m = led_m('tseg-on', '#ff3418', True, 5.0); off_m = led_m('tseg-off', '#ff3418', False, off='#1a0605')
    hgt = 1.5; pp = hgt * 0.74
    led_digits(tx - 1.75, tyy, '%d' % (left // 60), hgt, zd, on_m, off_m)
    led_digits(tx + 0.75, tyy, '%02d' % (left % 60), hgt, zd, on_m, off_m)
    for dy in (0.33, -0.33):
        o = rbox('colon', 0.18, 0.18, 0.02, zd, 0.09); o.location = (tx - 0.95 + dy * 0.14, tyy + dy, 0); o.data.materials.append(on_m)
    engrave('TIME LEFT', tx, tyy - 1.2 - 0.85, 0.44, track=0.14)
    engrave('CARTRIDGE', 16.0, 0.9, 0.62, track=0.2)
    engrave('NAM SIGNAL', 16.0, -0.45, 0.44, track=0.2, color='#a8a298')
    finish_glass()
    shoot(s, cam, 'unit-cart', PW, h, {'prog': prog})


UNITS = {'step': unit_step, 'patch': unit_patch, 'meters': unit_meters, 'gap': unit_gap, 'deck': unit_deck,
         'results': unit_results, 'cheeks': unit_cheeks, 'chart': unit_chart, 'preflight': unit_preflight,
         'nammeters': unit_nammeters, 'cart': unit_cart}


def main():
    todo = ['step', 'patch', 'meters', 'gap', 'results'] if WHAT == 'all' else WHAT.split(',')
    for u in todo:
        t = time.time(); UNITS[u](); print('unit', u, '%.0fs' % (time.time() - t), flush=True)


if __name__ == '__main__':
    main()
