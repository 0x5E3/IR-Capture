# ircapture_tape.py: tape machines for IR Capture (Phase 7 round 3 concept, 2026-11-03).
#
# Lowell, 11-03, on round 2: "a tape for the IR side would be really cool too. 3D with heads or something. in fact maybe
# making this device somewhat tape based in general? tape for one, something else for the other? different tape styles?
# i think people will use this program for IRs more so we should make that the focus".
#
#   reel     CAB IR: a 1960s open-reel recorder. Bronze fine hammertone case, a satin aluminium deck plate, two 7 inch
#            aluminium reels of brown oxide tape, a head block (erase, record, play) under a black cast hood, guide posts,
#            a steel capstan and a rubber pinch roller, a mechanical counter, the shelf's illuminated keys for the real
#            actions only (CHECK LEVELS, CAPTURE, STOP) and a red jewel for record. The tape pack on each reel is the
#            capture's progress (the supply reel empties as the sweeps play).
#   cassette AMP NAM: a late-1970s/80s front-loading cassette deck, a little more modern: graphite anodised face, a
#            smoked window on the cassette well, the cassette's label carrying the training signal's map (sweeps,
#            noise, guitar), soft-touch keys, a three-digit counter.
#
# Round 3b (Lowell, 11-03: "r2r looks good, broadcast cart would be better", "warm brushed"):
#   reel     the deck plate is warm brushed aluminium (PLATE=satin for round 3's plate); the deck is 27 cm tall, head
#            block between the reels and the keys along the bottom, so it and a seven-input meter bridge fit the window.
#   cart     AMP NAM: a broadcast cart machine replaces the cassette deck (piece_cart, below).
#
# Same studio, camera and light as every other IR Capture piece (toolkit.scene(): orthographic, 10 degrees above, key
# light up left). Concept proofs: one whole picture each. Split into layers (deck, reels at frames, tape packs) only once
# Lowell picks a direction.
#
#   FONTS_DIR=Resources/SwellKit/fonts ~/bvenv/bin/python design/render/ircapture_tape.py <out dir> reel|cart|cassette [px/cm] [samples] [progress 0..1]
import sys, os, math, json, time
HERE = os.path.dirname(os.path.abspath(__file__))
_argv = sys.argv[:]
OUT = _argv[1] if len(_argv) > 1 else '/tmp/irtape'
WHAT = _argv[2] if len(_argv) > 2 else 'reel'
PXCM = float(_argv[3]) if len(_argv) > 3 else 24.0
SAMPLES = int(_argv[4]) if len(_argv) > 4 else 16
PROG = float(_argv[5]) if len(_argv) > 5 else 0.4
sys.argv = [_argv[0], OUT, 'none', str(PXCM), str(SAMPLES)]
import ircapture_kit as K                     # brings the bench's scripts onto the path and sets TK's globals
sys.argv = _argv
import bpy, bmesh
import numpy as np
from PIL import Image
import parts as P
from parts import mat, srgb, lathe, _rring
from gear_kit import rbox, cut, chamfer, surface_wear, screw, node, obj_coords, add_bump, mix_into, edge_mask, noise, mul, autosmooth
from instrument import grimy, prism
import toolkit as TK
import shelf_gear as SG
TK.OUT, TK.PXCM, TK.SAMPLES = OUT, PXCM, SAMPLES
os.makedirs(OUT, exist_ok=True)
LAY = {'pxcm': PXCM, 'samples': SAMPLES, 'out': {}}


# ---------------------------------------------------------------------------------------------------------------------
# helpers

def cyl(name, r, z0, z1, x=0.0, y=0.0, n=128, m=None):
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=z1 - z0, vertices=n, location=(x, y, (z0 + z1) / 2))
    o = bpy.context.active_object; o.name = name
    if m: o.data.materials.append(m)
    return o


def screw_at(x, y, z, m):
    before = set(bpy.data.objects)
    screw(x, y, m)
    for o in set(bpy.data.objects) - before: o.location.z += z


def outline_prism(name, pts, z0, z1):
    return prism(name, [(x, y, 0) for x, y in pts], z0, z1)


def ink(text, x, y, z, cap, color='#d8d0bd', kind='cap', track=0.16, w=None, m_name=None):
    """A legend printed or engraved and filled on a flat face at depth z, centred on (x, y), capitals cap cm tall."""
    wcm = w or cap * (len(text) * 0.9 + 2); hcm = cap * 2.4
    mk = SG.legend_mask(text, wcm, hcm, cap, ppcm=max(120, int(PXCM * 4)), track=track, kind=kind)
    bpy.ops.mesh.primitive_plane_add(size=1, location=(x, y, z + 0.003)); o = bpy.context.active_object
    o.scale = (wcm, hcm, 1)
    m = mat(m_name or ('ink' + text[:6]), srgb(color), rough=0.6, spec=0.3); nt = m.node_tree; b = nt.nodes['Principled BSDF']
    t = SG.img_tex(nt, 'm' + text[:8], mk, False, 'CLIP')
    uv = nt.nodes.new('ShaderNodeTexCoord'); nt.links.new(uv.outputs['UV'], t.inputs['Vector'])
    co = obj_coords(nt)
    a = mul(nt, t.outputs['Color'], noise(nt, co, 30.0, 3.0, 0.6, lo=0.05, hi=0.35))
    nt.links.new(a, b.inputs['Alpha'])
    o.data.materials.append(m)
    return o


def ribbon(name, pts, z0, z1, m):
    """A tape: the polyline pts (x, y) swept from z0 to z1, a hair thick."""
    verts, faces = [], []
    for x, y in pts: verts += [(x, y, z0), (x, y, z1)]
    for i in range(len(pts) - 1):
        a = 2 * i; faces.append((a, a + 2, a + 3, a + 1))
    me = bpy.data.meshes.new(name); me.from_pydata(verts, [], faces); me.update()
    o = bpy.data.objects.new(name, me); bpy.context.scene.collection.objects.link(o)
    sm = o.modifiers.new('th', 'SOLIDIFY'); sm.thickness = 0.02
    o.data.materials.append(m)
    return o


def tape_path(circles, step=0.08):
    """circles: [((cx, cy), r, s)], s = +1 counter-clockwise round it, -1 clockwise. The tape's polyline: each common
    tangent between neighbours, and the wrap round every circle between them (none on the first and last)."""
    def perp(v): return np.array([-v[1], v[0]])
    tans = []
    for (c1, r1, s1), (c2, r2, s2) in zip(circles, circles[1:]):
        c1 = np.array(c1, float); c2 = np.array(c2, float)
        D = c2 - c1; k = s2 * r2 - s1 * r1; L = math.sqrt(D @ D - k * k)
        t = (L * D - k * perp(D)) / (D @ D)
        tans.append((c1 - s1 * r1 * perp(t), c2 - s2 * r2 * perp(t)))
    pts = [tans[0][0], tans[0][1]]
    for i in range(1, len(circles) - 1):
        (c, r, s) = circles[i]; c = np.array(c, float)
        a0 = math.atan2(*(tans[i - 1][1] - c)[::-1]); a1 = math.atan2(*(tans[i][0] - c)[::-1])
        da = (a1 - a0) % (2 * math.pi) if s > 0 else -((a0 - a1) % (2 * math.pi))
        n = max(2, int(abs(da) * r / step))
        for j in range(1, n + 1):
            a = a0 + da * j / n; pts.append(c + r * np.array([math.cos(a), math.sin(a)]))
        pts.append(tans[i][1])
    return [tuple(p) for p in pts]


# ---------------------------------------------------------------------------------------------------------------------
# materials

def satin_alu(name='deckalu', base='#b2a993'):
    """The deck plate: satin aluminium, a fine brushing along x, gone a little warm and dull with age, rubbed at the
    edges, handling marks round the keys."""
    m = mat(name, srgb(base), rough=0.34, metal=0.9, spec=0.5)
    nt = m.node_tree; co = obj_coords(nt)
    st = node(nt, 'ShaderNodeMapping'); st.inputs['Scale'].default_value = (0.015, 1.0, 1.0); nt.links.new(co, st.inputs[0])
    br = noise(nt, st.outputs[0], 22.0, 6.0, 0.7, lo=0.3, hi=0.7)
    add_bump(m, br, 0.08, 0.002)
    mix_into(m, 'Roughness', mul(nt, br, 0.5), 0.22, 'FLOAT')
    mix_into(m, 'Base Color', mul(nt, noise(nt, co, 0.3, 3.0, 0.55, lo=0.35, hi=0.75), 0.5), (*srgb('#8f8676'), 1))
    mix_into(m, 'Base Color', mul(nt, noise(nt, co, 1.2, 4.0, 0.6, lo=0.5, hi=0.8), 0.3), (*srgb('#b8b2a4'), 1))
    surface_wear(m, dust=0.3, smudge=0.5, scuff=0.4)
    return grimy(m, dirt='#3b3428', amount=0.45, dist=0.1)


def brushed_alu(name='deckbrush', base='#bdae90'):
    """The deck plate (Lowell, 11-03: "warm brushed"): aluminium brushed along x, the grain long and visible, an
    anisotropic sheen that runs across the plate, gone warm with age; rubbed edges, handling marks round the keys."""
    m = mat(name, srgb(base), rough=0.3, metal=0.92, spec=0.5, aniso=0.55)
    nt = m.node_tree; b = nt.nodes['Principled BSDF']; co = obj_coords(nt)
    tg = node(nt, 'ShaderNodeTangent'); tg.direction_type = 'RADIAL'; tg.axis = 'Y'   # radial round y: the tangent runs along x
    nt.links.new(tg.outputs['Tangent'], b.inputs['Tangent'])
    # the grain: noise stretched 200:1 along x, two scales (the brush's long strokes and the fine hairlines)
    st = node(nt, 'ShaderNodeMapping'); st.inputs['Scale'].default_value = (0.005, 1.0, 1.0); nt.links.new(co, st.inputs[0])
    hair = noise(nt, st.outputs[0], 90.0, 4.0, 0.65, lo=0.25, hi=0.75)
    st2 = node(nt, 'ShaderNodeMapping'); st2.inputs['Scale'].default_value = (0.02, 1.0, 1.0); nt.links.new(co, st2.inputs[0])
    stroke = noise(nt, st2.outputs[0], 6.0, 3.0, 0.55, lo=0.3, hi=0.7)
    add_bump(m, hair, 0.12, 0.0015)
    mix_into(m, 'Roughness', mul(nt, hair, 0.6), 0.44, 'FLOAT')
    mix_into(m, 'Base Color', mul(nt, stroke, 0.35), (*srgb('#a89a7e'), 1))
    mix_into(m, 'Base Color', mul(nt, hair, 0.25), (*srgb('#cbbfa6'), 1))
    # age: a soft warm cloud, darker toward the edges
    mix_into(m, 'Base Color', mul(nt, noise(nt, co, 0.3, 3.0, 0.55, lo=0.35, hi=0.75), 0.45), (*srgb('#968a72'), 1))
    surface_wear(m, dust=0.3, smudge=0.5, scuff=0.35)
    return grimy(m, dirt='#3b3428', amount=0.45, dist=0.1)


def reel_alu(name='reelalu'):
    m = mat(name, srgb('#b9b6ae'), rough=0.3, metal=1.0, spec=0.5)
    nt = m.node_tree; co = obj_coords(nt)
    # turned: fine concentric tool marks
    wv = node(nt, 'ShaderNodeTexWave', Scale=6.0); wv.wave_type = 'RINGS'; wv.rings_direction = 'Z'
    try: wv.inputs['Distortion'].default_value = 0.4
    except Exception: pass
    nt.links.new(co, wv.inputs['Vector'])
    add_bump(m, wv.outputs['Fac'], 0.05, 0.001)
    mix_into(m, 'Roughness', mul(nt, wv.outputs['Fac'], 0.3), 0.2, 'FLOAT')
    surface_wear(m, dust=0.2, smudge=0.45, scuff=0.55)
    return grimy(m, dirt='#3b3428', amount=0.4, dist=0.08)


def oxide(name='oxide'):
    """Brown oxide tape: the pack's face a dull chocolate brown with a soft sheen. (The earlier node set, with ring
    colour and roughness mixes, shaded the pack nearly black; a plain material reads as tape.)"""
    return mat(name, srgb('#86603f'), rough=0.42, spec=0.45)


def mu_metal(name='mu'):
    m = mat(name, srgb('#c9c6bd'), rough=0.18, metal=1.0)
    surface_wear(m, smudge=0.4, scuff=0.3)
    return grimy(m, dirt='#2f291f', amount=0.4, dist=0.05)


def black_rubber(name='pinch'):
    m = mat(name, srgb('#141312'), rough=0.7, spec=0.35)
    nt = m.node_tree; co = obj_coords(nt)
    add_bump(m, noise(nt, co, 60.0, 2.0, 0.5), 0.1, 0.002)
    surface_wear(m, dust=0.4)
    return m


# ---------------------------------------------------------------------------------------------------------------------
# the open-reel recorder (CAB IR)

# Round 3b (11-03): 27 cm tall instead of 36, so the deck and a six-mic meter bridge fit the 920 x 960 pt window: the
# head block sits between the reels, the keys run along the bottom edge under it.
REEL = dict(w=72.0, h=27.0, case_d=3.0, plate_inset=1.6, rx=22.5, ry=1.5, R=8.9, hub=3.0, tape=0.635, z_reel=1.2,
            pack_full=8.3, ty=-7.0)


def reel(x, y, rp, ang, alu, tape_m, chrome, black):
    """A 7 inch reel on its turntable: rear and front flanges with three windows each, the hub, the tape pack to radius
    rp, the three-prong hold-down."""
    R, hub, zt = REEL['R'], REEL['hub'], REEL['z_reel']
    cyl('turntable', 4.2, 0.25, zt - 0.05, x, y, 128, black)
    zf0, zf1 = zt, zt + 0.11                        # rear flange
    zt0, zt1 = zf1 + 0.02, zf1 + 0.02 + REEL['tape']
    zg0 = zt1 + 0.02; zg1 = zg0 + 0.11              # front flange
    for nm, a, b in (('rear', zf0, zf1), ('front', zg0, zg1)):
        f = cyl('fl' + nm, R, a, b, 0, 0, 256)
        for k in range(3):
            a0 = ang + k * 2 * math.pi / 3 + math.radians(14); a1 = a0 + math.radians(92)
            r0, r1, rc = hub + 0.9, R - 0.9, 0.55
            pts = []
            for i in range(41): t = a0 + (a1 - a0) * i / 40; pts.append((r1 * math.cos(t), r1 * math.sin(t)))
            for i in range(41): t = a1 - (a1 - a0) * i / 40; pts.append((r0 * math.cos(t), r0 * math.sin(t)))
            # round the window's corners a little by pulling the ends in
            cutter = outline_prism('win', pts, a - 1, b + 1)
            cut(f, cutter)
        chamfer(f, 0.03, 2); f.data.materials.append(alu)
        f.location = (x, y, (a + b) / 2)
        # the turned rim: a rolled lip
        lip = lathe('lip', [(R + 0.02, a), (R + 0.06, (a + b) / 2), (R + 0.02, b), (R - 0.15, b)], 256)
        lip.location = (x, y, 0); lip.data.materials.append(alu)
    hb = cyl('hub', hub, zf0, zg1 + 0.02, x, y, 128, alu)
    if rp > hub + 0.05:
        pk = lathe('pack', [(hub, zt0), (rp, zt0), (rp, zt1), (hub, zt1)], 256, smooth=False)   # flat: smooth normals across the pack's square corners shaded its face black
        pk.location = (x, y, 0); pk.data.materials.append(tape_m)
        # (no separate top disc: one coplanar with the pack's own face shadowed it black)
    # the hold-down: a chrome boss and three prongs
    bo = lathe('boss', [(1.1, zg1), (1.1, zg1 + 0.35), (0.9, zg1 + 0.55), (0.35, zg1 + 0.62), (0.0, zg1 + 0.64)], 96)
    bo.location = (x, y, 0); bo.data.materials.append(chrome)
    for k in range(3):
        t = ang + k * 2 * math.pi / 3 + math.radians(60)
        p = rbox('prong', 0.5, 1.5, 0.22, zg1 + 0.32, 0.2, roll=0.08)
        p.rotation_euler = (0, 0, t - math.pi / 2); p.location = (x + 0.95 * math.cos(t), y + 0.95 * math.sin(t), 0)
        p.data.materials.append(chrome)
    return zt0, zt1


def piece_reel(prog):
    W_, H_ = REEL['w'], REEL['h']
    s, cam = TK.scene(W_, H_, 1.0)
    TK.catcher(-REEL['case_d'])
    # the case: bronze fine hammertone, the deck plate set in it
    case = rbox('case', W_, H_, REEL['case_d'], -REEL['case_d'], 1.0, roll=0.35)
    TK.flat_faces(case); case.data.materials.append(K.hammertone_fine(name='casehammer'))
    pw, ph = W_ - 2 * REEL['plate_inset'], H_ - 2 * REEL['plate_inset']
    plate = rbox('plate', pw, ph, 0.25, 0.0, 0.6, roll=0.08)
    TK.flat_faces(plate); plate.data.materials.append(brushed_alu() if os.environ.get('PLATE', 'brushed') == 'brushed' else satin_alu())
    ni = TK.nickel(); ch = SG.chrome('chr', seed=3); blk = SG.black_cast('bc'); alu = reel_alu(); tp = oxide()
    for sx in (-1, 1):
        for sy in (-1, 1):
            screw_at(sx * (pw / 2 - 0.9), sy * (ph / 2 - 0.9), 0.25, ni)
    rx, ry = REEL['rx'], REEL['ry']
    full, hub = REEL['pack_full'], REEL['hub']
    # equal tape length: the areas of the two packs add up to one full pack
    A = full * full - hub * hub
    rs = math.sqrt(hub * hub + A * (1 - prog)); rt = math.sqrt(hub * hub + A * prog)
    zt0, zt1 = reel(-rx, ry, rs, 0.3, alu, tp, ch, blk)
    reel(rx, ry, rt, 1.4, alu, tp, ch, blk)
    # the head block: a cast base, three heads, a hood behind, guides, the capstan and the pinch roller
    ty = REEL['ty']
    base = rbox('hbase', 28.0, 5.6, 0.6, 0.25, 0.4, roll=0.12); base.location = (0, ty + 3.4, 0)
    chamfer(base, 0.02, 2); base.data.materials.append(K.hammertone_fine(base='#191612', hi='#2e271e', name='hbase'))
    hood = rbox('hood', 17.5, 2.4, 1.6, 0.85, 0.6, roll=0.35); hood.location = (-1.5, ty + 4.9, 0)
    chamfer(hood, 0.02, 2); hood.data.materials.append(blk)
    ink('ERASE        RECORD        PLAY', -1.5, ty + 4.9, 2.45, 0.32, w=15.0)
    mu = mu_metal()
    for hx in (-6.0, -1.5, 3.0):
        hd = rbox('head', 2.3, 2.4, 2.2, 0.85, 0.9, roll=0.2); hd.location = (hx, ty + 1.2, 0); hd.data.materials.append(mu)
        gap = rbox('gap', 0.05, 0.7, 0.02, 3.04, 0.0); gap.location = (hx, ty + 0.4, 0)
        gap.data.materials.append(mat('gapblk', srgb('#151210'), rough=0.5))
        sh = rbox('shield', 2.8, 0.35, 2.4, 0.85, 0.12, roll=0.05); sh.location = (hx, ty + 2.55, 0); sh.data.materials.append(ch)
        for sx in (-1, 1): screw_at(hx + sx * 1.6, ty + 3.2, 0.85, ni)
    for gx in (-10.5, 7.8):                          # guide posts with flanges at the tape's edges
        cyl('post', 0.55, 0.85, zt1 + 0.25, gx, ty + 0.55, 64, ch)
        for z in (zt0 - 0.06, zt1 + 0.06): cyl('pfl', 0.8, z - 0.05, z + 0.05, gx, ty + 0.55, 64, ch)
    cx_ = 5.6
    cyl('capstan', 0.22, 0.85, zt1 + 0.4, cx_, ty + 0.22, 48, mu)
    cyl('pinch', 1.05, 0.9, zt1 + 0.25, cx_, ty - 1.07, 128, black_rubber())
    cyl('pinchcap', 0.4, zt1 + 0.25, zt1 + 0.4, cx_, ty - 1.07, 64, ch)
    # the tension arms with their rollers, beside each reel
    for sx in (-1, 1):
        ax, ay = sx * 13.0, ty + 5.0                 # the roller; its arm pivots below it, on the head base
        a = rbox('tarm', 0.7, 3.0, 0.3, 0.55, 0.3, roll=0.1); a.location = (ax + sx * 0.5, ay - 1.3, 0); a.rotation_euler = (0, 0, sx * -0.35)
        a.data.materials.append(blk)
        cyl('troll', 0.7, 0.85, zt1 + 0.15, ax, ay, 64, ch)
    # the tape's path
    circles = [((-rx, ry), rs, -1), ((-13.0, ty + 5.0), 0.7, +1), ((-10.5, ty + 0.55), 0.55, +1),
               ((-6.0, ty + 0.9), 0.9, +1), ((-1.5, ty + 0.9), 0.9, +1), ((3.0, ty + 0.9), 0.9, +1),
               ((cx_, ty + 0.22), 0.22, +1), ((7.8, ty + 0.55), 0.55, +1), ((13.0, ty + 5.0), 0.7, +1), ((rx, ry), rt, -1)]
    ribbon('tape', tape_path(circles), zt0, zt1, tp)
    # the counter, between the reels
    cw, chh = 6.2, 2.0
    CY = 6.4
    bz = rbox('cbez', cw + 0.6, chh + 0.6, 0.3, 0.25, 0.3, roll=0.1); bz.location = (0, CY, 0)
    cut(bz, prism('chole', [(x, y + CY, z) for x, y, z in _rring(cw / 2, chh / 2, 0.15, 0.0, 0, n_arc=8)], -2, 2))
    chamfer(bz, 0.02, 2); bz.data.materials.append(blk)
    for i, d in enumerate('0045'):
        dx = -2.25 + i * 1.5
        wh = rbox('wheel', 1.25, 1.9, 0.3, -0.05, 0.05, roll=0.06); wh.location = (dx, CY, 0.0)
        wh.data.materials.append(mat('wheel', srgb('#141211'), rough=0.5, coat=0.2))
        ink(d, dx, CY, 0.26, 0.95, color='#ece6d6', kind='BarlowSemiCondensed-600-normal.ttf', track=0.0, w=1.2)
    D = '#221e19'
    ink('SECONDS LEFT', 0, CY - 1.65, 0.25, 0.34, color=D)
    ink('SUPPLY', -rx, -10.4, 0.25, 0.34, color=D); ink('TAKE-UP', rx, -10.4, 0.25, 0.34, color=D)
    ink('CAB IR RECORDER', 0, 10.0, 0.25, 0.5, track=0.3, color=D)
    ink('FULL TRACK  .  ONE CAPTURE, EVERY RATE', 0, 9.0, 0.25, 0.24, track=0.2, color=D, w=12.0)
    # the keys: the shelf's illuminated pushbuttons, only for real actions; a red jewel for record
    keys = [('CHECK LEVELS', -15.0, False, 6.2), ('CAPTURE', -6.6, True, 5.4), ('STOP', 1.6, False, 3.8)]
    ky = -10.4
    for txt, kx, lit, kw in keys:
        kh = 1.9
        bez = rbox('kbez', kw + 0.44, kh + 0.44, 0.25, 0.25, 0.25, roll=0.06); bez.location = (kx, ky, 0)
        cut(bez, prism('kh', [(x + kx, y + ky, z) for x, y, z in _rring((kw + 0.06) / 2, (kh + 0.06) / 2, 0.12, 0.0, 0, n_arc=8)], -2, 2))
        chamfer(bez, 0.02, 2); bez.data.materials.append(blk)
        cap = rbox('cap', kw, kh, 0.3, 0.4, 0.12, roll=0.07, seg=4); TK.flat_faces(cap)
        cap.data.materials.append(SG.cap_mat(txt, lit, 'cap' + txt[:4], kw, kh)); cap.location = (kx, ky, 0)
        if lit:
            L = bpy.data.lights.new('kg', 'POINT'); L.energy = 0.3; L.color = srgb('#ffa040'); L.shadow_soft_size = 0.6
            g = bpy.data.objects.new('kg', L); s.collection.objects.link(g); g.location = (kx, ky, 1.4)
    jw = SG.chrome('jch', seed=7)
    from gear_kit import tek_jewel
    j = -2.6 + 0.0
    bzl = lathe('jb', [(0.92, 0.0), (0.92, 0.2), (0.88, 0.26), (0.76, 0.28), (0.7, 0.36), (0.66, 0.42), (0.6, 0.43), (0.56, 0.38), (0.55, 0.2)], 160)
    bzl.location = (j, ky, 0.25); bzl.data.materials.append(jw)
    lens = mat('reclens', srgb('#5a0a06'), rough=0.3, coat=0.5, coat_rough=0.03, spec=0.4, emit=srgb('#ff3a22'), emit_strength=3.0)
    o = lathe('jl', [(0.56, 0.2), (0.56, 0.34), (0.45, 0.4), (0.25, 0.45), (0.0, 0.47)], 96); o.location = (j, ky, 0.25); o.data.materials.append(lens)
    ink('REC', j, ky + 1.3, 0.25, 0.26, color=D)
    # the meter bridge's place on the right (the app's own VU modules sit here; shown as a blank engraved label)
    name = 'tape-reel-%02d' % int(round(prog * 100))
    if os.environ.get('DETAIL'):
        from gear_kit import render_crop
        a = TK.proj(s, cam, (-15.5, ty + 9.5, 3.0)); b = TK.proj(s, cam, (15.5, ty - 3.0, 0.0))
        box = [int(a[0]) // 8 * 8, int(a[1]) // 8 * 8, -(-int(b[0]) // 8) * 8, -(-int(b[1]) // 8) * 8]
        render_crop(s, box, os.path.join(OUT, name + '-heads.png'))
    else:
        TK.shoot(s, cam, name, W_, H_)


# ---------------------------------------------------------------------------------------------------------------------
# the cassette deck (AMP NAM)

CASS = dict(w=54.0, h=18.0, d=3.0)


def label_tex(w, h, ppcm):
    """The cassette label: cream paper, a ruled title line, and the training signal's map: blocks for the 190 s
    (sweeps, then noise and clicks, then guitar, then the repeat)."""
    from PIL import ImageDraw
    W_, H_ = int(w * ppcm), int(h * ppcm)
    im = Image.new('RGB', (W_, H_), (232, 222, 196)); d = ImageDraw.Draw(im)
    f = SG.font('cap', int(0.42 * ppcm)); f2 = SG.font('BarlowSemiCondensed-600-normal.ttf', int(0.3 * ppcm))
    d.text((0.35 * ppcm, 0.12 * ppcm), 'A   TRAINING SIGNAL v3', font=f, fill=(40, 30, 24))
    d.text((W_ - 3.1 * ppcm, 0.2 * ppcm), '190 s . 48 kHz', font=f2, fill=(60, 48, 38))
    y0, y1 = int(0.72 * ppcm), int(1.48 * ppcm)
    x0, x1 = int(0.35 * ppcm), W_ - int(0.35 * ppcm)
    # the signal's own envelope (reference/nam_v3_map.json: peak and RMS per 0.25 s of T3K-sweep-v3.wav), drawn as a
    # waveform strip over its parts: the 9 s check section (repeated at the end), the clicks, the training section
    mp = json.load(open(os.path.join(HERE, '..', '..', 'reference', 'nam_v3_map.json')))
    pk = np.array(mp['peak_db']); rm = np.array(mp['rms_db']); n = len(pk); T = n * mp['block_s']
    ym = (y0 + y1) / 2
    for a, b, c in ((0, 9, (214, 150, 104)), (12, 181, (236, 226, 202)), (181, 190, (214, 150, 104))):
        d.rectangle([x0 + (x1 - x0) * a / T, y0, x0 + (x1 - x0) * b / T, y1], fill=c)
    for px in range(x0, x1):
        i0 = int((px - x0) / (x1 - x0) * n); i1 = max(i0 + 1, int((px + 1 - x0) / (x1 - x0) * n))
        for arr, col, k in ((pk, (120, 96, 76), 1.0), (rm, (52, 40, 32), 1.0)):
            e = arr[i0:i1].max(); h = max(0.0, (e + 48) / 48) * (y1 - y0) / 2 * k
            if h > 0.3: d.line([(px, ym - h), (px, ym + h)], fill=col)
    for t, a in (('CHECK', 0), ('TRAINING', 85), ('CHECK', 181)):
        xa = x0 + (x1 - x0) * a / T
        if a == 181: xa = x1 - f2.getlength(t)
        d.text((xa, y1 + 2), t, font=f2, fill=(60, 48, 38))
    return np.asarray(im, np.float32) / 255.0


def piece_cassette(prog):
    W_, H_, D = CASS['w'], CASS['h'], CASS['d']
    s, cam = TK.scene(W_, H_, 1.0)
    TK.catcher(-D)
    face = rbox('face', W_, H_, D, -D, 0.5, roll=0.3)
    dx, dy, dw, dh = -13.0, 0.8, 15.0, 10.4
    cut(face, prism('well', [(x + dx, y + dy + 0.6, z) for x, y, z in _rring(6.0, 3.6, 0.4, 0.0, 0, n_arc=8)], -2.4, 1))
    TK.flat_faces(face); face.data.materials.append(K.anodised('face'))
    back = rbox('wellback', 13.0, 8.0, 0.1, -2.5, 0.3); back.location = (dx, dy + 0.6, 0)
    back.data.materials.append(mat('wb', srgb('#121110'), rough=0.8))
    Lw = bpy.data.lights.new('well', 'AREA'); Lw.energy = 2.5; Lw.size = 9.0; Lw.color = srgb('#ffe2b0')
    gw = bpy.data.objects.new('well', Lw); s.collection.objects.link(gw); gw.location = (dx, dy + 3.6, -0.4); gw.rotation_euler = (math.radians(70), 0, 0)
    blk = SG.black_cast('bc'); ni = TK.nickel()
    for sx in (-1, 1):
        for sy in (-1, 1): screw(sx * (W_ / 2 - 1.0), sy * (H_ / 2 - 1.0), ni)
    # the cassette well: a recessed door with a smoked window; the cassette behind it
    door = rbox('door', dw, dh, 0.35, 0.0, 0.35, roll=0.1); door.location = (dx, dy, 0)
    cut(door, prism('dwin', [(x + dx, y + dy + 0.6, z) for x, y, z in _rring(5.6, 3.1, 0.4, 0.0, 0, n_arc=8)], -2, 2))
    chamfer(door, 0.02, 2); door.data.materials.append(blk)
    win = rbox('dglass', 11.4, 6.4, 0.06, 0.12, 0.4); win.location = (dx, dy + 0.6, 0)
    win.data.materials.append(mat('dglass', srgb('#b8aa96'), rough=0.04, transm=1.0, ior=1.05, spec=0.4))
    # the cassette (10 x 6.3 cm), seen through the glass: shell, label, window, hubs, tape
    cz = -0.9
    shell = rbox('shell', 10.0, 6.3, 0.7, cz - 0.7, 0.3, roll=0.05); shell.location = (dx, dy + 0.6, 0)
    shell.data.materials.append(mat('shell', srgb('#1c1b1a'), rough=0.35, coat=0.3))
    lab = rbox('label', 9.2, 2.1, 0.01, cz, 0.12); lab.location = (dx, dy + 2.4, 0)
    lm = mat('label', srgb('#e8dec4'), rough=0.7); nt = lm.node_tree
    tex = SG.img_tex(nt, 'labtex', label_tex(9.2, 2.1, 100), True, 'CLIP')
    tc = nt.nodes.new('ShaderNodeTexCoord'); sep = node(nt, 'ShaderNodeSeparateXYZ'); nt.links.new(tc.outputs['Object'], sep.inputs[0])
    u = node(nt, 'ShaderNodeMapRange', **{'From Min': -4.6, 'From Max': 4.6}); nt.links.new(sep.outputs['X'], u.inputs['Value'])
    v = node(nt, 'ShaderNodeMapRange', **{'From Min': -1.05, 'From Max': 1.05}); nt.links.new(sep.outputs['Y'], v.inputs['Value'])
    cv = node(nt, 'ShaderNodeCombineXYZ'); nt.links.new(u.outputs['Result'], cv.inputs['X']); nt.links.new(v.outputs['Result'], cv.inputs['Y'])
    nt.links.new(cv.outputs['Vector'], tex.inputs['Vector']); nt.links.new(tex.outputs['Color'], nt.nodes['Principled BSDF'].inputs['Base Color'])
    lab.data.materials.append(lm)
    # the playhead on the label's map (where the take is)
    ph = rbox('phead', 0.07, 0.8, 0.01, cz + 0.012, 0.0); ph.location = (dx - 4.25 + 8.5 * prog, dy + 2.4 - 0.08, 0)
    ph.data.materials.append(mat('phm', srgb('#d01a10'), rough=0.5))
    cwin = rbox('cwin', 7.2, 2.4, 0.01, cz + 0.035, 0.35); cwin.location = (dx, dy + 0.15, 0)
    cwin.data.materials.append(mat('cwin', srgb('#d8d0c4'), rough=0.05, transm=0.9, ior=1.05, spec=0.6))
    for hx, rr in ((-2.4, 0.8 + 0.9 * (1 - prog)), (2.4, 0.8 + 0.9 * prog)):
        cyl('hubpack', min(rr, 1.7), cz, cz + 0.015, dx + hx, dy + 0.15, 96, oxide('cox'))
        h = cyl('hub', 0.6, cz, cz + 0.03, dx + hx, dy + 0.15, 6, mat('hubw', srgb('#e6e1d6'), rough=0.4))
    ink('PLAY / RECORD', dx, dy - 4.3, 0.35, 0.3)
    # keys: soft-touch rectangles in a row, the active one with its LED
    ky = -6.6
    for i, (t, on) in enumerate((('CHECK', False), ('RECORD', True), ('STOP', False))):
        kx = -0.2 + i * 5.2
        k = rbox('skey', 4.4, 1.6, 0.45, 0.0, 0.25, roll=0.2); k.location = (kx, ky, 0)
        k.data.materials.append(mat('skey', srgb('#9a9890'), rough=0.3, metal=0.9))
        ink(t, kx, ky, 0.45, 0.3, color='#1a1918')
        lc = '#ff3020' if on else '#2a0806'
        led = cyl('led', 0.18, 0.0, 0.18, kx, ky + 1.3, 32, mat('led' + t, srgb(lc), rough=0.2, emit=srgb(lc) if on else None, emit_strength=6.0 if on else 0.0))
    # a three-digit counter
    bz = rbox('cbz', 4.4, 1.7, 0.2, 0.0, 0.2, roll=0.06); bz.location = (5.0, 4.5, 0); bz.data.materials.append(blk)
    for i, dgt in enumerate('045'):
        ink(dgt, 3.9 + i * 1.1, 4.5, 0.21, 0.85, color='#ece6d6', kind='BarlowSemiCondensed-600-normal.ttf', track=0.0, w=1.0)
    ink('COUNTER', 5.0, 3.1, 0.0, 0.26)
    ink('AMP CAPTURE DECK', 17.0, 5.2, 0.0, 0.5, track=0.3)
    ink('NAM  .  TRAINING SIGNAL v3', 17.0, 4.0, 0.0, 0.26)
    cyl('sled', 0.2, 0.0, 0.2, 13.2, -3.0, 32, mat('sled', srgb('#ffb030'), rough=0.2, emit=srgb('#ffa020'), emit_strength=5.0))
    ink('SIGNAL LOADED', 15.6, -3.0, 0.0, 0.26)
    name = 'tape-cassette-%02d' % int(round(prog * 100))
    TK.shoot(s, cam, name, W_, H_)


# ---------------------------------------------------------------------------------------------------------------------
# the broadcast cart machine (AMP NAM; Lowell, 11-03: "broadcast cart would be better")
#
# A late-1970s/80s rack cart machine, 3U: graphite anodised face with rack ears, a C-size cartridge in the slot with
# its end label facing out, square lens pushbuttons (CHECK amber, RECORD red, STOP white), READY and two CUE lamps,
# a four-digit LED timer behind a red filter. Every part is a function of the app:
#   the cart's end label   the training signal's map, with a playhead the app moves
#   READY                  T3K-sweep-v3.wav found and checked (was SIGNAL LOADED)
#   CUE 1, CUE 2           the two one-sample clicks at 10.5 s and 11.5 s, found in the recording (the alignment)
#   the timer              time left in the 190 s take
#   CHECK / RECORD / STOP  the level check, the take, stop

CART = dict(w=48.3, h=13.3, d=3.0, ear=1.9)


def cart_label_tex(w, h, ppcm, prog=None):
    """The cart's end label: cream stock, a title line, and the training signal's map (the real envelope of
    T3K-sweep-v3.wav, reference/nam_v3_map.json), the CHECK sections and the two cue clicks marked."""
    from PIL import ImageDraw
    W_, H_ = int(w * ppcm), int(h * ppcm)
    im = Image.new('RGB', (W_, H_), (233, 224, 199)); d = ImageDraw.Draw(im)
    f = SG.font('cap', int(0.30 * ppcm)); f2 = SG.font('BarlowSemiCondensed-600-normal.ttf', int(0.24 * ppcm))
    ink_c = (44, 34, 26)
    d.text((0.25 * ppcm, 0.08 * ppcm), 'TRAINING SIGNAL v3', font=f, fill=ink_c)
    t2 = '190 s  .  48 kHz  .  MONO'; d.text((W_ - 0.25 * ppcm - f2.getlength(t2), 0.12 * ppcm), t2, font=f2, fill=(70, 56, 44))
    d.line([(0.25 * ppcm, 0.5 * ppcm), (W_ - 0.25 * ppcm, 0.5 * ppcm)], fill=(170, 60, 50), width=max(1, int(0.03 * ppcm)))
    y0, y1 = int(0.62 * ppcm), int(1.42 * ppcm)
    x0, x1 = int(0.25 * ppcm), W_ - int(0.25 * ppcm)
    mp = json.load(open(os.path.join(HERE, '..', '..', 'reference', 'nam_v3_map.json')))
    pk = np.array(mp['peak_db']); rm = np.array(mp['rms_db']); n = len(pk); T = n * mp['block_s']
    ym = (y0 + y1) / 2
    X = lambda t: x0 + (x1 - x0) * t / T
    for a, b in ((0, 9), (181, 190)): d.rectangle([X(a), y0, X(b), y1], fill=(216, 160, 112))
    for px in range(x0, x1):
        i0 = int((px - x0) / (x1 - x0) * n); i1 = max(i0 + 1, int((px + 1 - x0) / (x1 - x0) * n))
        for arr, col in ((pk, (126, 102, 80)), (rm, (52, 40, 32))):
            e = arr[i0:i1].max(); hh = max(0.0, (e + 48) / 48) * (y1 - y0) / 2
            if hh > 0.3: d.line([(px, ym - hh), (px, ym + hh)], fill=col)
    for tc in (10.5, 11.5):                                   # the cue clicks
        d.line([(X(tc), y0 - 0.06 * ppcm), (X(tc), y1 + 0.06 * ppcm)], fill=(170, 60, 50), width=max(1, int(0.025 * ppcm)))
    yl = y1 + 0.04 * ppcm
    d.text((X(0), yl), 'CHECK', font=f2, fill=(70, 56, 44))
    d.text((X(12.5), yl), 'CUE 1, 2', font=f2, fill=(150, 56, 46))
    d.text(((x0 + x1) / 2 - f2.getlength('TRAINING') / 2, yl), 'TRAINING', font=f2, fill=(70, 56, 44))
    d.text((x1 - f2.getlength('CHECK'), yl), 'CHECK', font=f2, fill=(70, 56, 44))
    return np.asarray(im, np.float32) / 255.0


def img_plane(name, arr, w, h, x, y, z, rough=0.7):
    bpy.ops.mesh.primitive_plane_add(size=1, location=(x, y, z)); o = bpy.context.active_object; o.name = name
    o.scale = (w, h, 1)
    m = mat(name, srgb('#e8dec4'), rough=rough); nt = m.node_tree
    t = SG.img_tex(nt, name + 'tx', arr, True, 'CLIP')
    uv = nt.nodes.new('ShaderNodeTexCoord'); nt.links.new(uv.outputs['UV'], t.inputs['Vector'])
    nt.links.new(t.outputs['Color'], nt.nodes['Principled BSDF'].inputs['Base Color'])
    co = obj_coords(nt); add_bump(m, noise(nt, co, 40.0, 3.0, 0.6), 0.08, 0.002)
    o.data.materials.append(m)
    return o


def lens_mat(name, base, glow, lit):
    """A square pushbutton's lens: tinted translucent resin, frosted; lit, the lamp behind it glows evenly."""
    m = mat(name, srgb(base), rough=0.35, coat=0.4, coat_rough=0.12, spec=0.4,
            emit=srgb(glow) if lit else None, emit_strength=0.8 if lit else 0.0)
    nt = m.node_tree; co = obj_coords(nt)
    add_bump(m, noise(nt, co, 160.0, 2.0, 0.5), 0.12, 0.0012)
    surface_wear(m, smudge=0.5, scuff=0.2)
    return m


def led_mat(name, col, on, k=5.0):
    return mat(name, srgb(col if on else '#2a0e08'), rough=0.25, coat=0.5, coat_rough=0.05,
               emit=srgb(col) if on else None, emit_strength=k if on else 0.0)


SEG = {'0': 'abcdef', '1': 'bc', '2': 'abdeg', '3': 'abcdg', '4': 'bcfg', '5': 'acdfg', '6': 'acdefg', '7': 'abc',
       '8': 'abcdefg', '9': 'abcdfg'}


def seven_seg(ch, x, y, z, hgt, on_m, off_m):
    """One seven-segment digit hgt cm tall, slanted 8 degrees, every segment present (unlit ones dark red)."""
    w = hgt * 0.52; t = hgt * 0.11; sl = math.tan(math.radians(8))
    segs = {'a': (0, hgt / 2, True), 'g': (0, 0, True), 'd': (0, -hgt / 2, True),
            'f': (-w / 2, hgt / 4, False), 'b': (w / 2, hgt / 4, False), 'e': (-w / 2, -hgt / 4, False), 'c': (w / 2, -hgt / 4, False)}
    for k, (sx, sy, horiz) in segs.items():
        sw, sh = (w - t, t) if horiz else (t, hgt / 2 - t)
        o = rbox('seg', sw, sh, 0.02, z, t * 0.45, roll=0.0)
        o.location = (x + sx + sy * sl, y + sy, 0); o.rotation_euler = (0, 0, 0 if horiz else math.radians(-8) * 0)
        o.data.materials.append(on_m if k in SEG.get(ch, '') else off_m)


def piece_cart(prog):
    W_, H_, D, E = CART['w'], CART['h'], CART['d'], CART['ear']
    s, cam = TK.scene(W_, H_, 1.0)
    TK.catcher(-D)
    blk = SG.black_cast('bc'); ni = TK.nickel()
    # the face, the slot cut through it
    sx0, sy0, sw, sh = -10.4, 1.9, 16.2, 3.1
    face = rbox('face', W_, H_, 0.5, -0.5, 0.25, roll=0.2)
    cut(face, prism('slot', [(x + sx0, y + sy0, z) for x, y, z in _rring(sw / 2, sh / 2, 0.25, 0.0, 0, n_arc=8)], -2, 2))
    for ex in (-1, 1):                                        # rack ears: two slotted holes each
        for ey in (-1, 1):
            cut(face, prism('rk', [(x + ex * (W_ / 2 - E / 2), y + ey * 4.75, z) for x, y, z in _rring(0.55, 0.33, 0.32, 0.0, 0, n_arc=8)], -2, 2))
    TK.flat_faces(face); face.data.materials.append(K.anodised('face'))
    body = rbox('body', W_ - 2 * E - 0.4, H_ - 0.6, D - 0.5, -D, 0.3); body.data.materials.append(mat('body', srgb('#141414'), rough=0.6))
    for ex in (-1, 1):
        for ey in (-1, 1): screw_at(ex * (W_ / 2 - E / 2), ey * 4.75, 0.0, ni)
    # the ears' seams: a fine engraved line where the ear meets the panel's working face
    for ex in (-1, 1):
        g = rbox('seam', 0.035, H_ - 0.9, 0.02, -0.005, 0.0); g.location = (ex * (W_ / 2 - E), 0, 0)
        g.data.materials.append(mat('seam', srgb('#0e0e0f'), rough=0.6))
    # the slot's throat: dark, lit faintly from inside; the cart in it, its end standing 1.4 cm proud
    throat = rbox('throat', sw - 0.1, sh - 0.1, 0.1, -2.6, 0.2); throat.location = (sx0, sy0, 0)
    throat.data.materials.append(mat('throat', srgb('#0d0c0b'), rough=0.85))
    Lt = bpy.data.lights.new('throat', 'AREA'); Lt.energy = 0.6; Lt.size = 12.0; Lt.color = srgb('#ffdcb0')
    gt = bpy.data.objects.new('throat', Lt); s.collection.objects.link(gt); gt.location = (sx0, sy0 + 1.0, -1.2); gt.rotation_euler = (math.radians(80), 0, 0)
    cw_, ch_ = 15.2, 2.45
    shell = rbox('cart', cw_, ch_, 4.0, -2.6, 0.18, roll=0.04); shell.location = (sx0, sy0 - 0.15, 0)
    shm = mat('cartshell', srgb('#2b2927'), rough=0.42, coat=0.25, coat_rough=0.25)
    add_bump(shm, noise(shm.node_tree, obj_coords(shm.node_tree), 90.0, 2.0, 0.5), 0.08, 0.001); surface_wear(shm, dust=0.4, smudge=0.5, scuff=0.5)
    shell.data.materials.append(grimy(shm, dirt='#3a3228', amount=0.35, dist=0.05))
    # two finger grips moulded into the end, either side of the label
    for gx in (-1, 1):
        for i in range(4):
            gr = rbox('grip', 0.06, ch_ - 0.7, 0.05, 1.4, 0.02); gr.location = (sx0 + gx * (cw_ / 2 - 0.45 - i * 0.16), sy0 - 0.15, 0)
            gr.data.materials.append(shm)
    lw, lh = 12.6, 1.9
    img_plane('cartlabel', cart_label_tex(lw, lh, 110), lw, lh, sx0, sy0 - 0.15, 1.402)
    # the playhead on the label's map (the app moves it)
    ph = rbox('phead', 0.06, 0.95, 0.01, 1.404, 0.0)
    ph.location = (sx0 - lw / 2 + 0.25 + (lw - 0.5) * prog, sy0 - 0.15 - lh / 2 + 1.02 / 1.9 * lh, 0)
    ph.data.materials.append(mat('phm', srgb('#d01a10'), rough=0.5, emit=srgb('#ff2010'), emit_strength=0.6))
    D_ = '#cfc9bd'
    ink('PLAY / RECORD', sx0 - sw / 2 + 1.6, sy0 + sh / 2 + 0.55, 0.0, 0.26, color=D_)
    # the keys: square lens pushbuttons in chrome-edged bezels, under the slot
    ky = -3.3; ks = 2.5
    for txt, kx, base, glow, lit in (('CHECK', -16.0, '#c88a30', '#ffa030', False), ('RECORD', -10.4, '#5e0a05', '#ff1a08', True),
                                     ('STOP', -4.8, '#cfc8b8', '#fff0d0', False)):
        bz = rbox('kbz', ks + 0.5, ks + 0.5, 0.22, 0.0, 0.2, roll=0.06); bz.location = (kx, ky, 0)
        cut(bz, prism('kh', [(x + kx, y + ky, z) for x, y, z in _rring(ks / 2 + 0.03, ks / 2 + 0.03, 0.15, 0.0, 0, n_arc=8)], -2, 2))
        chamfer(bz, 0.02, 2); bz.data.materials.append(SG.chrome('kch', seed=5))
        cap = rbox('lens', ks, ks, 0.55, -0.1, 0.12, roll=0.08); TK.flat_faces(cap); cap.location = (kx, ky, 0)
        cap.data.materials.append(lens_mat('lens' + txt, base, glow, lit))
        if lit:
            L = bpy.data.lights.new('kg', 'POINT'); L.energy = 0.35; L.color = srgb(glow); L.shadow_soft_size = 0.8
            g = bpy.data.objects.new('kg', L); s.collection.objects.link(g); g.location = (kx, ky, 1.3)
        ink(txt, kx, ky - ks / 2 - 0.62, 0.0, 0.3, color=D_)
    # the lamps: READY and the two cues, flush LEDs in a row right of the slot
    for i, (txt, col, on) in enumerate((('READY', '#40e070', True), ('CUE 1', '#ffb030', True), ('CUE 2', '#ffb030', True))):
        lx, ly = 1.2 + i * 2.5, 2.4
        cyl('ledbz', 0.36, 0.0, 0.12, lx, ly, 48, blk)
        cyl('led', 0.24, 0.0, 0.2, lx, ly, 48, led_mat('led' + txt, col, on))
        ink(txt, lx, ly - 0.85, 0.0, 0.24, color=D_)
    # the timer: four digits (M:SS) behind a red filter, time left in the take
    left = int(round(190 * (1 - prog))); digits = '%d%02d' % (left // 60, left % 60)
    tx, tyy, tw, th = 3.7, -2.6, 7.4, 2.6
    win = rbox('twin', tw, th, 0.3, 0.0, 0.1, roll=0.04); win.location = (tx, tyy, 0)
    cut(win, prism('twh', [(x + tx, y + tyy, z) for x, y, z in _rring(tw / 2 - 0.3, th / 2 - 0.3, 0.1, 0.0, 0, n_arc=8)], -2, 2))
    win.data.materials.append(blk)
    back = rbox('tback', tw - 0.6, th - 0.6, 0.05, 0.0, 0.0); back.location = (tx, tyy, 0)
    back.data.materials.append(mat('tback', srgb('#120605'), rough=0.6))
    on_m, off_m = led_mat('segon', '#ff3a18', True, 14.0), led_mat('segoff', '#ff3a18', False)
    hgt = 1.45
    xs = (tx - 2.0, tx - 0.15, tx + 1.15, tx + 2.45)          # M : S S (one digit, colon, two)
    seven_seg(digits[0], xs[0], tyy, 0.05, hgt, on_m, off_m)
    for k, c in enumerate(digits[1:]): seven_seg(c, xs[2 + k] - 0.4, tyy, 0.05, hgt, on_m, off_m)
    for dy in (0.32, -0.32): cyl('colon', 0.08, 0.05, 0.07, xs[1] - 0.25, tyy + dy, 16, on_m)
    filt = rbox('tfilt', tw - 0.5, th - 0.5, 0.04, 0.16, 0.0); filt.location = (tx, tyy, 0)
    filt.data.materials.append(mat('tfilt', srgb('#e0a090'), rough=0.04, transm=1.0, ior=1.1, spec=0.35))
    ink('TIME LEFT', tx, tyy - th / 2 - 0.5, 0.0, 0.24, color=D_)
    # the title, engraved and filled
    ink('AMP CAPTURE CART', 15.6, 0.9, 0.0, 0.48, track=0.3, color=D_)
    ink('NAM  .  TRAINING SIGNAL v3', 15.6, -0.2, 0.0, 0.24, track=0.2, color='#a8a298')
    name = 'tape-cart-%02d' % int(round(prog * 100))
    TK.shoot(s, cam, name, W_, H_)


if __name__ == '__main__':
    t = time.time()
    {'reel': piece_reel, 'cassette': piece_cassette, 'cart': piece_cart}[WHAT](PROG)
    print('done %.1fs' % (time.time() - t))
    json.dump(TK.LAY, open(os.path.join(OUT, 'tape-%s.json' % WHAT), 'w'), indent=1)
