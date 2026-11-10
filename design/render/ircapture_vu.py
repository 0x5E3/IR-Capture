# ircapture_vu.py: IR Capture's own VU meter, in the Tools studio like every IR Capture piece (2026-11-10).
#
# Lowell, 11-03: the level meters "classic analogue VU meters ... beautiful and warm". Until now the app drew the rack's
# level unit (the bench's 11-03 kit: rack-vu.webp, the warm frame light, its face cropped at 1.76 px a point where the
# app draws it 174 pt wide, so soft on a Retina screen) with the needle drawn in code. Here one meter is built and lit as
# the keys and panels are (toolkit.scene(): orthographic, 10 degrees above, key light up left; ircapture_kit's 11-10
# studio: the 1.0 px filter, the workshop room in the reflections):
#
#   bezel   black phenolic, a rounded rectangle 10.8 x 7.6 cm, the window 9.4 x 5.9 cm, its edges eased and handled
#   face    a printed cream card: the scale by voltage (-20 to +3 VU over 94 degrees), the red zone past 0, the
#           percentage scale under it, VU; aged a little at the edges; lit from behind and below by its lamp (a warm
#           filament glow, strongest low in the middle) or unlit
#   glass   flat (no dome), chamfered, near-glossy; the studio's cards light-linked away from it so it never washes the
#           card out (handoff 1.4); it still mirrors the dim room
#   needle  a thin black blade on a pivot hidden under the window's lower edge, rendered alone, upright: the app turns it
#
# Pictures (renders): vu-lit.png, vu-unlit.png (the meter without its needle, over its shadow on the panel), vu-needle.png
# (the needle alone), vu-render.json (boxes, pivot, the angle table). ircapture_vu_post.py makes irc-vu-*.webp and
# irc-vu.json for the app (Gear.swift VUMeter, VUKit).
#
#   FONTS_DIR=Resources/SwellKit/fonts ~/bvenv/bin/python design/render/ircapture_vu.py <out> [px/cm] [samples]
#   App scale: the bezel drawn 174 pt wide: 16.1 pt a cm. Render at 80 px/cm (about 5 px a point) for the @2x file.
import sys, os, math, json, time
_argv = sys.argv[:]
OUT = _argv[1] if len(_argv) > 1 else '/tmp/ircvu'
PXCM = float(_argv[2]) if len(_argv) > 2 else 30.0
SAMPLES = int(_argv[3]) if len(_argv) > 3 else 16
sys.argv = [_argv[0], OUT, 'vu', str(PXCM), str(SAMPLES)]
import ircapture_kit as K                     # the bench's scripts on the path, toolkit's globals, the 11-10 studio
sys.argv = _argv
import bpy
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import toolkit as TK
import shelf_gear as SG
import parts as P
from parts import mat, srgb
from gear_kit import rbox, cut, chamfer, render_crop, node, mix_into, noise, mul, add_bump, surface_wear, obj_coords
from instrument import grimy
TK.OUT, TK.PXCM, TK.SAMPLES = OUT, PXCM, SAMPLES
K.OUT, K.PXCM, K.SAMPLES = OUT, PXCM, SAMPLES
os.makedirs(OUT, exist_ok=True)
FONTS = os.environ.get('FONTS_DIR') or next((d for d in (os.path.expanduser('~/fonts'),
                                                         os.path.join(K.HERE, '..', '..', 'Resources', 'SwellKit', 'fonts'))
                                               if os.path.exists(os.path.join(d, 'Barlow-700-normal.ttf'))), '')

# measures (cm); the panel the meter is screwed to at z = 0, the bezel standing 0.9 in front of it
BZ = dict(w=10.8, h=7.6, d=0.9, r=0.55, roll=0.14)
WIN = dict(w=9.4, h=5.9, r=0.28, y=0.25)               # the window, its centre 0.25 above the bezel's
Z_FACE, Z_NEEDLE, Z_GLASS = 0.25, 0.48, 0.74            # the card, the needle's plane, the glass (front face)
PIVOT_Y = WIN['y'] - WIN['h'] / 2 - 0.7                 # hidden under the window's lower edge
R_ARC = 4.95                                            # the scale's arc about the pivot
NEEDLE_L = R_ARC + 0.32
VU_DB = [-20, -10, -7, -5, -3, -2, -1, 0, 1, 2, 3]


def vu_angle(db):
    """Degrees from up: -20 VU at -47, +3 at +47, by voltage (as a real VU's scale; the bench's rack.vu_angle)."""
    v = 10 ** (db / 20); v0, v1 = 10 ** (-20 / 20), 10 ** (3 / 20)
    return -47 + 94 * (v - v0) / (v1 - v0)


def face_png(path, w, h, px=150):
    """The printed card, w x h cm (larger than the window), origin its centre; the pivot at (0, PIVOT_Y - y_card)."""
    W, H = int(w * px), int(h * px)
    paper = np.array([232, 199, 132], np.float32)      # (a warm ivory-yellow card, as the classic meters')
    rng = np.random.default_rng(11)
    im = Image.new('RGB', (W, H), tuple(int(c) for c in paper)); d = ImageDraw.Draw(im)
    cy_card = WIN['y']                                   # the card's centre (world y)
    pvx, pvy = W / 2, H / 2 - (PIVOT_Y - cy_card) * px   # the pivot in the card's px (y down)

    def at(a, r):
        t = math.radians(a); return (pvx + r * px * math.sin(t), pvy - r * px * math.cos(t))

    def arc(a0, a1, r, width, fill, n=400):
        pts = [at(a0 + (a1 - a0) * i / n, r) for i in range(n + 1)]
        d.line(pts, fill=fill, width=max(1, int(width * px)), joint='curve')

    f = lambda name, cm: ImageFont.truetype(os.path.join(FONTS, name), max(8, int(cm * px)))
    fnum = f('BarlowSemiCondensed-600-normal.ttf', 0.5)
    fsm = f('BarlowSemiCondensed-400-normal.ttf', 0.3)
    fvu = f('Barlow-700-normal.ttf', 0.95)
    fsign = f('BarlowSemiCondensed-600-normal.ttf', 0.62)
    ink = (22, 19, 15); red = (178, 38, 28); grey = (84, 76, 64)
    a0, az, a1 = vu_angle(-20), vu_angle(0), vu_angle(3)
    arc(a0, az, R_ARC, 0.035, ink)
    arc(az, a1, R_ARC + 0.09, 0.2, red)                  # the red band past 0, outside the line
    arc(az, a1, R_ARC, 0.035, red)
    for db in VU_DB:
        a = vu_angle(db); major = db in (-20, -10, -7, -5, -3, -2, -1, 0, 1, 2, 3)
        col = red if db > 0 else ink
        L = 0.42 if db in (-20, -10, -5, 0, 3) else 0.3
        d.line([at(a, R_ARC), at(a, R_ARC + L)], fill=col, width=max(1, int(0.035 * px)))
        txt = str(abs(db))
        d.text(at(a, R_ARC + 0.78), txt, font=fnum, fill=col, anchor='mm')
    for db in (-15, -8.5, -6, -4, -2.5, -1.5, -0.5, 0.5, 1.5, 2.5):       # minor ticks
        a = vu_angle(db)
        d.line([at(a, R_ARC), at(a, R_ARC + 0.18)], fill=red if db > 0 else ink, width=max(1, int(0.028 * px)))
    d.text(at(a0 + 2.0, R_ARC - 0.4), '−', font=fsign, fill=ink, anchor='mm')
    d.text(at(a1 - 2.0, R_ARC - 0.4), '+', font=fsign, fill=red, anchor='mm')
    # the percentage scale under the arc (100 % at 0 VU)
    arc(vu_angle(-14), az, R_ARC - 0.55, 0.02, grey)
    for pc, db in ((20, -13.98), (40, -7.96), (60, -4.44), (80, -1.94), (100, 0.0)):
        a = vu_angle(db)
        d.line([at(a, R_ARC - 0.55), at(a, R_ARC - 0.7)], fill=grey, width=max(1, int(0.022 * px)))
        d.text(at(a, R_ARC - 0.98), str(pc), font=fsm, fill=grey, anchor='mm')
    d.text((W / 2, pvy - 2.15 * px), 'VU', font=fvu, fill=ink, anchor='mm')
    # the paper: a fine tooth, the print's ink a touch uneven, aged toward the edges (warmer, darker), handled corners
    a = np.asarray(im, np.float32)
    tooth = np.asarray(Image.fromarray((rng.random((H, W)) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8)), np.float32) / 255
    a *= (0.985 + 0.03 * tooth)[..., None]
    yy, xx = np.mgrid[0:H, 0:W]
    e = np.maximum(np.abs(xx - W / 2) / (W / 2), np.abs(yy - H / 2) / (H / 2))
    age = np.clip((e - 0.72) / 0.28, 0, 1) ** 1.6
    a = a * (1 - 0.1 * age[..., None]) * np.array([1.0, 0.985, 0.94])[None, None, :] ** age[..., None]
    Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)).save(path)
    return W, H


def card_material(path, w, h, lit):
    """The card's print on a matte paper; lit, the lamp behind and below shines through it, warm, strongest low in the
    middle and falling off toward the top corners."""
    m = mat('vucard', (1, 1, 1), rough=0.62, spec=0.25)
    nt = m.node_tree; b = nt.nodes['Principled BSDF']
    tc = nt.nodes.new('ShaderNodeTexCoord')
    ti = nt.nodes.new('ShaderNodeTexImage'); ti.image = bpy.data.images.load(path); ti.extension = 'EXTEND'
    nt.links.new(tc.outputs['UV'], ti.inputs['Vector'])
    nt.links.new(ti.outputs['Color'], b.inputs['Base Color'])
    if lit:
        sep = node(nt, 'ShaderNodeSeparateXYZ'); nt.links.new(tc.outputs['UV'], sep.inputs[0])
        # distance from the lamps (low in the middle, under the window's edge) in the card's own units
        dx = node(nt, 'ShaderNodeMath', operation='SUBTRACT'); nt.links.new(sep.outputs['X'], dx.inputs[0]); dx.inputs[1].default_value = 0.5
        dy = node(nt, 'ShaderNodeMath', operation='SUBTRACT'); nt.links.new(sep.outputs['Y'], dy.inputs[0]); dy.inputs[1].default_value = -0.08
        cx = node(nt, 'ShaderNodeCombineXYZ'); nt.links.new(dx.outputs[0], cx.inputs['X']); nt.links.new(dy.outputs[0], cx.inputs['Y'])
        sc = node(nt, 'ShaderNodeVectorMath', operation='MULTIPLY'); sc.inputs[1].default_value = (1.0, 1.25, 0.0)
        nt.links.new(cx.outputs[0], sc.inputs[0])
        ln = node(nt, 'ShaderNodeVectorMath', operation='LENGTH'); nt.links.new(sc.outputs[0], ln.inputs[0])
        fall = node(nt, 'ShaderNodeMapRange', **{'From Min': 0.1, 'From Max': 1.05, 'To Min': 1.0, 'To Max': 0.22})
        fall.interpolation_type = 'SMOOTHSTEP'; nt.links.new(ln.outputs['Value'], fall.inputs['Value'])
        warm = node(nt, 'ShaderNodeMix', data_type='RGBA'); warm.blend_type = 'MULTIPLY'; warm.inputs[0].default_value = 1.0
        nt.links.new(ti.outputs['Color'], warm.inputs[6]); warm.inputs[7].default_value = (*srgb('#ffa646'), 1)
        nt.links.new(warm.outputs[2], b.inputs['Emission Color'])
        st = node(nt, 'ShaderNodeMath', operation='MULTIPLY'); st.inputs[1].default_value = float(os.environ.get('VU_LAMP', '1.0'))
        nt.links.new(fall.outputs['Result'], st.inputs[0]); nt.links.new(st.outputs[0], b.inputs['Emission Strength'])
    return m


def phenolic(name='vubezel'):
    """(11-10, Lowell: the bezel "a little too clean and smooth digital") Black phenolic on finish_maps' true-scale
    maps: the moulded skin's fine peel, hairline scratches from years of handling, small chips at the corners and
    edges showing the brown filler under the skin, dust and grime in the window's corners. VU_BEZEL=plain: the first
    version below."""
    if os.environ.get('VU_BEZEL') != 'plain':
        import finish_maps as FM
        m = FM.material(name, os.environ.get('VU_BEZEL_KIND', 'powder'), '#0d0c0b', float(os.environ.get('VU_BEZEL_WEAR', '0.45')), 4211, 'irc-vu-bezel',
                        bare='#3b2c22', dirt='#1e1b17', dirt_k=0.35, coat_rough=0.5)
        K.calm_up(m, 0.6)
        return m
    m = mat(name, srgb('#121110'), rough=0.38, coat=0.25, coat_rough=0.25, spec=0.4)
    nt = m.node_tree; co = obj_coords(nt)
    add_bump(m, noise(nt, co, 60.0, 3.0, 0.6), 0.05, 0.002)
    mix_into(m, 'Roughness', mul(nt, noise(nt, co, 1.2, 3.0, 0.6, lo=0.4, hi=0.7), 0.5), 0.5, 'FLOAT')
    surface_wear(m, dust=0.3, smudge=0.45, scuff=0.3)
    K.calm_up(m, 0.6)                    # its top face, seen at a grazing 80 degrees, mirrors less of the studio
    return grimy(m, dirt='#2a2620', amount=0.35, dist=0.12)


def glass_mat():
    m = mat('vuglass', (1, 1, 1), rough=0.02, spec=0.5)
    b = m.node_tree.nodes['Principled BSDF']
    try:
        b.inputs['Transmission Weight'].default_value = 1.0; b.inputs['IOR'].default_value = 1.5
    except Exception: pass
    return m


def unlink_cards_from(objs, coll='vu_glass_rx'):
    """The studio's softboxes (key, top, rim, ceil, side: seen in reflections only) kept out of these objects' light:
    a flat pane mirrors one of them whole and washes the card out behind it (handoff 1.4, the bench's scope LCD)."""
    ex = bpy.data.collections.get(coll) or bpy.data.collections.new(coll)
    for o in objs:
        if o.name not in ex.objects: ex.objects.link(o)
    for c in ex.collection_objects: c.light_linking.link_state = 'EXCLUDE'
    for o in K.studio_objects(bpy.context.scene):
        if o.type == 'MESH': o.light_linking.receiver_collection = ex


def show(objs_on, objs_off):
    for o in objs_on: o.hide_render = False
    for o in objs_off: o.hide_render = True


def main():
    t0 = time.time()
    K.set_seed('vu-meter')
    s, cam = TK.scene(BZ['w'], BZ['h'], 1.1)
    cat = TK.catcher(0.0)
    # the bezel: a moulded frame round the window
    bz = rbox('vubezel', BZ['w'], BZ['h'], BZ['d'], 0.0, BZ['r'], roll=BZ['roll'])
    hole = rbox('vuhole', WIN['w'], WIN['h'], 4.0, -2.0, WIN['r']); hole.location.y = WIN['y']
    cut(bz, hole); chamfer(bz, 0.02, 2); TK.flat_faces(bz)
    bz.data.materials.append(phenolic())
    # the meter's case inside the window (its walls and floor, dark), under the card's edges
    # (its top 0.03 under the card: two faces in one plane shade each other black)
    well = rbox('vuwell', WIN['w'] + 0.3, WIN['h'] + 0.3, 0.3, Z_FACE - 0.33, 0.2); well.location.y = WIN['y']
    well.data.materials.append(mat('vuwell', srgb('#0e0d0c'), rough=0.7))
    # the card: a little larger than the window, its print made at 150 px a cm
    cw, ch = WIN['w'] + 0.2, WIN['h'] + 0.2
    fp = os.path.join(OUT, 'vu-face-print.png'); face_png(fp, cw, ch)
    bpy.ops.mesh.primitive_plane_add(size=1, location=(0, WIN['y'], Z_FACE)); card = bpy.context.active_object
    card.name = 'vucard'; card.scale = (cw, ch, 1)
    bpy.ops.object.transform_apply(scale=True)
    m_unlit = card_material(fp, cw, ch, False); m_lit = card_material(fp, cw, ch, True)
    card.data.materials.append(m_unlit)
    # the glass: flat, chamfered, seated in the bezel's window
    gl = rbox('vuglass', WIN['w'] + 0.12, WIN['h'] + 0.12, 0.14, Z_GLASS - 0.14, WIN['r']); gl.location.y = WIN['y']
    chamfer(gl, 0.012, 1); TK.flat_faces(gl); gl.data.materials.append(glass_mat())
    gl.visible_shadow = False            # (Cycles' glass shadows are black without caustics: a real pane passes the light)
    unlink_cards_from([gl])
    # the needle: a thin blade from the pivot, a short tail and its counterweight below (hidden by the bezel)
    nm = mat('vuneedle', srgb('#121110'), rough=0.42, spec=0.35)
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, PIVOT_Y + (NEEDLE_L - 0.4) / 2, Z_NEEDLE)); nd = bpy.context.active_object
    nd.name = 'vuneedle'; nd.scale = (0.03, NEEDLE_L + 0.4, 0.012); bpy.ops.object.transform_apply(scale=True)
    nd.data.materials.append(nm)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.22, depth=0.05, vertices=48, location=(0, PIVOT_Y, Z_NEEDLE)); hub = bpy.context.active_object
    hub.name = 'vuhub'; hub.data.materials.append(nm)
    needle = [nd, hub]
    meter = [bz, well, card, gl]

    lay = {'pxcm': PXCM, 'samples': SAMPLES, 'elev': TK.ELEV, 'size': [s.render.resolution_x, s.render.resolution_y]}
    pj = lambda p: TK.proj(s, cam, p)
    lay['bezel_tl'] = pj((-BZ['w'] / 2, BZ['h'] / 2, BZ['d'])); lay['bezel_br'] = pj((BZ['w'] / 2, -BZ['h'] / 2, BZ['d']))
    lay['window_tl'] = pj((-WIN['w'] / 2, WIN['y'] + WIN['h'] / 2, Z_FACE)); lay['window_br'] = pj((WIN['w'] / 2, WIN['y'] - WIN['h'] / 2, Z_FACE))
    lay['pivot'] = pj((0, PIVOT_Y, Z_NEEDLE))
    lay['needle_tip'] = pj((0, PIVOT_Y + NEEDLE_L, Z_NEEDLE))
    # the key's direction (up left, in front): the needle's shadow falls on the card down and right of it
    kl = next((o for o in s.objects if o.name.startswith('keyL')), None)
    if kl:
        v = np.array(kl.location) - np.array((0, 0, Z_FACE)); v /= np.linalg.norm(v)
        dz = Z_NEEDLE - Z_FACE
        sx, sy = -v[0] / v[2] * dz, -v[1] / v[2] * dz          # cm on the card
        p0 = pj((0, 0, Z_FACE)); p1 = pj((sx, sy, Z_FACE))
        lay['needle_shadow_px'] = [p1[0] - p0[0], p1[1] - p0[1]]
    lay['needle_shadow_soft_px'] = 0.05 * PXCM
    lay['angles'] = {str(db): round(vu_angle(db), 3) for db in VU_DB}
    lay['cm'] = {'bezel': [BZ['w'], BZ['h']], 'window': [WIN['w'], WIN['h'], WIN['y']], 'pivot_y': PIVOT_Y, 'needle': NEEDLE_L}

    # the meter, lamp lit and unlit, the needle hidden
    show(meter + [cat], needle)
    card.data.materials[0] = m_lit; P.render(s, os.path.join(OUT, 'vu-lit.png'))
    card.data.materials[0] = m_unlit; P.render(s, os.path.join(OUT, 'vu-unlit.png'))
    # the needle alone, upright, no catcher: cropped from the window's lower edge to past its tip
    show(needle, meter + [cat])
    x0, y0 = pj((-0.35, PIVOT_Y + NEEDLE_L + 0.15, Z_NEEDLE)); x1, y1 = pj((0.35, WIN['y'] - WIN['h'] / 2 - 0.1, Z_NEEDLE))
    box = [int(x0) // 4 * 4, int(y0) // 4 * 4, -(-int(x1) // 4) * 4, -(-int(y1) // 4) * 4]
    render_crop(s, box, os.path.join(OUT, 'vu-needle.png'))
    lay['needle_box'] = box
    json.dump(lay, open(os.path.join(OUT, 'vu-render.json'), 'w'), indent=1)
    print('vu done %.0fs' % (time.time() - t0), flush=True)


if __name__ == '__main__':
    main()
