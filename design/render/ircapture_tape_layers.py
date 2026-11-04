# ircapture_tape_layers.py: the tape machines split into the layers the app animates (Phase 7, 2026-11-04).
#
# Round 3b's decks (ircapture_tape.py) were single pictures. In the app the reels turn, the tape packs grow and
# shrink, the counter rolls, the cart's keys and lamps light and its timer counts. This script renders, in one scene
# per machine with the studio, camera and light of every IR Capture piece (toolkit.scene()):
#
#   reel   (Cab IR, the open-reel recorder)
#     deck              the whole machine without its reels and keys: case, warm brushed plate, turntables, head block,
#                       guides, capstan, pinch roller, tension arms, the tape from roller to roller, the counter with
#                       blank wheels, the legends. The keys are the app's own worn keys, laid where the deck had them;
#                       the REC jewel is the kit's red jewel.
#     reel-<s|t>-rear       the rear flange as a solid disc (no windows), lit where it stands
#     reel-<s|t>-rearshadow the rear flange's shadow on the plate, windows at angle 0 (the flange itself unseen)
#     reel-<s|t>-pack       a full pack of oxide tape (radius pack_full)
#     reel-<s|t>-front      the front flange as a solid disc, its rolled lip, the hub and the chrome boss
#     reel-<s|t>-frontshadow the front flange's (and prongs') shadow on the pack's face, windows at angle 0
#     reel-<s|t>-prong-<i>  the three hold-down prongs, 24 frames over 120 degrees (they repeat there)
#     wheel-<d>         the counter's first wheel showing d (opaque crop of the wheel's window), d = 0..9
#   Why layers this way: a turned aluminium flange under a fixed light keeps its highlights where they are while it
#   turns (the tool marks are rings round its centre), so the app turns only the windows, as a mask over the lit disc,
#   and the pack, a flat ring, as a circle mask over the full pack: smooth at any speed and a few MB, where rotation
#   sprites for four layers at @2x would take several hundred MB. Only the chrome prongs, whose highlights do move,
#   are real frames.
#
#   cart   (Amp NAM, the broadcast cart machine)
#     cart              the face with the cartridge in the slot (blank label: the app draws the signal map), every key
#                       out, every lamp and timer segment unlit
#     cart-key-<k>-<state>   CHECK / RECORD / STOP, off, lit, down, litdown (opaque crops)
#     cart-lamp-<n>     READY, CUE 1, CUE 2 lit (opaque crops)
#     cart-digit-<p>-<d>    the timer's digit p (0: minutes, 2, 3: seconds) showing d, lit (opaque crops); cart-colon
#
#   box    (the results: a capture's tape box)
#     box-reel          a 7 inch reel's kraft box, face on, a blank track sheet glued on (the app writes on it)
#     box-cart          a cart's kraft carton, the same, smaller
#
# Every crop's box (in the full frame's px) and the anchors the app needs (reel centres per plane, the ellipse factor,
# the shadows' centres, the rollers, the keys) go to tape-layers-<what>.json; ircapture_tape_post.py makes the pictures.
#
#   FONTS_DIR=Resources/SwellKit/fonts ~/bvenv/bin/python design/render/ircapture_tape_layers.py <out> reel|cart [px/cm] [samples]
#   App scale: the deck at 11.5 pt a cm, the cart at 16.9: 1x is 27.6 and 40.6 px a cm, @2x 55.2 and 81.1.
import sys, os, math, json, time
_argv = sys.argv[:]
OUT = _argv[1] if len(_argv) > 1 else '/tmp/irlayers'
WHAT = _argv[2] if len(_argv) > 2 else 'reel'
PXCM = float(_argv[3]) if len(_argv) > 3 else 27.6
SAMPLES = int(_argv[4]) if len(_argv) > 4 else 16
sys.argv = [_argv[0], OUT, 'reel', str(PXCM), str(SAMPLES), '0.5']
import ircapture_tape as T
sys.argv = _argv
import bpy
import numpy as np
import toolkit as TK
import shelf_gear as SG
from parts import mat, srgb, lathe, _rring
from gear_kit import rbox, cut, chamfer, render_crop, tek_jewel
from instrument import prism
import parts as P
TK.OUT, TK.PXCM, TK.SAMPLES = OUT, PXCM, SAMPLES
os.makedirs(OUT, exist_ok=True)
E = math.radians(TK.ELEV)
LAY = {'what': WHAT, 'pxcm': PXCM, 'samples': SAMPLES, 'elev': TK.ELEV, 'ellipse_y': math.cos(E), 'crops': {}, 'anchors': {}}
ONLY = set(filter(None, os.environ.get('ONLY', '').split(',')))     # render only these crop names (re-runs)


def want(name): return not ONLY or name in ONLY or any(name.startswith(o) for o in ONLY)


def objs_since(before): return [o for o in set(bpy.data.objects) - before if o.type in ('MESH', 'CURVE')]


def show_only(s, visible, shadow_only=(), catchers=()):
    """visible: rendered normally; shadow_only: cast shadows but unseen by the camera; catchers: the shadow catchers in
    use. Every other mesh is left out of the render."""
    vis = set(visible); sh = set(shadow_only); ca = set(catchers)
    for o in s.objects:
        if o.type not in ('MESH', 'CURVE'): continue
        on = o in vis or o in sh or o in ca
        o.hide_render = not on
        o.visible_camera = o not in sh


def box_of(s, cam, x0, y0, x1, y1, z0, z1, m=4):
    pts = [TK.proj(s, cam, (x, y, z)) for x in (x0, x1) for y in (y0, y1) for z in (z0, z1)]
    xs = [p[0] for p in pts]; ys = [p[1] for p in pts]
    W, H = s.render.resolution_x, s.render.resolution_y
    return [max(0, int(min(xs)) // m * m), max(0, int(min(ys)) // m * m), min(W, -(-int(max(xs)) // m) * m), min(H, -(-int(max(ys)) // m) * m)]


def crop(s, name, box):
    LAY['crops'][name] = box
    if want(name): render_crop(s, box, os.path.join(OUT, name + '.png'))


def full(s, name):
    W, H = s.render.resolution_x, s.render.resolution_y
    LAY['crops'][name] = [0, 0, W, H]
    if want(name): P.render(s, os.path.join(OUT, name + '.png'))


def pj(s, cam, p): return TK.proj(s, cam, p)


# ---------------------------------------------------------------------------------------------------------------------
# the open-reel recorder

R = T.REEL
ZT = R['z_reel']
ZF0, ZF1 = ZT, ZT + 0.11                      # rear flange
ZP0, ZP1 = ZF1 + 0.02, ZF1 + 0.02 + R['tape']  # the pack
ZG0, ZG1 = ZP1 + 0.02, ZP1 + 0.13              # front flange
WIN = dict(a0=14.0, span=92.0, r0=R['hub'] + 0.9, r1=R['R'] - 0.9)   # the windows (degrees from the reel's angle, cm)


def flange(name, z0, z1, windows, alu, ang=0.0):
    f = T.cyl(name, R['R'], z0, z1, 0, 0, 256)
    if windows:
        for k in range(3):
            a0 = ang + k * 2 * math.pi / 3 + math.radians(WIN['a0']); a1 = a0 + math.radians(WIN['span'])
            pts = []
            for i in range(41): t = a0 + (a1 - a0) * i / 40; pts.append((WIN['r1'] * math.cos(t), WIN['r1'] * math.sin(t)))
            for i in range(41): t = a1 - (a1 - a0) * i / 40; pts.append((WIN['r0'] * math.cos(t), WIN['r0'] * math.sin(t)))
            cut(f, T.outline_prism('win', pts, z0 - 1, z1 + 1))
    chamfer(f, 0.03, 2); f.data.materials.append(alu)
    f.location = (0, 0, (z0 + z1) / 2)
    lip = lathe(name + 'lip', [(R['R'] + 0.02, z0), (R['R'] + 0.06, (z0 + z1) / 2), (R['R'] + 0.02, z1), (R['R'] - 0.15, z1)], 256)
    lip.data.materials.append(alu)
    return [f, lip]


def prongs(chrome, ang=0.0):
    out = []
    for k in range(3):
        t = ang + k * 2 * math.pi / 3 + math.radians(60)
        p = rbox('prong', 0.5, 1.5, 0.22, ZG1 + 0.32, 0.2, roll=0.08)
        p.rotation_euler = (0, 0, t - math.pi / 2); p.location = (0.95 * math.cos(t), 0.95 * math.sin(t), 0)
        p.data.materials.append(chrome); out.append(p)
    return out


def reel_parts(x, y, alu, tape_m, chrome, black):
    """Every part of one reel, each group its own list, the reel's centre at (x, y)."""
    g = {}
    def grp(key, fn):
        b = set(bpy.data.objects); fn(); g[key] = objs_since(b)
    grp('turntable', lambda: T.cyl('turntable', 4.2, 0.25, ZT - 0.05, 0, 0, 128, black))
    grp('rear', lambda: flange('rear', ZF0, ZF1, False, alu))
    grp('rearwin', lambda: flange('rearw', ZF0, ZF1, True, alu))
    grp('front', lambda: flange('front', ZG0, ZG1, False, alu))
    grp('frontwin', lambda: flange('frontw', ZG0, ZG1, True, alu))
    def hubboss():
        T.cyl('hub', R['hub'], ZF0, ZG1 + 0.02, 0, 0, 128, alu)
        bo = lathe('boss', [(1.1, ZG1), (1.1, ZG1 + 0.35), (0.9, ZG1 + 0.55), (0.35, ZG1 + 0.62), (0.0, ZG1 + 0.64)], 96)
        bo.data.materials.append(chrome)
    grp('hub', hubboss)
    def pack():
        pk = lathe('pack', [(R['hub'], ZP0), (R['pack_full'], ZP0), (R['pack_full'], ZP1), (R['hub'], ZP1)], 256, smooth=False)
        pk.data.materials.append(tape_m)
    grp('pack', pack)
    # the prongs: under a pivot, so the frames turn them about the reel's axis
    b = set(bpy.data.objects); pr = prongs(chrome)
    pivot = bpy.data.objects.new('pivot', None); bpy.context.scene.collection.objects.link(pivot)
    for o in pr:
        mw = o.matrix_world.copy(); o.parent = pivot; o.matrix_world = mw
    g['prongs'] = pr; g['pivot'] = pivot
    for k, objs in g.items():
        if k == 'pivot': continue
        for o in objs:
            if o.parent is None: o.location.x += x; o.location.y += y
    pivot.location = (x, y, 0)
    return g


def job_reel():
    W_, H_ = R['w'], R['h']
    s, cam = TK.scene(W_, H_, 1.0)
    main_catch = TK.catcher(-R['case_d'])
    b0 = set(bpy.data.objects)
    case = rbox('case', W_, H_, R['case_d'], -R['case_d'], 1.0, roll=0.35)
    TK.flat_faces(case); case.data.materials.append(T.K.hammertone_fine(name='casehammer'))
    pw, ph = W_ - 2 * R['plate_inset'], H_ - 2 * R['plate_inset']
    plate = rbox('plate', pw, ph, 0.25, 0.0, 0.6, roll=0.08)
    TK.flat_faces(plate); plate.data.materials.append(T.brushed_alu())
    ni = TK.nickel(); ch = SG.chrome('chr', seed=3); blk = SG.black_cast('bc'); alu = T.reel_alu(); tp = T.oxide()
    for sx in (-1, 1):
        for sy in (-1, 1): T.screw_at(sx * (pw / 2 - 0.9), sy * (ph / 2 - 0.9), 0.25, ni)
    rx, ry = R['rx'], R['ry']
    full_r, hub = R['pack_full'], R['hub']
    rmid = math.sqrt(hub * hub + (full_r * full_r - hub * hub) * 0.5)
    ty = R['ty']
    base = rbox('hbase', 28.0, 5.6, 0.6, 0.25, 0.4, roll=0.12); base.location = (0, ty + 3.4, 0)
    chamfer(base, 0.02, 2); base.data.materials.append(T.K.hammertone_fine(base='#191612', hi='#2e271e', name='hbase'))
    hood = rbox('hood', 17.5, 2.4, 1.6, 0.85, 0.6, roll=0.35); hood.location = (-1.5, ty + 4.9, 0)
    chamfer(hood, 0.02, 2); hood.data.materials.append(blk)
    T.ink('ERASE        RECORD        PLAY', -1.5, ty + 4.9, 2.45, 0.32, w=15.0)
    mu = T.mu_metal()
    for hx in (-6.0, -1.5, 3.0):
        hd = rbox('head', 2.3, 2.4, 2.2, 0.85, 0.9, roll=0.2); hd.location = (hx, ty + 1.2, 0); hd.data.materials.append(mu)
        gap = rbox('gap', 0.05, 0.7, 0.02, 3.04, 0.0); gap.location = (hx, ty + 0.4, 0)
        gap.data.materials.append(mat('gapblk', srgb('#151210'), rough=0.5))
        sh = rbox('shield', 2.8, 0.35, 2.4, 0.85, 0.12, roll=0.05); sh.location = (hx, ty + 2.55, 0); sh.data.materials.append(ch)
        for sx in (-1, 1): T.screw_at(hx + sx * 1.6, ty + 3.2, 0.85, ni)
    for gx in (-10.5, 7.8):
        T.cyl('post', 0.55, 0.85, ZP1 + 0.25, gx, ty + 0.55, 64, ch)
        for z in (ZP0 - 0.06, ZP1 + 0.06): T.cyl('pfl', 0.8, z - 0.05, z + 0.05, gx, ty + 0.55, 64, ch)
    cx_ = 5.6
    T.cyl('capstan', 0.22, 0.85, ZP1 + 0.4, cx_, ty + 0.22, 48, mu)
    T.cyl('pinch', 1.05, 0.9, ZP1 + 0.25, cx_, ty - 1.07, 128, T.black_rubber())
    T.cyl('pinchcap', 0.4, ZP1 + 0.25, ZP1 + 0.4, cx_, ty - 1.07, 64, ch)
    rollers = []
    for sx in (-1, 1):
        ax, ay = sx * 13.0, ty + 5.0
        a = rbox('tarm', 0.7, 3.0, 0.3, 0.55, 0.3, roll=0.1); a.location = (ax + sx * 0.5, ay - 1.3, 0); a.rotation_euler = (0, 0, sx * -0.35)
        a.data.materials.append(blk)
        T.cyl('troll', 0.7, 0.85, ZP1 + 0.15, ax, ay, 64, ch)
        rollers.append((ax, ay, 0.7))
    # the tape from roller to roller (through the heads): the path for a half-full pack, less its first and last spans
    circles = [((-rx, ry), rmid, -1), ((-13.0, ty + 5.0), 0.7, +1), ((-10.5, ty + 0.55), 0.55, +1),
               ((-6.0, ty + 0.9), 0.9, +1), ((-1.5, ty + 0.9), 0.9, +1), ((3.0, ty + 0.9), 0.9, +1),
               ((cx_, ty + 0.22), 0.22, +1), ((7.8, ty + 0.55), 0.55, +1), ((13.0, ty + 5.0), 0.7, +1), ((rx, ry), rmid, -1)]
    path = T.tape_path(circles)
    T.ribbon('tape', path[1:-1], ZP0, ZP1, tp)
    # the counter: bezel and four blank wheels; the digits are their own crops
    cw, chh, CY = 6.2, 2.0, 6.4
    bz = rbox('cbez', cw + 0.6, chh + 0.6, 0.3, 0.25, 0.3, roll=0.1); bz.location = (0, CY, 0)
    cut(bz, prism('chole', [(x, y + CY, z) for x, y, z in _rring(cw / 2, chh / 2, 0.15, 0.0, 0, n_arc=8)], -2, 2))
    chamfer(bz, 0.02, 2); bz.data.materials.append(blk)
    wheel_m = mat('wheel', srgb('#141211'), rough=0.5, coat=0.2)
    WX = [-2.25 + i * 1.5 for i in range(4)]
    for dx in WX:
        wh = rbox('wheel', 1.25, 1.9, 0.3, -0.05, 0.05, roll=0.06); wh.location = (dx, CY, 0.0); wh.data.materials.append(wheel_m)
    D = '#221e19'
    T.ink('SECONDS LEFT', 0, CY - 1.65, 0.25, 0.34, color=D)
    T.ink('SUPPLY', -rx, -10.4, 0.25, 0.34, color=D); T.ink('TAKE-UP', rx, -10.4, 0.25, 0.34, color=D)
    T.ink('CAB IR RECORDER', 0, 10.0, 0.25, 0.5, track=0.3, color=D)
    T.ink('FULL TRACK  .  ONE CAPTURE, EVERY RATE', 0, 9.0, 0.25, 0.24, track=0.2, color=D, w=12.0)
    KEYS = [('check', -15.0, 6.2), ('capture', -6.6, 5.4), ('stop', 1.6, 3.8)]
    KY, KH = -10.4, 1.9
    JX = -2.6
    T.ink('REC', JX, KY + 1.3, 0.25, 0.26, color=D)
    deck_objs = objs_since(b0)
    # the reels
    b1 = set(bpy.data.objects)
    reels = {'s': reel_parts(-rx, ry, alu, tp, ch, blk), 't': reel_parts(rx, ry, alu, tp, ch, blk)}
    turntables = reels['s']['turntable'] + reels['t']['turntable']
    deck_objs = deck_objs + turntables
    # catchers for the reels' shadows: on the plate, and on the pack's face
    c_plate = TK.catcher(0.25); c_pack = TK.catcher(ZP1)
    t0 = time.time()

    # --- the deck
    show_only(s, deck_objs, catchers=[main_catch])
    full(s, 'deck')
    A = LAY['anchors']
    A['deck_cm'] = [W_, H_]
    A['deck_tl'] = pj(s, cam, (-W_ / 2, H_ / 2, 0.0)); A['deck_br'] = pj(s, cam, (W_ / 2, -H_ / 2, 0.0))
    A['plate_z'] = 0.25
    A['keys'] = {k: {'c': pj(s, cam, (kx, KY, 0.25)), 'w_cm': kw, 'h_cm': KH} for k, kx, kw in KEYS}
    A['jewel'] = {'c': pj(s, cam, (JX, KY, 0.25)), 'd_cm': 1.84}
    A['wheels'] = [{'tl': pj(s, cam, (dx - 0.6, CY + 0.92, 0.25)), 'br': pj(s, cam, (dx + 0.6, CY - 0.92, 0.25))} for dx in WX]
    A['rollers'] = [{'c': pj(s, cam, (x, y, (ZP0 + ZP1) / 2)), 'r_cm': r} for x, y, r in rollers]
    # where the plate's tape starts and ends (the app's free spans end there)
    A['tape_ends'] = [pj(s, cam, (path[1][0], path[1][1], (ZP0 + ZP1) / 2)), pj(s, cam, (path[-2][0], path[-2][1], (ZP0 + ZP1) / 2))]
    A['px_per_cm'] = PXCM

    # --- the reels
    for key, (x, y) in (('s', (-rx, ry)), ('t', (rx, ry))):
        g = reels[key]
        m = R['R'] + 1.6
        bx = box_of(s, cam, x - m, y - m, x + m, y + m, 0.25, ZG1 + 0.7)
        a = A.setdefault('reel_' + key, {})
        a['box'] = bx
        a['c_rear'] = pj(s, cam, (x, y, ZF1)); a['c_pack'] = pj(s, cam, (x, y, ZP1)); a['c_front'] = pj(s, cam, (x, y, ZG1))
        a['c_plate'] = pj(s, cam, (x, y, 0.25))
        a['r_cm'] = R['R']; a['hub_cm'] = R['hub']; a['pack_full_cm'] = R['pack_full']
        a['win'] = WIN; a['prong_frames'] = 24; a['prong_span_deg'] = 120
        show_only(s, g['rear'], catchers=[]); crop(s, 'reel-%s-rear' % key, bx)
        show_only(s, [], shadow_only=g['rearwin'], catchers=[c_plate]); crop(s, 'reel-%s-rearshadow' % key, bx)
        show_only(s, [], shadow_only=g['rear'], catchers=[c_plate]); crop(s, 'reel-%s-rearshadow-solid' % key, bx)
        show_only(s, g['pack'], catchers=[]); crop(s, 'reel-%s-pack' % key, bx)
        show_only(s, g['front'] + g['hub'], catchers=[]); crop(s, 'reel-%s-front' % key, bx)
        show_only(s, [], shadow_only=g['frontwin'] + g['hub'] + g['prongs'], catchers=[c_pack]); crop(s, 'reel-%s-frontshadow' % key, bx)
        show_only(s, [], shadow_only=g['front'] + g['hub'], catchers=[c_pack]); crop(s, 'reel-%s-frontshadow-solid' % key, bx)
        # the prongs, turning clockwise as seen from the front (both reels turn that way playing forward)
        pb = box_of(s, cam, x - 2.0, y - 2.0, x + 2.0, y + 2.0, ZG1, ZG1 + 0.8)
        a['prong_box'] = pb
        show_only(s, g['prongs'] + g['hub'], catchers=[])
        hubo = [o for o in g['hub'] if o.name.startswith('hub')]
        for o in hubo: o.visible_camera = False             # the hub only occludes; the boss shows (it is under them)
        for i in range(24):
            g['pivot'].rotation_euler = (0, 0, math.radians(-120.0 * i / 24))
            bpy.context.view_layer.update()
            crop(s, 'reel-%s-prong-%02d' % (key, i), pb)
        g['pivot'].rotation_euler = (0, 0, 0)
        print('reel', key, '%.0fs' % (time.time() - t0), flush=True)

    # --- the counter's digits: every wheel showing d, the first wheel's window cropped
    show_only(s, deck_objs, catchers=[main_catch])
    wheels = [o for o in deck_objs if o.name.startswith('wheel')]
    wb = box_of(s, cam, WX[0] - 0.62, CY - 0.97, WX[0] + 0.62, CY + 0.97, 0.25, 0.26, m=1)
    A['wheel_box'] = wb
    for d in range(10):
        b = set(bpy.data.objects)
        for dx in WX[:1]:
            T.ink(str(d), dx, CY, 0.26, 0.95, color='#ece6d6', kind='BarlowSemiCondensed-600-normal.ttf', track=0.0, w=1.2)
        new = objs_since(b)
        show_only(s, deck_objs + new, catchers=[main_catch])
        crop(s, 'wheel-%d' % d, wb)
        for o in new: bpy.data.objects.remove(o, do_unlink=True)
    print('reel job done %.0fs' % (time.time() - t0), flush=True)


# ---------------------------------------------------------------------------------------------------------------------
# the broadcast cart machine

C = T.CART


def job_cart():
    W_, H_, D, Ear = C['w'], C['h'], C['d'], C['ear']
    s, cam = TK.scene(W_, H_, 1.0)
    main_catch = TK.catcher(-D)
    blk = SG.black_cast('bc'); ni = TK.nickel()
    sx0, sy0, sw, sh = -10.4, 1.9, 16.2, 3.1
    b0 = set(bpy.data.objects)
    face = rbox('face', W_, H_, 0.5, -0.5, 0.25, roll=0.2)
    cut(face, prism('slot', [(x + sx0, y + sy0, z) for x, y, z in _rring(sw / 2, sh / 2, 0.25, 0.0, 0, n_arc=8)], -2, 2))
    for ex in (-1, 1):
        for ey in (-1, 1):
            cut(face, prism('rk', [(x + ex * (W_ / 2 - Ear / 2), y + ey * 4.75, z) for x, y, z in _rring(0.55, 0.33, 0.32, 0.0, 0, n_arc=8)], -2, 2))
    TK.flat_faces(face); face.data.materials.append(T.K.anodised('face'))
    body = rbox('body', W_ - 2 * Ear - 0.4, H_ - 0.6, D - 0.5, -D, 0.3); body.data.materials.append(mat('body', srgb('#141414'), rough=0.6))
    for ex in (-1, 1):
        for ey in (-1, 1): T.screw_at(ex * (W_ / 2 - Ear / 2), ey * 4.75, 0.0, ni)
    for ex in (-1, 1):
        g = rbox('seam', 0.035, H_ - 0.9, 0.02, -0.005, 0.0); g.location = (ex * (W_ / 2 - Ear), 0, 0)
        g.data.materials.append(mat('seam', srgb('#0e0e0f'), rough=0.6))
    throat = rbox('throat', sw - 0.1, sh - 0.1, 0.1, -2.6, 0.2); throat.location = (sx0, sy0, 0)
    throat.data.materials.append(mat('throat', srgb('#0d0c0b'), rough=0.85))
    Lt = bpy.data.lights.new('throat', 'AREA'); Lt.energy = 0.6; Lt.size = 12.0; Lt.color = srgb('#ffdcb0')
    gt = bpy.data.objects.new('throat', Lt); s.collection.objects.link(gt); gt.location = (sx0, sy0 + 1.0, -1.2); gt.rotation_euler = (math.radians(80), 0, 0)
    cw_, ch_ = 15.2, 2.45
    shell = rbox('cart', cw_, ch_, 4.0, -2.6, 0.18, roll=0.04); shell.location = (sx0, sy0 - 0.15, 0)
    from gear_kit import add_bump, noise, obj_coords, surface_wear
    from instrument import grimy
    shm = mat('cartshell', srgb('#2b2927'), rough=0.42, coat=0.25, coat_rough=0.25)
    add_bump(shm, noise(shm.node_tree, obj_coords(shm.node_tree), 90.0, 2.0, 0.5), 0.08, 0.001); surface_wear(shm, dust=0.4, smudge=0.5, scuff=0.5)
    shell.data.materials.append(grimy(shm, dirt='#3a3228', amount=0.35, dist=0.05))
    for gx in (-1, 1):
        for i in range(4):
            gr = rbox('grip', 0.06, ch_ - 0.7, 0.05, 1.4, 0.02); gr.location = (sx0 + gx * (cw_ / 2 - 0.45 - i * 0.16), sy0 - 0.15, 0)
            gr.data.materials.append(shm)
    lw, lh = 12.6, 1.9
    blank = np.ones((int(lh * 110), int(lw * 110), 3), np.float32) * (np.array([233, 224, 199], np.float32) / 255.0)
    T.img_plane('cartlabel', blank, lw, lh, sx0, sy0 - 0.15, 1.402)
    Dc = '#cfc9bd'
    T.ink('PLAY / RECORD', sx0 - sw / 2 + 1.6, sy0 + sh / 2 + 0.55, 0.0, 0.26, color=Dc)
    # the keys' legends and bezels stay on the face; the lenses are their own objects per state
    ky = -3.3; ks = 2.5
    KEYS = (('check', 'CHECK', -16.0, '#c88a30', '#ffa030'), ('record', 'RECORD', -10.4, '#5e0a05', '#ff1a08'),
            ('stop', 'STOP', -4.8, '#cfc8b8', '#fff0d0'))
    for k, txt, kx, base, glow in KEYS:
        bz = rbox('kbz', ks + 0.5, ks + 0.5, 0.22, 0.0, 0.2, roll=0.06); bz.location = (kx, ky, 0)
        cut(bz, prism('kh', [(x + kx, y + ky, z) for x, y, z in _rring(ks / 2 + 0.03, ks / 2 + 0.03, 0.15, 0.0, 0, n_arc=8)], -2, 2))
        chamfer(bz, 0.02, 2); bz.data.materials.append(SG.chrome('kch', seed=5))
        T.ink(txt, kx, ky - ks / 2 - 0.62, 0.0, 0.3, color=Dc)
    LAMPS = (('ready', 'READY', '#40e070'), ('cue1', 'CUE 1', '#ffb030'), ('cue2', 'CUE 2', '#ffb030'))
    for i, (k, txt, col) in enumerate(LAMPS):
        lx, ly = 1.2 + i * 2.5, 2.4
        T.cyl('ledbz', 0.36, 0.0, 0.12, lx, ly, 48, blk)
        T.ink(txt, lx, ly - 0.85, 0.0, 0.24, color=Dc)
    tx, tyy, tw, th = 3.7, -2.6, 7.4, 2.6
    win = rbox('twin', tw, th, 0.3, 0.0, 0.1, roll=0.04); win.location = (tx, tyy, 0)
    cut(win, prism('twh', [(x + tx, y + tyy, z) for x, y, z in _rring(tw / 2 - 0.3, th / 2 - 0.3, 0.1, 0.0, 0, n_arc=8)], -2, 2))
    win.data.materials.append(blk)
    back = rbox('tback', tw - 0.6, th - 0.6, 0.05, 0.0, 0.0); back.location = (tx, tyy, 0)
    back.data.materials.append(mat('tback', srgb('#120605'), rough=0.6))
    filt = rbox('tfilt', tw - 0.5, th - 0.5, 0.04, 0.16, 0.0); filt.location = (tx, tyy, 0)
    filt.data.materials.append(mat('tfilt', srgb('#e0a090'), rough=0.04, transm=1.0, ior=1.1, spec=0.35))
    T.ink('TIME LEFT', tx, tyy - th / 2 - 0.5, 0.0, 0.24, color=Dc)
    T.ink('AMP CAPTURE CART', 15.6, 0.9, 0.0, 0.48, track=0.3, color=Dc)
    T.ink('NAM  .  TRAINING SIGNAL v3', 15.6, -0.2, 0.0, 0.24, track=0.2, color='#a8a298')
    face_objs = objs_since(b0)
    # the variable parts
    on_m, off_m = T.led_mat('segon', '#ff3a18', True, 14.0), T.led_mat('segoff', '#ff3a18', False)
    hgt = 1.45
    XS = (tx - 2.0, None, tx + 1.15 - 0.4, tx + 2.45 - 0.4)

    def digit(p, ch, lit):
        b = set(bpy.data.objects); T.seven_seg(ch if lit else '', XS[p], tyy, 0.05, hgt, on_m, off_m); return objs_since(b)

    def colon(lit):
        b = set(bpy.data.objects)
        for dy in (0.32, -0.32): T.cyl('colon', 0.08, 0.05, 0.07, tx - 0.15 - 0.25, tyy + dy, 16, on_m if lit else off_m)
        return objs_since(b)

    def lens(k, kx, base, glow, lit, down):
        b = set(bpy.data.objects)
        cap = rbox('lens', ks, ks, 0.55, -0.1 - (0.09 if down else 0.0), 0.12, roll=0.08); TK.flat_faces(cap); cap.location = (kx, ky, 0)
        cap.data.materials.append(T.lens_mat('lens' + k + str(lit), base, glow, lit))
        if lit:
            L = bpy.data.lights.new('kg', 'POINT'); L.energy = 0.35; L.color = srgb(glow); L.shadow_soft_size = 0.8
            gl = bpy.data.objects.new('kg' + k, L); s.collection.objects.link(gl); gl.location = (kx, ky, 1.3)
        return objs_since(b)

    def led(i, col, on):
        b = set(bpy.data.objects); T.cyl('led', 0.24, 0.0, 0.2, 1.2 + i * 2.5, 2.4, 48, T.led_mat('led%d%s' % (i, on), col, on)); return objs_since(b)

    def drop(objs):
        for o in objs: bpy.data.objects.remove(o, do_unlink=True)
        for l in [o for o in bpy.data.objects if o.type == 'LIGHT' and o.name.startswith('kg')]: bpy.data.objects.remove(l, do_unlink=True)

    base_var = []
    for p in (0, 2, 3): base_var += digit(p, '', False)
    base_var += colon(False)
    keys_out = []
    for k, txt, kx, b_, g_ in KEYS: keys_out += lens(k, kx, b_, g_, False, False)
    leds_off = []
    for i, (k, txt, col) in enumerate(LAMPS): leds_off += led(i, col, False)
    t0 = time.time()
    show_only(s, face_objs + base_var + keys_out + leds_off, catchers=[main_catch])
    full(s, 'cart')
    A = LAY['anchors']
    A['cart_cm'] = [W_, H_]
    A['cart_tl'] = pj(s, cam, (-W_ / 2, H_ / 2, 0.0)); A['cart_br'] = pj(s, cam, (W_ / 2, -H_ / 2, 0.0))
    A['label'] = {'tl': pj(s, cam, (sx0 - lw / 2, sy0 - 0.15 + lh / 2, 1.402)), 'br': pj(s, cam, (sx0 + lw / 2, sy0 - 0.15 - lh / 2, 1.402))}
    A['px_per_cm'] = PXCM
    kb = {}
    for k, txt, kx, base, glow in KEYS:
        kb[k] = box_of(s, cam, kx - ks / 2 - 0.45, ky - ks / 2 - 0.45, kx + ks / 2 + 0.45, ky + ks / 2 + 0.45, 0.0, 0.5)
    A['keys'] = kb
    lb = {k: box_of(s, cam, 1.2 + i * 2.5 - 0.5, 2.4 - 0.5, 1.2 + i * 2.5 + 0.5, 2.4 + 0.5, 0.0, 0.25) for i, (k, _, _) in enumerate(LAMPS)}
    A['lamps'] = lb
    db = {p: box_of(s, cam, XS[p] - 0.62, tyy - 0.85, XS[p] + 0.62, tyy + 0.85, 0.0, 0.2) for p in (0, 2, 3)}
    cb = box_of(s, cam, tx - 0.4 - 0.2, tyy - 0.5, tx - 0.4 + 0.2, tyy + 0.5, 0.0, 0.2)
    A['digits'] = {str(p): v for p, v in db.items()}; A['colon'] = cb
    # keys in their states (opaque crops of the face round each key)
    for k, txt, kx, base, glow in KEYS:
        mine = [o for o in keys_out if abs(o.location.x - kx) < 0.01]
        others = [o for o in keys_out if o not in mine]
        for st in ('off', 'lit', 'down', 'litdown'):
            new = lens(k, kx, base, glow, st in ('lit', 'litdown'), st in ('down', 'litdown'))
            show_only(s, face_objs + base_var + others + new + leds_off, catchers=[main_catch])
            crop(s, 'cart-key-%s-%s' % (k, st), kb[k])
            drop(new)
    for i, (k, txt, col) in enumerate(LAMPS):
        new = led(i, col, True)
        rest = [o for o in leds_off if abs(o.location.x - (1.2 + i * 2.5)) > 0.01]
        show_only(s, face_objs + base_var + keys_out + rest + new, catchers=[main_catch])
        crop(s, 'cart-lamp-%s' % k, lb[k])
        drop(new)
    for p in (0, 2, 3):
        p_off = [o for o in base_var if abs(o.location.x - XS[p]) < 0.9 and o.name.startswith('seg')]
        rest = [o for o in base_var if o not in p_off]
        for d in range(10):
            new = digit(p, str(d), True)
            show_only(s, face_objs + rest + new + keys_out + leds_off, catchers=[main_catch])
            crop(s, 'cart-digit-%d-%d' % (p, d), db[p])
            drop(new)
    c_off = [o for o in base_var if o.name.startswith('colon')]
    new = colon(True)
    show_only(s, face_objs + [o for o in base_var if o not in c_off] + new + keys_out + leds_off, catchers=[main_catch])
    crop(s, 'cart-colon', cb)
    drop(new)
    print('cart job done %.0fs' % (time.time() - t0), flush=True)


# ---------------------------------------------------------------------------------------------------------------------
# the tape boxes (results)

def kraft(name, base='#a47a4c'):
    from gear_kit import add_bump, noise, obj_coords, surface_wear, mix_into, mul, edge_mask
    from instrument import grimy
    m = mat(name, srgb(base), rough=0.82, spec=0.3)
    nt = m.node_tree; co = obj_coords(nt)
    fib = noise(nt, co, 90.0, 4.0, 0.7, lo=0.3, hi=0.7)
    add_bump(m, fib, 0.25, 0.002)
    mix_into(m, 'Base Color', mul(nt, noise(nt, co, 2.0, 3.0, 0.6, lo=0.35, hi=0.7), 0.45), (*srgb('#8a6440'), 1))
    mix_into(m, 'Base Color', mul(nt, fib, 0.25), (*srgb('#b98f60'), 1))
    mix_into(m, 'Base Color', mul(nt, edge_mask(nt, 0.25, 5.0), 0.55), (*srgb('#c9a679'), 1))   # rubbed corners
    surface_wear(m, dust=0.3, smudge=0.45, scuff=0.5)
    return grimy(m, dirt='#4a3a28', amount=0.5, dist=0.15)


BOXES = {'reel': dict(w=18.6, h=18.6, d=2.2, label=(15.2, 11.4, 0.0, -2.3), tilt=-0.7,
                      band='CAB IR', sub='ONE CAPTURE  .  EVERY RATE'),
         'cart': dict(w=16.4, h=11.0, d=3.0, label=(13.6, 7.0, 0.0, -1.35), tilt=0.5,
                      band='AMP CAPTURE', sub='NAM TRAINING TAKE')}


def job_box():
    A = LAY['anchors']
    for key, B in BOXES.items():
        W_, H_ = B['w'], B['h']
        s, cam = TK.scene(W_, H_, 0.8)
        TK.catcher(-B['d'])
        bx = rbox('box', W_, H_, B['d'], -B['d'], 0.12, roll=0.1); TK.flat_faces(bx)
        T.K.set_seed('box' + key) if hasattr(T.K, 'set_seed') else None
        bx.data.materials.append(kraft('kraft' + key))
        # the printed band across the top, and its legends
        band = rbox('band', W_ - 0.02, 2.2, 0.01, 0.0, 0.0); band.location = (0, H_ / 2 - 1.75, 0)
        band.data.materials.append(mat('band' + key, srgb('#5a2a1e'), rough=0.75, spec=0.3))
        T.ink(B['band'], 0, H_ / 2 - 1.55, 0.012, 0.62, color='#e8dcc0', track=0.3)
        T.ink(B['sub'], 0, H_ / 2 - 2.35, 0.012, 0.26, color='#d8c8a8', track=0.25, w=W_ - 2)
        lw, lh, lx, ly = B['label']
        blank = np.ones((int(lh * 60), int(lw * 60), 3), np.float32) * (np.array([252, 238, 200], np.float32) / 255.0)
        lab = T.img_plane('label' + key, blank, lw, lh, lx, ly, 0.004)
        lab.rotation_euler = (0, 0, math.radians(B['tilt']))
        full(s, 'box-' + key)
        A['box_' + key] = {'tl': pj(s, cam, (-W_ / 2, H_ / 2, 0.0)), 'br': pj(s, cam, (W_ / 2, -H_ / 2, 0.0)),
                           'label_tl': pj(s, cam, (lx - lw / 2, ly + lh / 2, 0.004)), 'label_br': pj(s, cam, (lx + lw / 2, ly - lh / 2, 0.004)),
                           'tilt_deg': B['tilt']}
    A['px_per_cm'] = PXCM


if __name__ == '__main__':
    t = time.time()
    {'reel': job_reel, 'cart': job_cart, 'box': job_box}[WHAT]()
    json.dump(LAY, open(os.path.join(OUT, 'tape-layers-%s.json' % WHAT), 'w'), indent=1)
    print('done %.1fs' % (time.time() - t))
