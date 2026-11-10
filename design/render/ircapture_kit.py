# ircapture_kit.py: IR Capture's own rendered pieces, in the desktop bench's Tools studio (helper for IR Capture,
# 2026-11-03).
#
# On the iMac these sit beside the bench's scripts (desktop-bench/design/render/), which they import; here (the container)
# they live in ir-capture/design/render/ and reach the bench's folder through sys.path below. Nothing in the bench's
# scripts is changed: its materials and studio are imported and used as they are, and the new materials are written here.
#
# Lowell, 11-03, on IR Capture dressed in the bench's look: "the hammertone is too busy--it could be a different surface
# or finer grain"; "the camera angles are not uniform--looking down and up at the same time" (the shelf pieces came from
# the frame camera, below the shelf; the keys and panels from 10 degrees above); "the colors are a little too uniform, too
# perfect"; for the NAM side "maybe the rack gear over there is just a little more modern looking". So, all in
# toolkit.scene()'s studio (gear_kit.stage(): orthographic, 10 degrees above, key light up and to the left):
#
#   panel-fine   toolkit.piece_panel() again in a finer, calmer bronze hammertone: cells 2.5 x smaller, half the relief,
#                the flake and the per-cell colour mottle subdued, a broad gentle tone drift kept (not too perfect)
#   panel-nam    the same panel for the NAM job, 1970s-80s rack stock: dark graphite anodised aluminium, a fine horizontal
#                brushed grain, satin, the edges worn to bright aluminium, faint handling marks, button-head hex screws
#   plank        the shelf: fumed quartersawn oak (shelf_wood.py's field, made periodic along x), 2.6 cm front edge,
#                12 cm deep, its top seen from 10 degrees above, rolled edges, dings; its shadow on the wall (z = 0)
#   box-bronze   a homemade steel instrument case standing on the plank (fine hammertone), 36 cm wide, 7 cm front face,
#   box-oxblood  10 cm deep, corners 0.45 cm, rolled edges, two rubber feet; over shadow catchers at the plank and wall
#   trim-h       a stained oak moulding round the opening under the shelf (1.6 cm face, ogee both sides), horizontal and
#   trim-v       vertical runs, periodic along their length
#
#   ~/bvenv/bin/python design/render/ircapture_kit.py <out dir> <piece[,piece]|all> [px/cm] [samples]
#   python3 design/render/ircapture_kit_post.py <out dir> Resources/SwellKit
# Units: 1 = 1 cm; the wall is the XY plane at z = 0 facing +z (the camera), y up.
import sys, os, math, json, time
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, '/home/claude/desktop-bench/design/render')   # the bench's scripts (on the iMac: this folder itself)
sys.path.insert(0, HERE)

_argv = sys.argv[:]
OUT = _argv[1] if len(_argv) > 1 else '/tmp/ircapture_kit'
WHAT = _argv[2] if len(_argv) > 2 else 'all'
PXCM = float(_argv[3]) if len(_argv) > 3 else 48.0
SAMPLES = int(_argv[4]) if len(_argv) > 4 else 192
os.makedirs(OUT, exist_ok=True)
sys.argv = [_argv[0], OUT, OUT]          # parts.py and toolkit.py read sys.argv when imported
import bpy
import numpy as np
import parts as P
from parts import mat, srgb, lathe, _rring
from gear_kit import rbox, cut, chamfer, surface_wear, screw, node, obj_coords, add_bump, mix_into, edge_mask, noise, mul, scratches
from instrument import grimy, prism
import toolkit as TK
import shelf_gear as SG
import shelf_wood as SW
sys.argv = _argv
TK.OUT, TK.PXCM, TK.SAMPLES = OUT, PXCM, SAMPLES

# ---------------------------------------------------------------------------------------------------------------------
# (11-10) the bench's look since 11-03 (handoff HANDOFF-desktop-to-ircapture-2026-11-09.md), for every piece made here
# and in the tape scripts (they import this module):
#   - the pixel filter 1.0 px, as the rig's (gear_kit.stage leaves Blender's 1.5 px, which softened every sprite);
#     IRC_FILTER sets another
#   - the workshop room in the world, seen by glossy rays only (metal_kit.room_world): polished and brushed parts mirror
#     a dim room instead of black; diffuse light unchanged. IRC_ROOM=0 leaves it out
#   - the liquid hammertone (hammer_liquid.liquid_paint) wherever a hammertone was (IRC_HAMMER=cells: the 11-04 cells)
#   - the NAM panels' anodising from finish_maps' true-scale maps (IRC_ANOD=old: the 11-03 shader)
#   - the shelf and its mouldings as rough shop wood (shop_wood.py: real meshes, the relief in true cm), long strips that
#     never repeat, lit alike along their length (IRC_WOOD=oak: the 11-04 lacquered oak)
import metal_kit as MK
FILTER = float(os.environ.get('IRC_FILTER', '1.0'))
ROOM = os.environ.get('IRC_ROOM', '1') != '0'
HAMMER = os.environ.get('IRC_HAMMER', 'liquid')
ANOD = os.environ.get('IRC_ANOD', 'old')         # (11-10 proof: the maps' worn rim and scratches read loud on a 16 cm panel)
WOOD = os.environ.get('IRC_WOOD', 'shop')
_scene0 = TK.scene


def scene_now(*a, **k):
    """toolkit.scene() and then the 11-10 studio: the 1.0 px filter and the room in the reflections."""
    s, cam = _scene0(*a, **k)
    if abs(ELEV - TK.ELEV) > 1e-6:                     # the shelf from below: the same studio, the camera turned
        e = math.radians(ELEV)
        cam.location = (0, 200 * math.sin(e), 200 * math.cos(e)); cam.rotation_euler = (-e, 0, 0)
        # (11-10 proof) seen from below, a face toward the camera mirrors what is a little above in front: the studio's
        # top softbox, which washed the bronze box's face out to a flat grey. It still lights; it is only not seen in
        # reflections (the room in the world is: metal_kit.room_world).
        for o in s.objects:
            if o.name.split('.')[0] in ('top', 'topL'):
                try: o.visible_glossy = False
                except Exception: pass
    try: s.cycles.filter_width = FILTER
    except Exception: pass
    if ROOM: MK.room_world(s)
    return s, cam


TK.scene = scene_now

# ---------------------------------------------------------------------------------------------------------------------
# shop wear (11-04), after the bench's shelf_wear.py (desktop-bench look, 128th chat; Lowell on the bench, 11-03: "each
# device and switch looks practically identical. everything up there is too perfect and uniform ... a little shop wear
# and texture so it looks real. some slight staining and discoloration of some switches")
#
# A seed per piece: every material samples its noise in object coordinates (gear_kit.obj_coords), so offsetting those
# coordinates per piece gives each piece its own stipple, rub, smudges and chips with the same materials. The bench's
# scripts are not changed: their modules' obj_coords is swapped here, at run time, for a seeded one. With the seed at
# zero it is exactly gear_kit's.
import hashlib
from PIL import Image, ImageFilter
import gear_kit as GK
SEED = [0.0, 0.0, 0.0]
_obj_coords0 = GK.obj_coords


def seeded_coords(nt, scale=1.0):
    if not any(SEED): return _obj_coords0(nt, scale)
    tc = nt.nodes.new('ShaderNodeTexCoord')
    mp = node(nt, 'ShaderNodeMapping'); mp.inputs['Scale'].default_value = (scale, scale, scale)
    mp.inputs['Location'].default_value = tuple(SEED)
    nt.links.new(tc.outputs['Object'], mp.inputs[0]); return mp.outputs[0]


for _m in list(sys.modules.values()):
    try:
        if getattr(_m, 'obj_coords', None) is _obj_coords0: _m.obj_coords = seeded_coords
    except Exception: pass
obj_coords = seeded_coords


def seed_of(name): return int(hashlib.md5(name.encode()).hexdigest()[:8], 16)


def set_seed(name):
    """Every material made after this samples its noise at this piece's own offset; returns the piece's rng."""
    r = np.random.default_rng(seed_of('irc-' + name))
    SEED[:] = [float(v) for v in r.uniform(-60, 60, 3)]
    return r


def ss(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1); return t * t * (3 - 2 * t)


def _box(a, r, axis):
    if r < 1: return a
    pad = [(0, 0)] * a.ndim; pad[axis] = (r + 1, r)
    c = np.cumsum(np.pad(a, pad, mode='wrap' if axis == 1 else 'edge'), axis)
    n = a.shape[axis]
    return (np.take(c, np.arange(2 * r + 1, n + 2 * r + 1), axis) - np.take(c, np.arange(0, n), axis)) / (2 * r + 1)


def blur(a, px):
    """About a Gaussian of sigma px (three box passes each way); columns wrap (the maps are periodic along x)."""
    a = np.asarray(a, np.float32); r = max(0, int(round(px * 0.93)))
    for _ in range(3): a = _box(_box(a, r, 0), r, 1)
    return a


def _max(nt, a, b):
    n = node(nt, 'ShaderNodeMath', operation='MAXIMUM'); nt.links.new(a, n.inputs[0]); nt.links.new(b, n.inputs[1]); return n.outputs[0]


def screw_ring(m, pts):
    """shelf_wear.py's: the paint scuffed round each screw (object coordinates), ragged, to primer then steel, with
    screwdriver slips."""
    nt = m.node_tree; tc = nt.nodes.new('ShaderNodeTexCoord'); co = obj_coords(nt)
    acc = None
    for i, p in enumerate(pts):
        d = node(nt, 'ShaderNodeVectorMath', operation='DISTANCE'); nt.links.new(tc.outputs['Object'], d.inputs[0])
        d.inputs[1].default_value = p
        mr = node(nt, 'ShaderNodeMapRange', **{'From Min': 0.62 + 0.08 * (i % 3), 'From Max': 0.3}); mr.clamp = True
        mr.interpolation_type = 'SMOOTHSTEP'; nt.links.new(d.outputs['Value'], mr.inputs['Value'])
        acc = mr.outputs['Result'] if acc is None else _max(nt, acc, mr.outputs['Result'])
    rag = noise(nt, co, 14.0, 6.0, 0.7, lo=0.42, hi=0.62)
    slip = GK.scratches(nt, co, 22.0, along='X', density=0.8, length=6.0)
    wear = mul(nt, acc, _max(nt, rag, slip))
    steel = node(nt, 'ShaderNodeMath', operation='GREATER_THAN'); steel.inputs[1].default_value = 0.6; nt.links.new(wear, steel.inputs[0])
    mix_into(m, 'Base Color', wear, (*srgb('#6e695f'), 1)); mix_into(m, 'Base Color', steel.outputs[0], (*srgb('#a29d93'), 1))
    mix_into(m, 'Metallic', steel.outputs[0], 1.0, 'FLOAT'); mix_into(m, 'Roughness', wear, 0.38, 'FLOAT')
    add_bump(m, wear, -0.3, 0.004)
    return m


def corner_wear(m, half_w, zone=2.2, amount=0.9):
    """shelf_wear.py's: more chips toward the ends (where a case is picked up and knocked). zone: how far in from each
    end (cm); kept inside the box pictures' end caps (2.9 cm into the face), so nothing in the repeating middle."""
    nt = m.node_tree; tc = nt.nodes.new('ShaderNodeTexCoord'); co = obj_coords(nt)
    sep = node(nt, 'ShaderNodeSeparateXYZ'); nt.links.new(tc.outputs['Object'], sep.inputs[0])
    ab = node(nt, 'ShaderNodeMath', operation='ABSOLUTE'); nt.links.new(sep.outputs['X'], ab.inputs[0])
    end = node(nt, 'ShaderNodeMapRange', **{'From Min': half_w - zone, 'From Max': half_w}); end.clamp = True
    nt.links.new(ab.outputs[0], end.inputs['Value'])
    em = edge_mask(nt, 0.35, 5.0); chip = noise(nt, co, 3.4, 8.0, 0.78, lo=0.42, hi=0.52)
    w = mul(nt, mul(nt, em, chip), mul(nt, end.outputs['Result'], amount))
    steel = node(nt, 'ShaderNodeMath', operation='GREATER_THAN'); steel.inputs[1].default_value = 0.35; nt.links.new(w, steel.inputs[0])
    mix_into(m, 'Base Color', w, (*srgb('#5d584f'), 1)); mix_into(m, 'Base Color', steel.outputs[0], (*srgb('#9d988e'), 1))
    mix_into(m, 'Metallic', steel.outputs[0], 1.0, 'FLOAT'); add_bump(m, w, -0.25, 0.006)
    return m


def map_wear(mp, rows_per_cm, K, rng, dents=0, scratch=0, water=None, ding_scale=1.0):
    """Wear in a periodic wood map (color, rough, height; columns wrap): larger dents (3 to 7 mm, crushed darker, the
    lacquer cracked round), fine scratches through the lacquer at small angles, and a faint water mark (u, v, r in
    fractions of the map). Columns wrap, so the strip stays seamless."""
    col, rough, hgt = mp['color'], mp['rough'], mp['height']
    H, Wd = rough.shape
    for _ in range(dents):
        cx = rng.uniform(0, Wd); cy = rng.uniform(0.15, 0.85) * H
        r = rng.uniform(0.15, 0.35) * K * ding_scale; ry = max(1.0, r * rows_per_cm / K) * rng.uniform(0.7, 1.3)
        xs = np.arange(int(cx - 3 * r), int(cx + 3 * r) + 1); ys = np.arange(max(0, int(cy - 3 * ry)), min(H, int(cy + 3 * ry) + 1))
        gy, gx = np.meshgrid(ys, xs, indexing='ij'); xi = np.mod(gx, Wd)
        dd = np.sqrt(((gx - cx) / r) ** 2 + ((gy - cy) / ry) ** 2)
        dn = np.exp(-dd ** 2 * 1.6); crack = np.exp(-((dd - 1.05) / 0.12) ** 2) * 0.5
        hgt[gy, xi] -= 1.6 * dn; col[gy, xi] *= (1 - (0.3 * dn + 0.12 * crack))[..., None]; rough[gy, xi] += 0.2 * dn + 0.15 * crack
    for _ in range(scratch):
        x0 = rng.uniform(0, Wd); y0 = rng.uniform(0.05, 0.95) * H; L = rng.uniform(0.8, 4.0) * K
        ang = rng.normal(0, 0.12); n = int(L)
        t = np.arange(n); xs = np.mod((x0 + t * np.cos(ang)).astype(int), Wd)
        ys = np.clip((y0 + t * np.sin(ang) * rows_per_cm / K).astype(int), 0, H - 1)
        fade = np.sin(np.pi * (t + 0.5) / n) * rng.uniform(0.4, 1.0)
        col[ys, xs] *= (1 + 0.1 * fade)[..., None]; rough[ys, xs] += 0.25 * fade; hgt[ys, xs] -= 0.3 * fade
    if water:
        u, v, rr = water
        yy, xx = np.mgrid[0:H, 0:Wd]
        dx = np.minimum(np.abs(xx - u * Wd), Wd - np.abs(xx - u * Wd)) / (rr * Wd)
        dy = (yy - v * H) / (rr * Wd * rows_per_cm / K * 0.6)
        n = blur(rng.random((H, Wd)), 2.0 * K / 24); n = (n - n.mean()) / (n.std() + 1e-6)
        d = np.sqrt(dx * dx + dy * dy) + 0.08 * n
        tide = np.exp(-((d - 1.0) / 0.06) ** 2) * 0.35 + ss(1.0, 0.7, d) * 0.12
        col *= (1 + 0.18 * tide)[..., None] * np.array([1.0, 0.98, 0.94], np.float32)[None, None, :] ** tide[..., None]
        rough += 0.25 * tide
    mp['rough'] = np.clip(rough, 0.05, 1); mp['color'] = np.clip(col, 0, 1)
    return mp
ELEV = TK.ELEV
E = math.radians(ELEV)
CE, SE = math.cos(E), math.sin(E)
# (11-10, Lowell: "we should not be looking down on the top shelf that is above us") The shelf is above the eye: the
# plank and the boxes standing on it are seen from 9 degrees below (the bench's frame camera puts its top shelf about
# 54 cm above the eye and sees its underside at 8 to 9 degrees, no top). Still the Tools studio, orthographic, the same
# lights and room: only the camera turns. The keys and lamp on the boxes come from the bench's own shelf sheets, seen
# from below already. Everything under the shelf (panels, keys, machines, the opening's mouldings) stays 10 above.
# IRC_SHELF_ELEV=10: the shelf from above, as 11-04.
SHELF_ELEV = float(os.environ.get('IRC_SHELF_ELEV', '-9'))
SHELF_PIECES = ('plank', 'box-bronze', 'box-oxblood')
UNDER_FILL = float(os.environ.get('IRC_UNDER_FILL', '0.25'))   # the low fill on the plank seen from below


def use_elev(deg):
    """Set the camera elevation the shelf's helpers (v_of, frame, render_long) and the next scene use."""
    global ELEV, E, CE, SE
    ELEV = deg; E = math.radians(deg); CE, SE = math.cos(E), math.sin(E)

# the shelf's measures (cm)
PL = dict(thick=2.6, depth=12.0, edge=0.28, period=60.0, fade=10.0, pre=3.0)
BOX = dict(w=36.0, h=7.0, d=10.0, r=0.45, roll=0.25, z_front=11.0, foot_h=0.4, foot_r=0.6, foot_in=1.8, right=12.0, left=1.6, head=3.4, screw_in=1.0)
TRIM = dict(w=1.6, proud=0.65, period=30.0, fade=6.0, pre=2.0)
LAY = {'pxcm': PXCM, 'elev': ELEV, 'samples': SAMPLES, 'out': {}}


def v_of(y, z):
    """The picture's up coordinate (cm in the view plane) of a world point: y cos e - z sin e."""
    return y * CE - z * SE


def frame(s, cam, x0, x1, v0, v1):
    """Frame world x0..x1 and view-plane v0..v1 (v0 the bottom) at exactly PXCM, keeping toolkit.scene()'s camera angle
    and the studio where it is."""
    W = int(math.ceil((x1 - x0) * PXCM / 4 - 1e-6)) * 4; H = int(math.ceil((v1 - v0) * PXCM / 4 - 1e-6)) * 4
    s.render.resolution_x, s.render.resolution_y = W, H
    cam.data.ortho_scale = W / PXCM
    xc = x0 + W / PXCM / 2; vc = v1 - H / PXCM / 2          # anchored at the left and top edges
    cam.location = (xc, vc * CE + 200 * SE, -vc * SE + 200 * CE)
    cam.data.shift_y = 0.0


def shoot(s, cam, name, extra):
    bpy.context.view_layer.update()
    lay = {'size': [s.render.resolution_x, s.render.resolution_y]}
    lay.update(extra)
    t = time.time()
    P.render(s, os.path.join(OUT, name + '.png'))
    lay['s'] = round(time.time() - t, 1)
    LAY['out'][name] = lay


def proj(s, cam, p): return TK.proj(s, cam, p)


# ---------------------------------------------------------------------------------------------------------------------
# materials

# the liquid hammertone's paint for each of the 11-04 cells' base colours: the liquid's lumps and web scatter the light
# more and its coat is glossier, so the paint is set a little lighter to land on the same mean tone (checked on the
# panel proof: the panel's mean against the posted rkit-panel-fine's #34312F)
LIQUID_BASE = {'#1d1812': '#262019', '#1a1610': '#241d16', '#191612': '#211b14'}
LIQUID_K = float(os.environ.get('IRC_LIQUID_K', '0.12'))
LIQUID_RELIEF = float(os.environ.get('IRC_LIQUID_RELIEF', '1.0'))   # the bench's 3.0 read loud under IR Capture's studio      # its wear: dust in the low ground, rubbed edges


def hammertone_fine(base='#1d1812', hi='#3a3226', name='hfine', cells=8.0):
    """(11-10) The bench's liquid hammertone (hammer_liquid.liquid_paint: a fine wandering web between mixed lumps under a
    glossy coat, his Magnecorder's finish) in a dark bronze, each piece at its own place in the maps. Lowell, 11-03, on
    the cells: "the hammertone is too busy--it could be a different surface or finer grain". IRC_HAMMER=cells: the cells."""
    if HAMMER == 'liquid':
        import hammer_liquid as HL
        h = seed_of('liq-' + name + '-' + ','.join('%.2f' % v for v in SEED))
        m = HL.liquid_paint(name, LIQUID_BASE.get(base, base), k=LIQUID_K, seed=101 + h % 3, size_cm=12.0, px_cm=90.0,
                            relief=LIQUID_RELIEF, offset=((h // 3 % 1000) / 1000.0, (h // 3000 % 1000) / 1000.0))
        surface_wear(m, dust=0.04, smudge=0.35, scuff=0.2)
        return grimy(m, dirt='#17130e', amount=0.25, dist=0.25)
    return hammertone_cells(base, hi, name, cells)


def hammertone_cells(base='#1d1812', hi='#3a3226', name='hfine', cells=8.0):
    """shelf_gear.hammertone() calmed: the hammered cells 2.5 x smaller (Voronoi 8 against 3.2) and half as deep, the
    per-cell colour mottle and the metallic flake turned down, so a broad panel reads as a quiet fine-grain finish; the
    broad tone drift and the gloss variation kept (hand-sprayed enamel is never one even colour), the edges rolled and
    worn to primer and steel as before."""
    m = mat(name, srgb(base), rough=0.42, metal=0.2, coat=0.3, coat_rough=0.28, spec=0.4)
    nt = m.node_tree; co = obj_coords(nt)
    wn = node(nt, 'ShaderNodeTexNoise', Scale=2.0, Detail=2.0); nt.links.new(co, wn.inputs['Vector'])
    warp = node(nt, 'ShaderNodeVectorMath', operation='MULTIPLY_ADD'); nt.links.new(wn.outputs['Color'], warp.inputs[0])
    warp.inputs[1].default_value = (0.12, 0.12, 0.12); nt.links.new(co, warp.inputs[2])
    vo = node(nt, 'ShaderNodeTexVoronoi', Scale=cells, Randomness=0.9); vo.feature = 'F1'; nt.links.new(warp.outputs[0], vo.inputs['Vector'])
    dimple = node(nt, 'ShaderNodeMapRange', **{'From Min': 0.0, 'From Max': 0.6}); dimple.clamp = True; dimple.interpolation_type = 'SMOOTHSTEP'
    nt.links.new(vo.outputs['Distance'], dimple.inputs['Value'])
    add_bump(m, dimple.outputs['Result'], 0.35, 0.025)
    sepc = node(nt, 'ShaderNodeSeparateColor'); nt.links.new(vo.outputs['Color'], sepc.inputs[0])
    mix_into(m, 'Base Color', mul(nt, sepc.outputs[0], 0.16), (*srgb(hi), 1))
    flake = noise(nt, co, 300.0, 0.0, 0.5, lo=0.62, hi=0.7)
    mix_into(m, 'Roughness', mul(nt, flake, 0.22), 0.22, 'FLOAT')
    # the broad drift: a slow, soft variation of tone (warmer and cooler, lighter and darker) across the panel
    mix_into(m, 'Base Color', mul(nt, noise(nt, co, 0.25, 3.0, 0.55, lo=0.3, hi=0.75), 0.5), (*srgb('#33281b'), 1))
    mix_into(m, 'Base Color', mul(nt, noise(nt, co, 0.6, 3.0, 0.55, lo=0.45, hi=0.8), 0.3), (*srgb('#13110e'), 1))
    em = edge_mask(nt, 0.3, 6.0); chip = noise(nt, co, 2.4, 8.0, 0.75, lo=0.44, hi=0.6)
    wear = mul(nt, em, chip)
    steel = node(nt, 'ShaderNodeMath', operation='GREATER_THAN'); steel.inputs[1].default_value = 0.7; nt.links.new(wear, steel.inputs[0])
    mix_into(m, 'Base Color', wear, (*srgb('#77736b'), 1)); mix_into(m, 'Base Color', steel.outputs[0], (*srgb('#a8a49c'), 1))
    mix_into(m, 'Metallic', steel.outputs[0], 1.0, 'FLOAT'); mix_into(m, 'Roughness', wear, 0.35, 'FLOAT')
    surface_wear(m, dust=0.25, smudge=0.4, scuff=0.35)
    return grimy(m, dirt='#17130e', amount=0.35, dist=0.25)


def anodised(name='anod', base='#2e2e30'):
    """(11-10) finish_maps' anodised aluminium at true scale (the brushing at 0.05 mm, the dye a little uneven, the edges
    worn through, hairline scratches and dust from its shared wear maps), each panel its own offset. IRC_ANOD=old: the
    11-03 shader below."""
    if ANOD == 'maps':
        import finish_maps as FM
        h = seed_of('anod-' + name + '-' + ','.join('%.2f' % v for v in SEED))
        return FM.material(name, 'anod', base, 0.7, h % 997, 'irc-' + name + str(h))
    return anodised_shader(name, base)


def anodised_shader(name='anod', base='#2e2e30'):
    """Dark graphite anodised aluminium, 1970s-80s rack stock: satin, a fine horizontal brushed grain (streaks along x in
    the relief and the gloss, and an anisotropic highlight), a faint broad unevenness of the dye, the edges worn through
    to bright aluminium where hands and rack rails rub, faint handling marks."""
    m = mat(name, srgb(base), rough=0.36, metal=0.55, spec=0.5, coat=0.08, coat_rough=0.35)
    nt = m.node_tree; b = nt.nodes['Principled BSDF']; co = obj_coords(nt)
    try:
        b.inputs['Anisotropic'].default_value = 0.45
        tg = node(nt, 'ShaderNodeCombineXYZ'); tg.inputs[0].default_value = 1.0
        nt.links.new(tg.outputs[0], b.inputs['Tangent'])
    except Exception: pass
    # the brushing: noise squeezed along x (streaks centimetres long, fractions of a millimetre across)
    # (11-03 proof: at 45 a cm across the streaks were finer than a picture px and averaged away; now 0.4 to 0.8 mm)
    st = node(nt, 'ShaderNodeMapping'); st.inputs['Scale'].default_value = (0.012, 1.0, 1.0); nt.links.new(co, st.inputs[0])
    st2 = node(nt, 'ShaderNodeMapping'); st2.inputs['Scale'].default_value = (0.02, 1.0, 1.0); nt.links.new(co, st2.inputs[0])
    fine = noise(nt, st.outputs[0], 24.0, 6.0, 0.7, lo=0.3, hi=0.7)
    mid = noise(nt, st2.outputs[0], 7.0, 4.0, 0.6, lo=0.3, hi=0.7)
    add_bump(m, fine, 0.3, 0.003); add_bump(m, mid, 0.15, 0.003)
    rr = node(nt, 'ShaderNodeMapRange', **{'To Min': 0.27, 'To Max': 0.47}); nt.links.new(fine, rr.inputs['Value'])
    nt.links.new(rr.outputs['Result'], b.inputs['Roughness'])
    mix_into(m, 'Base Color', mul(nt, fine, 0.45), (*srgb('#3d3d3f'), 1))
    mix_into(m, 'Base Color', mul(nt, mid, 0.3), (*srgb('#242425'), 1))
    # a few longer, brighter brushing scratches
    sc = scratches(nt, co, 14.0, density=0.8, length=60.0)
    mix_into(m, 'Base Color', mul(nt, sc, 0.35), (*srgb('#4a4a4b'), 1)); mix_into(m, 'Roughness', mul(nt, sc, 0.5), 0.2, 'FLOAT')
    # the dye's broad unevenness (a touch warmer and lighter in places)
    mix_into(m, 'Base Color', mul(nt, noise(nt, co, 0.3, 3.0, 0.55, lo=0.35, hi=0.75), 0.3), (*srgb('#353331'), 1))
    # the edges worn through to bright aluminium (slight, patchy)
    em = edge_mask(nt, 0.2, 6.0); chip = noise(nt, co, 3.0, 8.0, 0.75, lo=0.5, hi=0.62)
    wear = mul(nt, em, chip)
    mix_into(m, 'Base Color', wear, (*srgb('#b9b8b3'), 1)); mix_into(m, 'Metallic', wear, 1.0, 'FLOAT')
    mix_into(m, 'Roughness', wear, 0.25, 'FLOAT')
    surface_wear(m, dust=0.15, smudge=0.35, scuff=0.3)
    return grimy(m, dirt='#141414', amount=0.3, dist=0.2)


def calm_up(m, k=0.75):
    """Seen 10 degrees from above, what faces up (a box's lid) is seen at a grazing 80 degrees, where the enamel's coat
    and specular reflect the studio's grey and wash its colour out (11-03 proof: a flat grey band): on up-facing faces
    the coat and specular are turned down and the gloss dulled (a lid also carries more dust and handling)."""
    nt = m.node_tree
    g = nt.nodes.new('ShaderNodeNewGeometry')
    sp = node(nt, 'ShaderNodeSeparateXYZ'); nt.links.new(g.outputs['Normal'], sp.inputs[0])
    up = node(nt, 'ShaderNodeMapRange', **{'From Min': 0.4, 'From Max': 0.9}); up.clamp = True
    nt.links.new(sp.outputs['Y'], up.inputs['Value'])
    f = mul(nt, up.outputs['Result'], k)
    mix_into(m, 'Coat Weight', f, 0.03, 'FLOAT'); mix_into(m, 'Specular IOR Level', f, 0.18, 'FLOAT')
    mix_into(m, 'Roughness', mul(nt, f, 0.6), 0.75, 'FLOAT')
    return m


def stainless(name='stain'):
    m = mat(name, (0.52, 0.52, 0.5), rough=0.3, metal=1.0)
    surface_wear(m, scuff=0.4, smudge=0.3)
    return grimy(m, dirt='#1b1a18', amount=0.5, dist=0.05)


def button_hex(x, y, steel):
    """A button-head hex socket cap screw (ISO 7380 style) standing on the panel's face at z = 0."""
    head = lathe('bhead', [(0.36, 0.0), (0.36, 0.025), (0.34, 0.07), (0.29, 0.12), (0.2, 0.155), (0.1, 0.17), (0.0, 0.173)], 96)
    head.location = (x, y, 0)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.115, depth=0.4, vertices=6, location=(x, y, 0.2))
    c = bpy.context.active_object; c.rotation_euler = (0, 0, 0.3 + x * 0.11 + y * 0.07)
    bpy.context.view_layer.update(); cut(head, c)
    head.data.materials.append(steel)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.11, depth=0.02, vertices=6, location=(x, y, 0.07))
    f = bpy.context.active_object; f.rotation_euler = (0, 0, 0.3 + x * 0.11 + y * 0.07)
    f.data.materials.append(mat('sockdark', srgb('#0c0b0a'), rough=0.85))
    for p in head.data.polygons: p.use_smooth = True


# ---------------------------------------------------------------------------------------------------------------------
# oak: shelf_wood.py's 3D field (the boards' piths, rings, pores, rays), here also for the plank's TOP (seen from above
# now) and made periodic along x so a strip repeats with no seam

def _oak_top(K, Kr):
    """The plank's lacquered top (y = 0), rows z from the front (DEPTH + EDGE_R) back to the wall: shelf_wood.face()'s
    board loop for the plane y = 0 with the lacquered colours, its dings and fine scratches, the front edge rubbed a
    touch lighter, a little dust toward the wall."""
    ss, smooth2, bilinear = SW.ss, SW.smooth2, SW.bilinear
    W = int(SW.LEN * K); xs = -SW.LEN / 2 + (np.arange(W) + 0.5) / K
    H = int((SW.DEPTH + SW.EDGE_R) * Kr)
    zs = SW.DEPTH + SW.EDGE_R - (np.arange(H) + 0.5) / Kr
    ZZ = np.repeat(zs[:, None], W, 1); YY = np.zeros((H, W), np.float32); XX = np.repeat(xs[None, :], H, 0)
    color = np.zeros((H, W, 3), np.float32); rough = np.zeros((H, W), np.float32); height = np.zeros((H, W), np.float32)
    bidx = np.digitize(XX, SW.JOINTS)
    for bi, B in enumerate(SW.BOARDS):
        m = bidx == bi
        if not m.any(): continue
        cols = np.where(m.any(0))[0]; c0, c1 = cols[0], cols[-1] + 1
        X = XX[:, c0:c1]; Y = YY[:, c0:c1]; Z = ZZ[:, c0:c1]; w = c1 - c0
        rs = np.random.default_rng(B['seed'])
        bx = smooth2(1, w, 1, 60 * K, B['seed'] + 1)[0] * B['bend']
        bz = smooth2(1, w, 1, 45 * K, B['seed'] + 2)[0] * B['bend'] * 0.7
        dy = Y - (B['yp'] + bx[None, :]); dz = Z - (B['zp'] + bz[None, :])
        d = np.sqrt(dy * dy + dz * dz)
        nx, nd = int(w / (8 * K)) + 4, int(40 / 0.5) + 4
        wob = smooth2(nd, nx, 1.0, 1.0, B['seed'] + 3); wob2 = smooth2(nd * 3, nx * 6, 1.0, 1.0, B['seed'] + 4)
        xi = (X - X[0, 0]) * K / (8 * K)
        dd = d + 0.22 * bilinear(wob, d / 0.5, xi) + 0.015 * bilinear(wob2, d / 0.17, xi * 6)
        spacing = B['ring'] / 10.0 * (1 + 0.25 * bilinear(smooth2(nd, 8, 1.0, 1.0, B['seed'] + 5), d / 0.5, d * 0 + 2))
        ring = dd / spacing; p = ring - np.floor(ring)
        early = ss(0.0, 0.06, p) * (1 - ss(0.22, 0.42, p)); late = ss(0.5, 0.95, p)
        pr = rs.random((X.shape[0], w)).astype(np.float32)
        k = max(2, int(0.22 * K)); cs = np.cumsum(np.pad(pr, ((0, 0), (k, 0))), 1); pr = (cs[:, k:] - cs[:, :-k]) / k
        pores = ss(0.535, 0.58, pr) * (0.25 + 0.75 * early); pores = np.maximum(pores, ss(0.57, 0.62, pr) * 0.3)
        quarter = ss(0.55, 0.95, 1.0 - np.abs(dy) / (d + 1e-6))
        fl = smooth2(X.shape[0], w, max(1.0, 0.12 * Kr), 1.4 * K, B['seed'] + 6)
        fl2 = smooth2(X.shape[0], w, max(1.0, 0.04 * Kr), 0.25 * K, B['seed'] + 7)
        flk = ss(1.1, 1.6, fl + 0.35 * fl2) * quarter * ss(-0.5, 0.6, fl2)
        fig = smooth2(X.shape[0], w, 3 * Kr, 25 * K, B['seed'] + 8) * 0.06
        tone = np.array(B['tone'], np.float32)
        L, E_, P_, R_ = SW.LATE, SW.EARLY, SW.PORE, SW.RAY
        col = L[None, None, :] * (1 - early[..., None] * 0.75) + E_[None, None, :] * (early[..., None] * 0.75)
        col = col * (1 + 0.12 * late[..., None])
        col = col * (1 - pores[..., None] * 0.65) + P_[None, None, :] * (pores[..., None] * 0.65)
        col = col * (1 - flk[..., None] * 0.7) + R_[None, None, :] * (flk[..., None] * 0.7)
        color[:, c0:c1] = col * (1 + fig[..., None]) * tone[None, None, :]
        rough[:, c0:c1] = 0.40 + 0.18 * pores - 0.12 * flk + 0.04 * early
        height[:, c0:c1] = -0.6 * pores - 0.15 * early + 0.25 * flk
    rr = np.random.default_rng(78)
    rub = ss(SW.DEPTH - 0.8, SW.DEPTH + 0.2, ZZ) * ss(-0.2, 0.9, smooth2(H, W, 1 * Kr, 6 * K, 52))
    color = color * (1 + 0.25 * rub[..., None]); rough += 0.2 * rub
    for _ in range(int(SW.LEN * 0.5)):                   # dings: small dents, a little dirt in them
        cx = rr.uniform(0, W); cy = rr.uniform(0, H); r = rr.uniform(0.04, 0.14) * K
        ry_ = r * Kr / K
        ys0, ys1 = max(0, int(cy - 3 * ry_)), min(H, int(cy + 3 * ry_) + 1); xs0, xs1 = max(0, int(cx - 3 * r)), min(W, int(cx + 3 * r) + 1)
        gy, gx = np.mgrid[ys0:ys1, xs0:xs1]
        dn = np.exp(-(((gx - cx) / (r * rr.uniform(1, 2.5))) ** 2 + ((gy - cy) / max(ry_, 0.6)) ** 2))
        height[ys0:ys1, xs0:xs1] -= 1.0 * dn; color[ys0:ys1, xs0:xs1] *= (1 - 0.25 * dn[..., None]); rough[ys0:ys1, xs0:xs1] += 0.15 * dn
    sc = rr.random((H, W)).astype(np.float32)
    k2 = max(3, int(1.5 * K)); cs = np.cumsum(np.pad(sc, ((0, 0), (k2, 0))), 1); sc = (cs[:, k2:] - cs[:, :-k2]) / k2
    sc = ss(0.62, 0.66, sc); rough += 0.1 * sc; color *= (1 + 0.06 * sc[..., None])
    back = ss(SW.DEPTH * 0.35, 0.0, ZZ)[..., None] * (0.5 + 0.5 * ss(-0.8, 0.8, smooth2(H, W, 4 * Kr, 9 * K, 61)))[..., None]
    color = color * (1 - 0.12 * back) + SW.lin(SW.hexc('#5c544a'))[None, None, :] * (0.12 * back)
    return dict(color=np.clip(color, 0, 1), rough=np.clip(rough, 0.05, 1), height=height, x0=-SW.LEN / 2, K=K, Kr=Kr, rows=H)


def _periodic(maps, K, x0, P, F, lo, hi):
    """Cut [xa, xa + P + F) out of each map (the same columns of each) and fold the last F cm smoothly into the first,
    so each is exactly periodic over P cm; xa (within lo .. hi - P - F) is the start whose fold region matches best."""
    def cols(x): return int(round((x - x0) * K))
    p, f = int(round(P * K)), int(round(F * K))
    ref = maps[0]['color'].mean(-1)
    best, bx = None, lo
    for xa in np.arange(lo, hi - P - F, 0.5):
        c = cols(xa); d = np.abs(ref[:, c:c + f] - ref[:, c + p:c + p + f]).mean()
        if best is None or d < best: best, bx = d, xa
    c = cols(bx)
    w = (np.arange(f) + 0.5) / f; w = w * w * (3 - 2 * w)
    out = []
    for mp in maps:
        o = {}
        for key in ('color', 'rough', 'height'):
            a = mp[key][:, c:c + p + f].copy()
            ww = w.reshape((1, f) + (1,) * (a.ndim - 2))
            a[:, :f] = ww * a[:, :f] + (1 - ww) * a[:, p:p + f]
            o[key] = np.ascontiguousarray(a[:, :p])
        out.append(o)
    return out, float(bx)


def oak_material(name, mp, u_axis, u0, P, v_axis, v_lo, v_hi, coat=0.2, tint=(1, 1, 1), dust=0.2, spec=0.35, rough_add=0.0):
    """A lacquered oak material from a periodic map: u along u_axis ('X' or 'Y', object coords) from u0 over P cm
    (REPEAT), v along v_axis from v_lo (the map's last row) to v_hi (its first row)."""
    col = np.clip(mp['color'] * np.array(tint, np.float32)[None, None, :], 0, 1)
    m = mat(name, (0.2, 0.13, 0.08), rough=0.4, coat=coat, coat_rough=0.3, spec=spec)
    nt = m.node_tree; b = nt.nodes['Principled BSDF']
    tc = nt.nodes.new('ShaderNodeTexCoord'); sep = node(nt, 'ShaderNodeSeparateXYZ'); nt.links.new(tc.outputs['Object'], sep.inputs[0])
    u = node(nt, 'ShaderNodeMapRange', **{'From Min': u0, 'From Max': u0 + P}); u.clamp = False
    nt.links.new(sep.outputs[u_axis], u.inputs['Value'])
    v = node(nt, 'ShaderNodeMapRange', **{'From Min': v_lo, 'From Max': v_hi}); v.clamp = False
    nt.links.new(sep.outputs[v_axis], v.inputs['Value'])
    cv = node(nt, 'ShaderNodeCombineXYZ'); nt.links.new(u.outputs['Result'], cv.inputs['X']); nt.links.new(v.outputs['Result'], cv.inputs['Y'])
    h = mp['height']; hn = (h - h.min()) / (np.ptp(h) + 1e-6)
    ts = [SG.img_tex(nt, name + 'c', col, True, 'REPEAT'), SG.img_tex(nt, name + 'r', mp['rough'], False, 'REPEAT'),
          SG.img_tex(nt, name + 'h', hn, False, 'REPEAT')]
    for t in ts: nt.links.new(cv.outputs['Vector'], t.inputs['Vector'])
    nt.links.new(ts[0].outputs['Color'], b.inputs['Base Color'])
    if rough_add:
        ra = node(nt, 'ShaderNodeMath', operation='ADD'); ra.inputs[1].default_value = rough_add; ra.use_clamp = True
        nt.links.new(ts[1].outputs['Color'], ra.inputs[0]); nt.links.new(ra.outputs[0], b.inputs['Roughness'])
    else: nt.links.new(ts[1].outputs['Color'], b.inputs['Roughness'])
    add_bump(m, ts[2].outputs['Color'], 0.35, 0.012)
    surface_wear(m, dust=dust, smudge=0.3)
    return grimy(m, dirt='#1a120b', amount=0.35, dist=0.4)


def plank_maps(K):
    """The plank's front-edge and top maps, periodic over PL['period'] cm along x.
    (11-04, after the bench's shop wear) the piths straighter (see below), the maps at twice the picture's px a cm (pores and rays no longer as soft as the
    maps' interpolation), and wear: larger dents, fine scratches through the lacquer, a faint water mark on the edge.
    The strip repeats every 60 cm, so the wear repeats with it: it is kept sparse so the repeat doesn't read."""
    save = SW.LEN, SW.DEPTH, SW.BOARDS
    SW.LEN, SW.DEPTH = 120.0, PL['depth']
    # the piths bend a quarter as much (the bench's shelf_wear.straighter): long arches on the edge, no tight bullseyes.
    # (Tried 11-04: piths above the plank for straight lines; the rays then flecked the whole edge. Not kept.)
    SW.BOARDS = [dict(B, bend=B['bend'] * 0.25) for B in save[2]]
    try:
        front = SW.face(K, 'front')
        top = _oak_top(K, 24.0)
    finally:
        SW.LEN, SW.DEPTH, SW.BOARDS = save
    (fr, tp), xa = _periodic([front, top], K, -60.0, PL['period'], PL['fade'], -56.0, 56.0)
    rng = set_seed('plank-maps')
    rf = fr['rough'].shape[0] / (SW.THICK + SW.EDGE_R)
    map_wear(fr, rf, K, rng, dents=3, scratch=10, water=(0.62, 0.45, 0.035))
    map_wear(tp, 24.0, K, rng, dents=5, scratch=24, ding_scale=0.8)
    return fr, tp, xa


def trim_maps(K, which):
    """A moulding's map: shelf_wood's front field from another board (board 2 for the horizontal run, 0 for the
    vertical), periodic over TRIM['period'] cm."""
    save = SW.LEN, SW.JOINTS
    SW.LEN = 80.0
    SW.JOINTS = (-2000.0, -1000.0) if which == 'h' else (1000.0, 2000.0)
    try:
        f = SW.face(K, 'front')
    finally:
        SW.LEN, SW.JOINTS = save
    (fr,), xa = _periodic([f], K, -40.0, TRIM['period'], TRIM['fade'], -39.0, 39.0)
    return fr, xa


# ---------------------------------------------------------------------------------------------------------------------
# the pieces

def panel_piece(name, finish):
    """toolkit.piece_panel() with another finish (same size, rolled edges, a screw in each corner). Each name its own
    seed (11-04): panel-fine-b, panel-nam-b are the same stock with its own stipple, rub and handling marks."""
    set_seed(name)
    w, h, d = TK.PANEL['w'], TK.PANEL['h'], TK.PANEL['d']
    s, cam = TK.scene(w, h, 0.4)
    TK.catcher(-d)
    o = rbox('panel', w, h, d, -d, TK.PANEL['r'], roll=0.1)
    TK.flat_faces(o)
    c = TK.PANEL['screw']
    if finish == 'fine':
        o.data.materials.append(hammertone_fine())
        ni = TK.nickel()
        for sx in (-1, 1):
            for sy in (-1, 1): screw(sx * (w / 2 - c), sy * (h / 2 - c), ni)
    else:
        o.data.materials.append(anodised())
        st = stainless()
        for sx in (-1, 1):
            for sy in (-1, 1): button_hex(sx * (w / 2 - c), sy * (h / 2 - c), st)
    bpy.context.view_layer.update()
    lay = {'cm': [w, h], 'tl': proj(s, cam, (-w / 2, h / 2, 0.0)), 'br': proj(s, cam, (w / 2, -h / 2, 0.0))}
    shoot(s, cam, name, lay)


# ---------------------------------------------------------------------------------------------------------------------
# the keys (11-04): the app draws one blank Tools key (rkit-key-*) under every legend, so every key on the page was the
# same key. Now six keys, each its own seed and look (after the bench's KEY_LOOK); the app picks one per button by its
# label, so a button keeps its key. aged: 0 new ivory .. 1 yellowed (deepest at the rim); tone: a greyer cap (a
# replacement); stain (u, v, r as fractions of the half cap; strength); gloss: coat roughness; use: finger polish in the
# middle (the stipple flattened, glossier); chip: the bezel's paint chipped at a corner to the bright casting.
# No cap is turned in its bezel: the app's legends are drawn level, so a turned cap would show.
KEY_LOOK = {
    'a': dict(aged=0.35, use=0.85, gloss=0.17),
    'b': dict(aged=0.75, use=0.5, gloss=0.22),                                     # yellowed
    'c': dict(aged=0.1, use=0.15, gloss=0.33),                                     # the newest
    'd': dict(aged=0.45, use=0.55, gloss=0.25, stain=(0.45, -0.35, 0.26, 0.28)),    # a faint stain, lower right
    'e': dict(aged=0.5, use=0.6, gloss=0.23, tone='#c8bba4'),                      # greyer: a replacement cap
    'f': dict(aged=0.9, use=0.3, gloss=0.3, chip=(-1, -1)),                        # the most yellowed, its bezel chipped
}


def cap_mat_blank(lit, name, wcm, hcm, look, rng):
    """shelf_wear.cap_mat_worn() without a legend: this key's own age, stain, gloss and polish; the stipple flattened where
    fingers have polished it; lit, the grain-of-wheat lamp glows through, a little less and warmer through an aged cap."""
    aged = look.get('aged', 0.3)
    new_off, old_off = np.array(srgb('#ddcca2')), np.array(srgb('#cdb072'))
    base = new_off * (1 - aged) + old_off * aged
    if look.get('tone'): base = base * 0.6 + np.array(srgb(look['tone'])) * 0.4
    col = tuple(base) if not lit else srgb('#e8902e')
    m = mat(name, col, rough=0.36 + 0.1 * (1 - look.get('use', 0.3)), coat=0.2, coat_rough=look.get('gloss', 0.25), spec=0.35)
    nt = m.node_tree; b = nt.nodes['Principled BSDF']
    try:
        b.inputs['Subsurface Weight'].default_value = 0.12; b.inputs['Subsurface Radius'].default_value = (0.25, 0.18, 0.1)
        b.inputs['Subsurface Scale'].default_value = 0.08
    except Exception: pass
    tc = nt.nodes.new('ShaderNodeTexCoord'); sep = node(nt, 'ShaderNodeSeparateXYZ'); nt.links.new(tc.outputs['Object'], sep.inputs[0])
    u = node(nt, 'ShaderNodeMapRange', **{'From Min': -wcm / 2, 'From Max': wcm / 2}); nt.links.new(sep.outputs['X'], u.inputs['Value'])
    v = node(nt, 'ShaderNodeMapRange', **{'From Min': -hcm / 2, 'From Max': hcm / 2}); nt.links.new(sep.outputs['Y'], v.inputs['Value'])
    cv = node(nt, 'ShaderNodeCombineXYZ'); nt.links.new(u.outputs['Result'], cv.inputs['X']); nt.links.new(v.outputs['Result'], cv.inputs['Y'])
    h, w = int(hcm * 150), int(wcm * 150)
    yy, xx = np.mgrid[0:h, 0:w]; ux = (xx + 0.5) / w * 2 - 1; vy = 1 - (yy + 0.5) / h * 2
    rim = ss(0.55, 1.0, np.maximum(np.abs(ux), np.abs(vy)))
    stain = np.zeros((h, w), np.float32)
    if look.get('stain'):
        su, sv, sr, st = look['stain']
        n = blur(rng.random((h, w)), 9.0); n = (n - n.mean()) / (n.std() + 1e-6)
        d = np.sqrt(((ux - su) / sr) ** 2 + ((vy - sv) / (sr * 1.3 * wcm / hcm)) ** 2) + 0.18 * n
        stain = st * ss(1.0, 0.55, d) * 0.55 + st * np.exp(-((d - 0.92) / 0.07) ** 2) * 0.45     # a body and a tide line
    polish = look.get('use', 0.3) * np.exp(-((ux / 0.5) ** 2 + (vy / 0.6) ** 2))
    t_rim = SG.img_tex(nt, name + 'r', rim.astype(np.float32), False, 'CLIP')
    t_st = SG.img_tex(nt, name + 's', stain.astype(np.float32), False, 'CLIP')
    t_po = SG.img_tex(nt, name + 'p', polish.astype(np.float32), False, 'CLIP')
    for t in (t_rim, t_st, t_po): nt.links.new(cv.outputs['Vector'], t.inputs['Vector'])
    co = obj_coords(nt)
    stip = noise(nt, co, 180.0, 2.0, 0.5)
    inv_po = node(nt, 'ShaderNodeMath', operation='SUBTRACT'); inv_po.inputs[0].default_value = 1.0
    nt.links.new(t_po.outputs['Color'], inv_po.inputs[1])
    add_bump(m, mul(nt, stip, inv_po.outputs[0]), 0.14, 0.0015)
    add_bump(m, noise(nt, co, 9.0, 3.0, 0.6), 0.06, 0.004)
    mix_into(m, 'Roughness', mul(nt, t_po.outputs['Color'], 0.9), 0.16, 'FLOAT')
    if lit:
        gr = node(nt, 'ShaderNodeVectorMath', operation='MULTIPLY'); gr.inputs[1].default_value = (2.0 / wcm, 2.6 / hcm, 0)
        off = node(nt, 'ShaderNodeVectorMath', operation='SUBTRACT'); off.inputs[1].default_value = (0, 0.06, 0)
        nt.links.new(tc.outputs['Object'], off.inputs[0]); nt.links.new(off.outputs[0], gr.inputs[0])
        ln = node(nt, 'ShaderNodeVectorMath', operation='LENGTH'); nt.links.new(gr.outputs[0], ln.inputs[0])
        fall = node(nt, 'ShaderNodeMapRange', **{'From Min': 0.0, 'From Max': 1.3, 'To Min': 1.6, 'To Max': 0.35})
        fall.interpolation_type = 'SMOOTHSTEP'; nt.links.new(ln.outputs['Value'], fall.inputs['Value'])
        grain = noise(nt, co, 30.0, 3.0, 0.6, lo=0.3, hi=0.7)
        e = node(nt, 'ShaderNodeMath', operation='MULTIPLY_ADD'); e.inputs[1].default_value = 0.25
        nt.links.new(grain, e.inputs[0]); nt.links.new(fall.outputs['Result'], e.inputs[2])
        inv = node(nt, 'ShaderNodeMath', operation='SUBTRACT'); inv.inputs[0].default_value = 1.0; inv.use_clamp = True
        nt.links.new(mul(nt, t_st.outputs['Color'], 0.8), inv.inputs[1])
        e2 = node(nt, 'ShaderNodeMath', operation='MULTIPLY'); nt.links.new(e.outputs[0], e2.inputs[0]); nt.links.new(inv.outputs[0], e2.inputs[1])
        e3 = mul(nt, e2.outputs[0], 1.0 - 0.18 * aged)
        hot = np.array(srgb('#ff8c26')) * (1 - aged * 0.5) + np.array(srgb('#ff7414')) * aged * 0.5
        b.inputs['Emission Color'].default_value = (*hot, 1)
        nt.links.new(e3, b.inputs['Emission Strength'])
    else:
        mix_into(m, 'Base Color', mul(nt, noise(nt, co, 2.0, 4.0, 0.6, lo=0.4, hi=0.75), 0.35), (*srgb('#c4b48a'), 1))
        mix_into(m, 'Base Color', mul(nt, t_rim.outputs['Color'], 0.35 * aged + 0.08), (*srgb('#b8995a'), 1))
    mix_into(m, 'Base Color', t_st.outputs['Color'], (*srgb('#8e6a3c' if not lit else '#9a4a14'), 1))
    mix_into(m, 'Roughness', t_st.outputs['Color'], 0.55, 'FLOAT')
    surface_wear(m, smudge=0.4 + 0.3 * look.get('use', 0.3), scuff=0.25)
    return grimy(m, dirt='#3a3122', amount=0.3 + 0.15 * aged, dist=0.06)


def bezel_mat_chip(name, at):
    """The bezel's black casting with its paint chipped at a corner (at: object coordinates) to the bright metal."""
    m = SG.black_cast(name)
    nt = m.node_tree; tc = nt.nodes.new('ShaderNodeTexCoord')
    d = node(nt, 'ShaderNodeVectorMath', operation='DISTANCE'); nt.links.new(tc.outputs['Object'], d.inputs[0])
    d.inputs[1].default_value = at
    mr = node(nt, 'ShaderNodeMapRange', **{'From Min': 0.16, 'From Max': 0.11}); mr.clamp = True
    nt.links.new(d.outputs['Value'], mr.inputs['Value'])
    ragged = mul(nt, mr.outputs['Result'], noise(nt, obj_coords(nt), 40.0, 4.0, 0.7, lo=0.35, hi=0.55))
    mix_into(m, 'Base Color', ragged, (*srgb('#8a867e'), 1)); mix_into(m, 'Metallic', ragged, 1.0, 'FLOAT')
    mix_into(m, 'Roughness', ragged, 0.3, 'FLOAT'); add_bump(m, ragged, -0.4, 0.01)
    return m


def piece_key(v, states=('off', 'lit', 'down', 'litdown')):
    """toolkit.piece_key() with this key's own seed and look; writes key-<state>-<v>.png (and toolkit_post's layout)."""
    look = KEY_LOOK[v]
    w, h, bz = TK.KEY['w'], TK.KEY['h'], TK.KEY['bezel']
    for state in states:
        rng = set_seed('key-' + v)                  # the same key in every state
        s, cam = TK.scene(w + 2 * bz, h + 2 * bz, 0.3)
        TK.catcher(0.0)
        bez = rbox('kbezel', w + 2 * bz, h + 2 * bz, 0.25, 0.0, TK.KEY['r'] + bz * 0.6, roll=0.06)
        cut(bez, prism('khole', _rring((w + 0.06) / 2, (h + 0.06) / 2, TK.KEY['r'], 0.0, 0, n_arc=8), -2, 2))
        chamfer(bez, 0.02, 2)
        if look.get('chip'):
            cx, cy = look['chip']
            bez.data.materials.append(bezel_mat_chip('kbez-' + v, (cx * (w / 2 + bz - 0.07), cy * (h / 2 + bz - 0.07), 0.125)))
        else:
            bez.data.materials.append(SG.black_cast('kbez'))
        well = rbox('kwell', w + 0.1, h + 0.1, 0.3, -0.3, 0.05); well.data.materials.append(mat('kwell', (0.01, 0.009, 0.008), rough=0.8))
        lit = state in ('lit', 'litdown'); down = state in ('down', 'litdown')
        zc = 0.03 if down else 0.15
        cap = rbox('cap', w, h, 0.3, zc, TK.KEY['r'], roll=0.07, seg=4)
        TK.flat_faces(cap)
        cap.data.materials.append(cap_mat_blank(lit, 'cap-%s-%s' % (v, state), w, h, look, rng))
        if lit:
            L = bpy.data.lights.new('kglow', 'POINT'); L.energy = 0.3 * (1 - 0.15 * look.get('aged', 0.3))
            L.color = srgb('#ffa040'); L.shadow_soft_size = 0.6
            g = bpy.data.objects.new('kglow', L); s.collection.objects.link(g); g.location = (0, 0, zc + 0.9)
        TK.shoot(s, cam, 'key-%s-%s' % (state, v), w + 2 * bz, h + 2 * bz,
                 lambda s, cam: {'cap_tl': proj(s, cam, (-w / 2, h / 2, zc + 0.3)), 'cap_br': proj(s, cam, (w / 2, -h / 2, zc + 0.3))})


def piece_panel_fine(): panel_piece('panel-fine', 'fine')
def piece_panel_nam(): panel_piece('panel-nam', 'nam')


def plank_obj(L, x0=0.0):
    """The plank: the top at y = 0, its back against the wall (z = 0), its front edge at z = depth; edges rolled."""
    t, d = PL['thick'], PL['depth']
    bpy.ops.mesh.primitive_cube_add(size=1, location=(x0, -t / 2, d / 2)); o = bpy.context.active_object; o.name = 'plank'
    o.scale = (L, t, d); bpy.ops.object.transform_apply(location=True, scale=True)
    chamfer(o, w=PL['edge'], seg=4)
    return o


def piece_plank():
    K = PXCM
    fr, tp, xa = plank_maps(2 * K)
    set_seed('plank')
    Pp, pre = PL['period'], PL['pre']
    X0 = -Pp / 2                                           # the picture's tile: x from X0 to X0 + P
    s, cam = TK.scene(20, 10, 0.5)
    TK.catcher(0.0)                                        # the wall
    o = plank_obj(Pp + 60)                                 # its ends' shadows well outside the frame
    mf = oak_material('oakfront', fr, 'X', X0, Pp, 'Y', -(SW.THICK + SW.EDGE_R), 0.0)
    # (11-03 proof: at 10 degrees the top is seen at a grazing 80 degrees, where the full lacquer's reflection washed the
    # oak to grey; the top's sheen is calmed: an oiled, rubbed-down top rather than a fresh gloss)
    mt = oak_material('oaktop', tp, 'X', X0, Pp, 'Z', 0.0, PL['depth'] + SW.EDGE_R, coat=0.04, dust=0.1, spec=0.2, rough_add=0.18)
    o.data.materials.append(mf); o.data.materials.append(mt)
    for p in o.data.polygons:
        p.material_index = 1 if p.normal.y > 0.6 else 0
    t, d = PL['thick'], PL['depth']
    v_top = 1.4; v_bot = v_of(-t, d) - 12.5       # above: the wall's contact darkening over the back edge; below: the
    #                                               key's shadow drops about 10.5 cm, its penumbra 3 more
    frame(s, cam, X0 - pre, X0 + Pp + 0.5, v_bot, v_top)
    bpy.context.view_layer.update()
    lay = {'x_tile': [X0, X0 + Pp], 'x_pre': pre,
           'px_tile0': proj(s, cam, (X0, 0, 0))[0], 'px_tile1': proj(s, cam, (X0 + Pp, 0, 0))[0],
           'row_back': proj(s, cam, (0, 0, 0))[1], 'row_front_top': proj(s, cam, (0, 0, d))[1],
           'row_front_bot': proj(s, cam, (0, -t, d))[1], 'map_xa': xa}
    shoot(s, cam, 'plank', lay)


def piece_box(name):
    finish = name.split('-')[1]
    w, h, d, zf, fh = BOX['w'], BOX['h'], BOX['d'], BOX['z_front'], BOX['foot_h']
    s, cam = TK.scene(20, 10, 0.5)
    TK.catcher(0.0)                                        # the wall
    pc = plank_obj(w + 60); pc.is_shadow_catcher = True    # the plank, as a shadow catcher only
    set_seed('box-' + finish)
    m = hammertone_fine(base='#1a1610', hi='#3d3224', name='hbox') if finish == 'bronze' else SG.crackle(base='#2e0d09')
    calm_up(m)
    # (11-04, after the bench's shop wear) four slotted screws in the face's corners, the paint scuffed round each by a
    # screwdriver, and more chips toward the ends; all inside the end caps the app keeps whole (2.9 cm into the face)
    sx_, sy_ = BOX['w'] / 2 - BOX['screw_in'], BOX['h'] / 2 - BOX['screw_in']
    pts = [(sx * sx_, sy * sy_, zf) for sx in (-1, 1) for sy in (-1, 1)]        # the box's object coordinates (its origin
    screw_ring(m, pts); corner_wear(m, w / 2)                                    # at x 0, y its middle, z 0; face at zf)
    o = rbox('box', w, h, d, zf - d, BOX['r'], roll=BOX['roll'])
    o.location = (0, fh + h / 2, 0); o.data.materials.append(m); TK.flat_faces(o)
    nk = SG.nickel('boxscrew', seed=seed_of(name) % 97)
    for (px_, py_, _) in pts:
        before = set(ob.name for ob in bpy.data.objects)
        screw(px_, py_ + fh + h / 2, nk)
        for ob in bpy.data.objects:
            if ob.name not in before: ob.location.z += zf
    rm = SG.rubber()
    for fx in (-(w / 2 - BOX['foot_in']), w / 2 - BOX['foot_in']):
        bpy.ops.mesh.primitive_cylinder_add(radius=BOX['foot_r'], depth=fh + 0.05, vertices=40, location=(fx, fh / 2, zf - 1.3))
        f = bpy.context.active_object; f.rotation_euler = (math.radians(90), 0, 0); f.data.materials.append(rm)
        bpy.ops.object.shade_smooth()
    v_top = max(v_of(fh + h, zf - d), v_of(fh + h, zf)) + BOX['head']; v_bot = v_of(0.0, PL['depth'])   # the wall's darkening round the box
    frame(s, cam, -w / 2 - BOX['left'], w / 2 + BOX['right'], v_bot, v_top)
    bpy.context.view_layer.update()
    lay = {'cm': [w, h], 'box_x': [-w / 2, w / 2],
           'px_left': proj(s, cam, (-w / 2, 0, zf))[0], 'px_right': proj(s, cam, (w / 2, 0, zf))[0],
           'row_lid_back': proj(s, cam, (0, fh + h, zf - d if ELEV > 0 else zf))[1], 'row_face_top': proj(s, cam, (0, fh + h, zf))[1],
           'row_face_bot': proj(s, cam, (0, fh, zf))[1], 'row_plank_front_top': proj(s, cam, (0, 0, PL['depth']))[1],
           'row_plank_back': proj(s, cam, (0, 0, 0))[1], 'edge_in': BOX['r'] + BOX['roll'], 'roll': BOX['roll'],
           'foot_in': BOX['foot_in'], 'foot_r': BOX['foot_r']}
    shoot(s, cam, name, lay)


def moulding(name, L, vertical):
    """A moulding: 1.6 cm wide, 0.65 cm proud of the wall, an ogee falling to a small rounded step on each side, a
    slightly crowned flat in the middle; L long, along x (or y if vertical), centred at the origin."""
    import bmesh
    hw = TRIM['w'] / 2
    def hgt(u):
        a = abs(u)
        if a <= 0.42: return 0.62 + 0.03 * (1 - (a / 0.42) ** 2)
        if a <= 0.72:
            t = (0.72 - a) / 0.30; return 0.24 + 0.38 * t * t * (3 - 2 * t)
        t = min(1.0, (a - 0.72) / (hw - 0.72)); return 0.24 * math.sqrt(max(0.0, 1 - t * t)) if t < 1 else 0.0
    us = list(np.linspace(-hw, hw, 97))
    prof = [(u, max(hgt(u), 0.0)) for u in us]
    prof[0] = (-hw, 0.0); prof[-1] = (hw, 0.0)
    nl = 2
    bm = bmesh.new()
    rows = []
    for j in range(nl):
        a = -L / 2 + L * j / (nl - 1)
        rows.append([bm.verts.new((u, a, z) if vertical else (a, u, z)) for (u, z) in prof])
    for j in range(nl - 1):
        for i in range(len(prof) - 1):
            q = [rows[j][i], rows[j][i + 1], rows[j + 1][i + 1], rows[j + 1][i]]
            bm.faces.new(q if vertical else q[::-1])
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    o = bpy.data.objects.new(name, me); bpy.context.scene.collection.objects.link(o)
    me.update(); me.validate()
    # make the profile face the camera (+z)
    if sum(p.normal.z for p in me.polygons) < 0:
        for p in me.polygons: p.flip()
        me.update()
    for p in me.polygons: p.use_smooth = True
    return o


def piece_trim(which):
    K = PXCM
    mp, xa = trim_maps(K, which)
    rng = set_seed('trim-' + which)           # (11-04) each run its own board's wear: dings, a few scratches
    map_wear(mp, mp['rough'].shape[0] / 2.95, K, rng, dents=2, scratch=6, ding_scale=0.6)
    Pt, pre, hw = TRIM['period'], TRIM['pre'], TRIM['w'] / 2
    s, cam = TK.scene(20, 10, 0.5)
    TK.catcher(0.0)
    vertical = which == 'v'
    o = moulding('trim', Pt + 30, vertical)
    tint = (0.62, 0.5, 0.42)                               # stained darker and redder than the plank
    across = 'X' if vertical else 'Y'
    # the map's rows run across the moulding (its 2.95 cm cover the 1.6 cm face with a little to spare)
    m = oak_material('trimoak', mp, 'Y' if vertical else 'X', -Pt / 2, Pt, across, -1.5, 1.45, coat=0.15, tint=tint, dust=0.1, spec=0.28, rough_add=0.08)
    o.data.materials.append(m)
    A0 = -Pt / 2
    if vertical:
        # the tile runs down from y = -A0 (the top) to y = A0 - Pt ... the frame: x -1.0 .. +2.4, v covering the length
        x0, x1 = -hw - 0.9, hw + 1.7
        vt = v_of(-A0 + pre, 0.0); vb = v_of(-A0 - Pt - 0.5, 0.0)
        frame(s, cam, x0, x1, vb, vt)
        bpy.context.view_layer.update()
        lay = {'tile_y': [-A0, -A0 - Pt], 'pre': pre, 'row_tile0': proj(s, cam, (0, -A0, 0))[1],
               'row_tile1': proj(s, cam, (0, -A0 - Pt, 0))[1], 'px_left': proj(s, cam, (-hw, 0, 0))[0],
               'px_right': proj(s, cam, (hw, 0, 0))[0]}
    else:
        x0, x1 = A0 - pre, A0 + Pt + 0.5
        vt = v_of(hw, 0.0) + 0.9; vb = v_of(-hw, 0.0) - 1.7
        frame(s, cam, x0, x1, vb, vt)
        bpy.context.view_layer.update()
        lay = {'x_tile': [A0, A0 + Pt], 'pre': pre, 'px_tile0': proj(s, cam, (A0, 0, 0))[0],
               'px_tile1': proj(s, cam, (A0 + Pt, 0, 0))[0], 'row_top': proj(s, cam, (0, hw, 0))[1],
               'row_bot': proj(s, cam, (0, -hw, 0))[1], 'row_crown': proj(s, cam, (0, 0, 0.65))[1]}
    lay['map_xa'] = xa
    shoot(s, cam, 'trim-' + which, lay)


# ---------------------------------------------------------------------------------------------------------------------
# (11-10) shop wood: the shelf and the mouldings as the bench's (shop_wood.py, Lowell 11-04 on the bench's shelf: "too
# smooth ... office furniture, not a workshop shelf", then "loved the new wood"; on IR Capture's oak, 11-04: "looks too
# smooth and fake, no texture"). Each board a real mesh: its section swept along its length about every mm, pushed out
# and in by a height field in true cm (raised latewood, planer chatter or saw marks, knots with checks, the top arris
# chewed and grimed where hands go, dents, gouges, screws and empty holes, stains), no lacquer.
# The bench draws its shelf from the frame camera (from below); IR Capture's one camera is the Tools studio's, 10
# degrees above, so the boards are built here in that studio and seen from above: the top face, the front edge.
#
# The strips are long enough for a large screen and never repeat (400 cm: 3200 pt at the shelf's 8 pt a cm). Rendered
# whole under one studio, the far end would be lit from 2 m off the key's side; so the strip is rendered in segments
# with the whole studio moved along with each (every part of the shelf lit as a piece at the studio's centre is), the
# segments cross-faded over their overlaps.
LONG = dict(plank=float(os.environ.get('IRC_PLANK_CM', 400.0)), trim_h=float(os.environ.get('IRC_TRIM_H_CM', 400.0)),
            trim_v=float(os.environ.get('IRC_TRIM_V_CM', 260.0)), seg=40.0, ov=4.0)
WOOD_AGE = float(os.environ.get('WOOD_AGE', 1.2))     # (a shade darker than the bench's 1.0: the Tools studio's light lifts raw pine toward orange)
_EMIT = {'key', 'top', 'rim', 'ceil', 'side'}


def studio_objects(s):
    """The studio's lights and reflection cards (gear_kit.stage), to be moved together."""
    return [o for o in s.objects if o.type == 'LIGHT' or (o.type == 'MESH' and o.name.split('.')[0] in _EMIT)]


def wall(z=0.0, size=1400.0):
    bpy.ops.mesh.primitive_plane_add(size=size, location=(0, 0, z)); c = bpy.context.active_object; c.is_shadow_catcher = True
    return c


def render_long(s, cam, name, vertical, u0, u1, c0, c1):
    """A long strip rendered in segments, the studio moved to each segment's middle, cross-faded over the overlaps.
    u: the strip's length in the picture's own axis, cm: x for a horizontal strip, the view plane's v (y cos 10) for a
    vertical one (u1 its top); c0..c1 across: v (bottom, top) for a horizontal strip, x for a vertical one. Everything is
    worked in whole pixels, so the segments' pixels fall on one grid. Writes <name>.png; returns its size (W, H)."""
    sp, op = int(round(LONG['seg'] * PXCM)), int(round(LONG['ov'] * PXCM))
    Lp = int(round((u1 - u0) * PXCM))
    studio = studio_objects(s); home = {o.name: tuple(o.location) for o in studio}
    acc = None; wsum = np.zeros(Lp, np.float32)
    n = max(1, int(math.ceil(Lp / sp)))
    for i in range(n):
        pa, pb = i * sp, min(Lp, (i + 1) * sp)                       # px along the strip: from u0 (horizontal) or u1 (vertical)
        lo, hi = pa - (op if i > 0 else 0), pb + (op if i < n - 1 else 0)
        mid = (pa + pb) / 2 / PXCM
        for o in studio:
            x, y, z = home[o.name]
            o.location = (x, y + (u1 - mid) / CE, z) if vertical else (x + u0 + mid, y, z)
        if vertical:
            frame(s, cam, c0, c1, u1 - hi / PXCM, u1 - lo / PXCM)
        else:
            frame(s, cam, u0 + lo / PXCM, u0 + hi / PXCM, c0, c1)
        bpy.context.view_layer.update()
        path = os.path.join(OUT, '%s-seg%02d.png' % (name, i))
        P.render(s, path)
        with Image.open(path) as f:                                   # (closed before the remove: Windows, the iMac)
            im = np.asarray(f.convert('RGBA')).astype(np.float32) / 255.0
        im[..., :3] *= im[..., 3:4]
        span = hi - lo
        im = im[:span] if vertical else im[:, :span]                  # frame() rounds up to 4 px: its extra px dropped
        if acc is None:
            acc = np.zeros((Lp, im.shape[1], 4) if vertical else (im.shape[0], Lp, 4), np.float32)
        q = np.arange(lo, hi) + 0.5
        w = np.ones(span, np.float32)
        if i > 0: w *= np.clip((q - (pa - op)) / (2 * op), 0, 1)
        if i < n - 1: w *= np.clip(((pb + op) - q) / (2 * op), 0, 1)
        if vertical: acc[lo:hi] += im * w[:, None, None]
        else: acc[:, lo:hi] += im * w[None, :, None]
        wsum[lo:hi] += w
        os.remove(path)
        print(name, 'segment', i + 1, 'of', n, flush=True)
    for o in studio: o.location = home[o.name]
    ws = np.maximum(wsum, 1e-6)
    out = acc / (ws[:, None, None] if vertical else ws[None, :, None])
    al = out[..., 3:4]
    rgb = np.where(al > 1e-6, out[..., :3] / np.maximum(al, 1e-6), 0)
    img = np.concatenate([rgb, al], -1)
    Image.fromarray(np.clip(img * 255 + 0.5, 0, 255).astype(np.uint8), 'RGBA').save(os.path.join(OUT, name + '.png'))
    return out.shape[1], out.shape[0]


def _board_spec(rng, L, pr, Kw, **kw):
    """shelf_wear.wood_spec: a board's look with this rng's own draws (x0 = 0: each board built at its own origin)."""
    t = rng.uniform(0.9, 1.08)
    sp = dict(L=L, x0=0.0, prof=pr, K=Kw, seed=int(rng.integers(1, 1 << 30)), bend=rng.uniform(0.5, 1.5),
              ring=rng.uniform(0.38, 0.62), late=rng.uniform(0.22, 0.34), raised=rng.uniform(0.02, 0.035),
              age=rng.uniform(1.35, 1.75) * WOOD_AGE, tone=(t, t * rng.uniform(0.96, 1.02), t * rng.uniform(0.9, 1.0)),
              grime=rng.uniform(0.4, 0.7), dents=rng.uniform(18, 34), gouges=rng.uniform(5, 11), scratches=rng.uniform(40, 80))
    sp.update(kw)
    return sp


def _knots(rng, n, x_lo, x_hi, a_lo, a_hi, b, r=(0.35, 0.8), across=True):
    out = []
    for _ in range(n):
        dead = 1 if rng.random() < 0.45 else 0
        k = (float(rng.uniform(x_lo, x_hi)), float(rng.uniform(a_lo, a_hi)), b, float(rng.uniform(*r)), dead,
             int(rng.integers(1, 4)) if dead or rng.random() < 0.4 else 0)
        out.append(k + ((float(rng.uniform(70, 110)),) if across else ()))
    return out


def _vds(hi=0.2, lo=0.2, front=0.06, arris=0.035):
    return {0: hi, 1: arris, 2: front, 3: arris, 4: lo, 5: 0.6}


def piece_plank_shop():
    """The shelf: old pine boards butted end to end, each its own colour, grain and knots, seen from 10 degrees above
    (the top face foreshortened, the front edge whole): the top arris chewed dark where hands go, chips on the bottom
    one, screws and empty holes along the front, dents, gouges, an oil soak, a soldering iron's burn, a cup ring."""
    import shop_wood as SWD
    set_seed('plank')
    rng = np.random.default_rng(seed_of('irc-plank-boards'))
    t, d = PL['thick'], PL['depth']
    Lt = LONG['plank']; A0 = -Lt / 2; A1 = Lt / 2
    s, cam = TK.scene(20, 10, 0.5)
    wall(0.0)
    Kw = max(8.0, 2.0 * PXCM)                     # map px a cm: two a picture px
    f = 1.0 / Kw
    # the top seen at 10 degrees: its 12 cm take about 2 cm of the picture (spacing over sin 10), the front whole, the
    # underside unseen (coarse)
    below = ELEV < 0                              # (11-10) from below: the underside foreshortened, the top unseen
    sv = max(0.12, abs(math.sin(E)))
    pr = SWD.profile(-t, 0.0, 0.0, d, 0.32, 0.18, dict(hi=0.5 if below else f / 0.2, front=f, lo=f / sv if below else 0.5,
                                                       back=0.6, arris=f * 0.8))
    lens = []
    while sum(lens) < Lt + 20:
        lens.append(float(rng.uniform(70, 125)))
    x = A0 - 10.0
    hands = [(-150.0, -90.0, 0.9), (-30.0, 40.0, 0.6), (80.0, 150.0, 0.8)]
    for i, L in enumerate(lens):
        r = np.random.default_rng(seed_of('irc-plank-board-%d' % i))
        holes = [(float(u), float(r.uniform(-1.9, -0.8))) for u in r.uniform(3, L - 3, int(L / 45) + 1)]
        scr = [float(u) for u in r.uniform(3, L - 3, int(L / 70) + 1)]
        stains = [(float(r.uniform(5, L - 5)), float(r.uniform(-2.0, -0.6)), float(r.uniform(1.2, 2.8)), 'oil', float(r.uniform(0.25, 0.45)))]
        if i == 1: stains.append((float(r.uniform(10, L - 10)), -0.5, 0.35, 'burn', 0.95))
        if i == 2: stains.append((float(r.uniform(10, L - 10)), -1.4, 1.5, 'ring', 0.3))
        hb = [(h0 - x, h1 - x, k) for (h0, h1, k) in hands if h1 > x and h0 < x + L]
        spec = _board_spec(r, L, pr, Kw, pith=(float(r.uniform(-24, -16)), float(r.uniform(6, 12))), bend=float(r.uniform(0.4, 1.0)),
                           saw='chatter', saw_amp=0.002, feed=0.22,
                           knots=_knots(r, int(L / 40) + 1, 2, L - 2, -2.0, -0.6, d, r=(0.22, 0.5)),
                           hands=hb, chew_hi=0.85, chew_lo=0.3, holes=holes, stains=stains, wear_faces=(1, 2, 3, 4),
                           seats=[(u, -1.3, 0.55) for u in scr])
        M = SWD.board(spec)
        X0 = x + 0.05
        SWD.build('plank%d' % i, M, _vds(hi=0.25, lo=0.6), 0.1, lambda xx, a, b, X0=X0: (xx + X0, a, b))
        for j, u in enumerate(scr):
            SWD.drywall_screw(u + X0, -1.3, d, 0, 0, 1, r=0.4, finish='zinc' if i == 1 else 'black',
                              proud=float(r.uniform(-0.04, 0.06)), turn=float(r.uniform(0, math.pi)), name='scr%d-%d' % (i, j))
        print('plank board', i, '%.0f cm' % L, M['rows'], 'x', M['cols'], 'map px', flush=True)
        del M
        x += L
        if x > A1 + 10: break
    if below:
        # (11-10 proof) the underside came out as bright as the front: the studio's low fill from the right and the floor
        # below light it squarely. Under a real shelf lit from above it is the darkest face (the bench's frame studio:
        # "its underside stays dark"); so for the shelf seen from below the fill is turned down and the floor left out.
        for o in s.objects:
            if o.type == 'LIGHT' and o.name.startswith('fill'): o.data.energy *= UNDER_FILL
            if o.type == 'MESH' and o.name.split('.')[0] == 'Plane' and abs(o.rotation_euler.x) > 1.0: o.hide_render = True   # the floor, not the wall
    if below: v_top = v_of(0, d) + 1.4; v_bot = v_of(-t, 0) - 12.5    # front top edge to the underside's back and its shadow
    else: v_top = 1.4; v_bot = v_of(-t, d) - 12.5
    W, H = render_long(s, cam, 'plank', False, A0, A1, v_bot, v_top)
    # (frame() anchors each segment at its top edge: row r is v_top - (r + 0.5) / PXCM)
    LAY['out']['plank'] = {'size': [W, H], 'kind': 'long', 'x': [A0, A1], 'v_top': v_top, 'v_bot': v_bot,
                           'row_back': (v_top - v_of(0, 0 if not below else d)) * PXCM, 'row_front_top': (v_top - v_of(0, d)) * PXCM,
                           'row_front_bot': (v_top - v_of(-t, d)) * PXCM, 'boards_cm': [round(v, 2) for v in lens]}
    if below: LAY['out']['plank']['row_under_back'] = (v_top - v_of(-t, 0)) * PXCM     # where the underside meets the wall


def piece_trim_shop(which):
    """A moulding round the opening: a rough 1x2 strip nailed up (planed, with chatter; the bottom one rough-sawn as
    the bench's), its arrises eased and chipped, nail holes, a screw, knots, dents. 1.6 cm face, 0.65 cm proud of the
    wall, as before."""
    import shop_wood as SWD
    vertical = which == 'v'
    set_seed('trim-' + which)
    rng = np.random.default_rng(seed_of('irc-trim-' + which))
    w, zt = TRIM['w'], TRIM['proud']
    L = LONG['trim_v' if vertical else 'trim_h']; A0, A1 = -L / 2, L / 2
    s, cam = TK.scene(20, 10, 0.5)
    wall(0.0)
    Kw = max(8.0, 2.0 * PXCM); f = 1.0 / Kw
    pr = SWD.profile(-w / 2, w / 2, 0.0, zt, 0.14, 0.14, dict(hi=f / 0.5, front=f, lo=f / 0.5, back=0.4, arris=f * 0.8))
    holes = [(float(u), float(rng.uniform(-w / 4, w / 4))) for u in rng.uniform(2, L - 2, int(L / 30) + 1)]
    rough = which == 'h' and os.environ.get('IRC_TRIM_ROUGH', '0') == '1'
    spec = _board_spec(rng, L, pr, Kw, pith=(float(rng.uniform(-6, 6)), float(rng.choice([-5.0, 6.5]))),
                       saw='rough' if rough else 'chatter', saw_amp=0.012 if rough else 0.002, feed=0.45 if rough else 0.22,
                       knots=_knots(rng, int(L / 35) + 1, 3, L - 3, -w / 3, w / 3, zt, r=(0.3, 0.6)),
                       hands=[(0, L, 0.25)], chew_hi=0.35, chew_lo=0.35, holes=holes, wear_faces=(0, 1, 2, 3, 4),
                       stains=[(float(rng.uniform(L / 6, 5 * L / 6)), 0.0, float(rng.uniform(1.0, 2.0)), 'oil', 0.3)])
    M = SWD.board(spec)
    # the section's a runs across the face (x for the vertical strip, y for the horizontal), b out from the wall (z)
    fr = (lambda xx, a, b: (a, A1 - xx, b)) if vertical else (lambda xx, a, b: (xx + A0, a, b))
    SWD.build('trim', M, _vds(hi=0.1, lo=0.1), 0.1, fr)
    for k in range(int(L / 90) + 1):
        u = float(rng.uniform(4, L - 4))
        p = (0.0, A1 - u, zt) if vertical else (u + A0, 0.0, zt)
        SWD.drywall_screw(p[0], p[1], p[2], 0, 0, 1, r=0.32, finish='zinc', proud=0.02 + float(rng.uniform(-0.02, 0.03)),
                          turn=float(rng.uniform(0, math.pi)), name='tscr%d' % k)
    del M
    hw = w / 2
    if vertical:
        W, H = render_long(s, cam, 'trim-v', True, v_of(A0, 0.0), v_of(A1, 0.0), -hw - 0.9, hw + 1.7)
        LAY['out']['trim-v'] = {'size': [W, H], 'kind': 'long', 'y': [A0, A1], 'x_left': -hw - 0.9,
                                'px_left': 0.9 * PXCM, 'px_right': (0.9 + w) * PXCM}
    else:
        vt = v_of(hw, 0.0) + 0.9; vb = v_of(-hw, 0.0) - 1.7
        W, H = render_long(s, cam, 'trim-h', False, A0, A1, vb, vt)
        LAY['out']['trim-h'] = {'size': [W, H], 'kind': 'long', 'x': [A0, A1], 'v_top': vt,
                                'row_top': (vt - v_of(hw, 0.0)) * PXCM, 'row_bot': (vt - v_of(-hw, 0.0)) * PXCM,
                                'row_crown': (vt - v_of(0.0, zt)) * PXCM}


def main():
    todo = (['panel-fine', 'panel-nam', 'plank', 'box-bronze', 'box-oxblood', 'trim-h', 'trim-v'] if WHAT == 'all'
            else WHAT.split(','))
    for pc in todo:
        t = time.time()
        use_elev(SHELF_ELEV if pc in SHELF_PIECES else TK.ELEV)
        if pc.startswith('box-'): piece_box(pc)
        elif pc == 'plank' and WOOD == 'shop': piece_plank_shop()
        elif pc.startswith('trim-') and WOOD == 'shop': piece_trim_shop(pc[5:])
        elif pc.startswith('trim-'): piece_trim(pc[5:])
        elif pc.startswith('panel-'): panel_piece(pc, 'nam' if pc.startswith('panel-nam') else 'fine')
        elif pc.startswith('key-'):
            v = pc[4:]; piece_key(v)
            json.dump({'pxcm': PXCM, 'samples': SAMPLES, 'out': {k: x for k, x in TK.LAY['out'].items() if k.endswith('-' + v)}},
                      open(os.path.join(OUT, 'toolkit-keys-%s.json' % v), 'w'), indent=1)
            print('piece', pc, '%.1fs' % (time.time() - t), flush=True); continue
        else: globals()['piece_' + pc.replace('-', '_')]()
        print('piece', pc, '%.1fs' % (time.time() - t), flush=True)
        path = os.path.join(OUT, 'irc-render-%s.json' % pc)
        json.dump({'pxcm': PXCM, 'elev': ELEV, 'samples': SAMPLES, 'out': {pc: LAY['out'][pc]}}, open(path, 'w'), indent=1)


if __name__ == '__main__':
    main()
