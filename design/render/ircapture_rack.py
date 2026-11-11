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


UNITS = {'step': unit_step, 'patch': unit_patch, 'meters': unit_meters, 'gap': unit_gap, 'deck': unit_deck,
         'results': unit_results, 'cheeks': unit_cheeks}


def main():
    todo = [u for u in UNITS if u not in ('cheeks', 'deck')] if WHAT == 'all' else WHAT.split(',')
    for u in todo:
        t = time.time(); UNITS[u](); print('unit', u, '%.0fs' % (time.time() - t), flush=True)


if __name__ == '__main__':
    main()
