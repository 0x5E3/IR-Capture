# ircapture_shelf.py: the top shelf from below at the rack bay's scale (2026-11-11, proof).
#
# The rack bay (ircapture_rack.py) is drawn at one scale, 14 pt a cm; the shelf was still 8 pt a cm (its boxes 36 x 7
# cm, drawn small). Here the shelf is rebuilt at 14 pt a cm and seen as the rule says, from 9 degrees below (it is above
# the eye): the shop-wood plank's front edge and dark underside, no top, and on it three small boxes standing where the
# app's shelf has them, now sized to what they hold:
#
#   left    the two job keys, CAB IR (lit, the job showing) and AMP NAM
#   middle  the power lamp and the status line on the bench's blue-green VFD, 26 characters, its dot pitch 1.05 mm
#           (capitals 0.74 cm: 10.3 pt on screen, against 8.9 pt in the preview build, and the glass filled)
#   right   HELP
#
# Rendered WHOLE with its live parts baked in (the lit key, the lamp, the VFD's text), as a proof. For the app the plank
# stays a long strip and each box a picture with its keys and display as layers, as now.
#
#   FONTS_DIR=Resources/SwellKit/fonts ~/bvenv/bin/python design/render/ircapture_shelf.py <out> [px/cm] [samples]
import sys, os, math, json, time
_argv = sys.argv[:]
OUT = _argv[1] if len(_argv) > 1 else '/tmp/ircshelf'
PXCM = float(_argv[2]) if len(_argv) > 2 else 28.0
SAMPLES = int(_argv[3]) if len(_argv) > 3 else 32
sys.argv = [_argv[0], OUT, 'none', str(PXCM), str(SAMPLES)]
import ircapture_rack as R                    # the rack's parts (key, jewel, moved), its studio and K, TK, SG
sys.argv = _argv
K, TK, SG = R.K, R.TK, R.SG
import bpy
from parts import mat, srgb
from gear_kit import rbox, cut, chamfer, screw

WIDTH = float(os.environ.get('IRC_SHELF_CM', '72'))        # the strip: a 920 pt window is 65.7 cm at 14 pt a cm
VFD_PITCH = float(os.environ.get('IRC_VFD_PITCH', '0.105'))
VFD_TEXT = os.environ.get('IRC_VFD_TEXT', 'READY  INTERFACE 1  96 KHZ')
BOX = dict(h=4.2, d=8.0, z_front=11.0, foot=0.4, r=0.4, roll=0.22, pad=1.2, screw_in=0.6)
# where the boxes stand (their centres, cm from the strip's middle), as the app's shelf has them
X_LEFT, X_MID, X_RIGHT = -24.0, 0.0, 26.0
LAY = {'pxcm': PXCM, 'samples': SAMPLES, 'elev': K.SHELF_ELEV, 'pt_per_cm': R.PT, 'boxes': {}}


def box_mat(finish, name, w):
    m = (K.hammertone_fine(base='#1a1610', hi='#3d3224', name='hbox-' + name) if finish == 'bronze'
         else SG.crackle(base='#2e0d09'))
    K.calm_up(m)
    sx_, sy_ = w / 2 - BOX['screw_in'], BOX['h'] / 2 - BOX['screw_in']
    K.screw_ring(m, [(sx * sx_, sy * sy_, 0.0) for sx in (-1, 1) for sy in (-1, 1)]); K.corner_wear(m, w / 2)
    return m


def vfd(box, xc, n=26):
    """The status line: ircapture_kit.piece_gas('line') with the VFD look, in a window cut in the box's face (z = 0)
    at x = xc (the cut happens now, so the cutter is placed by hand; the rest is built about 0 and moved)."""
    import gas_disp as GD
    W, H, Wu, Hu = GD.mtx_geom(n, 1)
    dw, dh = Wu * VFD_PITCH, Hu * VFD_PITCH
    ww, wh = dw + 0.6, dh + 0.6
    T = 0.32
    hole = rbox('vhole', ww, wh, T + 2, -T - 1, 0.08); hole.location.x = xc
    bpy.context.view_layer.update(); cut(box, hole)
    with R.moved(xc, 0, 0): _vfd_parts(ww, wh, T, n)
    return ww + 2 * K.GAS_BEZEL, wh + 2 * K.GAS_BEZEL


def _vfd_parts(ww, wh, T, n):
    import gas_disp as GD
    bw = K.GAS_BEZEL
    bez = rbox('gbezel', ww + 2 * bw, wh + 2 * bw, 0.14, 0.0, 0.12, roll=0.05)
    bh = rbox('gbezh', ww - 0.04, wh - 0.04, 1.0, -0.5, 0.06)
    bpy.context.view_layer.update(); cut(bez, bh); chamfer(bez, 0.02, 2); TK.flat_faces(bez)
    bez.data.materials.append(K.gas_bezel_mat())
    rd = os.path.join(OUT, 'gas'); os.makedirs(rd, exist_ok=True)
    RA = K._RackAdapter(T, rd)
    old = GD.DEMO, GD.demo_text, GD.matrix_maps, GD.thin_glass
    GD.DEMO = True; GD.demo_text = lambda eid: [VFD_TEXT]
    _tg = GD.thin_glass
    GD.matrix_maps = lambda b, e, n_, nl, **kw: K.vfd_matrix_maps(GD, b, e, n_, nl, **kw)
    GD.thin_glass = lambda RA_, name, tint='#c8b49e', dust=0.5, rough=0.03: _tg(RA_, name, K.VFD_GLASS if name.endswith('pane') else tint, dust, rough)
    L = []
    try:
        GD.gas_window(RA, L, 'shelf-vfd', 'matrix', -ww / 2, -wh / 2, ww / 2, wh / 2, SG.nickel('gscrew', seed=3), 3, n=n, lines=1)
    finally:
        GD.DEMO, GD.demo_text, GD.matrix_maps, GD.thin_glass = old
    for o in bpy.data.objects:
        if o.name.endswith('pane') or o.name.endswith('env'):
            o.visible_shadow = False
            if o not in R.GLASS: R.GLASS.append(o)


def shelf_box(name, finish, cx, parts):
    """A box standing on the plank: its face at z_front, its bottom on rubber feet; `parts` (key ids, 'lamp', 'vfd')
    laid out left to right on the face, the box as wide as they need."""
    import ircapture_legends as LG
    sizes = []
    for p in parts:
        if p == 'lamp': sizes.append(1.5)
        elif p == 'vfd':
            import gas_disp as GD
            _, _, Wu, Hu = GD.mtx_geom(26, 1); sizes.append(Wu * VFD_PITCH + 0.6 + 2 * K.GAS_BEZEL)
        else: sizes.append(K.legend_width(LG.LEGENDS[p[0]][0], 'std') + 2 * TK.KEY['bezel'])
    gap = 0.6
    w = sum(sizes) + gap * (len(parts) - 1) + 2 * BOX['pad']
    h, d, zf, fh = BOX['h'], BOX['d'], BOX['z_front'], BOX['foot']
    K.set_seed('shelfbox-' + name)
    with R.moved(cx, fh + h / 2, zf):
        b = rbox('box-' + name, w, h, d, -d, BOX['r'], roll=BOX['roll']); TK.flat_faces(b)
        x = -w / 2 + BOX['pad']
        for p, sz in zip(parts, sizes):
            xc = x + sz / 2
            if p == 'lamp':
                R.jewel(xc, 0.0, 'amber', True, r=0.48)
            elif p == 'vfd':
                vfd(b, xc)
            else:
                with R.moved(xc, 0, 0): R.key(p[0], lit=p[1])
            x += sz + gap
        b.data.materials.append(box_mat(finish, name, w))     # after every cut (gear_kit.cut clears the materials)
        nk = SG.nickel('boxscrew-' + name, seed=K.seed_of(name) % 97)
        for sx in (-1, 1):
            for sy in (-1, 1):
                screw(sx * (w / 2 - BOX['screw_in']), sy * (h / 2 - BOX['screw_in']), nk)
    rm = SG.rubber()
    for fx in (cx - (w / 2 - 1.4), cx + (w / 2 - 1.4)):
        bpy.ops.mesh.primitive_cylinder_add(radius=0.55, depth=fh + 0.05, vertices=40, location=(fx, fh / 2, zf - 1.3))
        f = bpy.context.active_object; f.rotation_euler = (math.radians(90), 0, 0); f.data.materials.append(rm)
        bpy.ops.object.shade_smooth()
    LAY['boxes'][name] = {'x': [cx - w / 2, cx + w / 2], 'cm': [w, h], 'parts': [p if isinstance(p, str) else p[0] for p in parts]}
    return w


def build_boxes():
    shelf_box('jobs', 'bronze', X_LEFT, [('cab-ir', True), ('amp-nam', False)])
    shelf_box('status', 'bronze', X_MID, ['lamp', 'vfd'])
    shelf_box('help', 'oxblood', X_RIGHT, [('help', False)])
    R.finish_glass()


def main():
    t = time.time()
    K.use_elev(K.SHELF_ELEV)                                      # the studio's camera turned (scene_now), TK.ELEV kept
    K.LONG['plank'] = WIDTH; K.LONG['seg'] = WIDTH + 10           # one segment: the boxes lit with the plank
    _rl = K.render_long

    def render_long(s, cam, name, vertical, u0, u1, c0, c1):
        build_boxes()
        top = K.v_of(BOX['foot'] + BOX['h'], BOX['z_front']) + 1.6
        return _rl(s, cam, name, vertical, u0, u1, c0, max(c1, top))
    K.render_long = render_long
    K.piece_plank_shop()
    K.render_long = _rl
    os.replace(os.path.join(OUT, 'plank.png'), os.path.join(OUT, 'shelf.png'))
    LAY['shelf'] = K.LAY['out']['plank']
    # piece_plank_shop measured its rows from its own top (the plank's front edge + 1.4); the frame was raised for the
    # boxes, so every row moves down by the difference
    v0 = K.v_of(0, K.PL['depth']) + 1.4
    v1 = max(v0, K.v_of(BOX['foot'] + BOX['h'], BOX['z_front']) + 1.6)
    for k in [k for k in LAY['shelf'] if k.startswith('row_')]: LAY['shelf'][k] += (v1 - v0) * PXCM
    LAY['shelf']['v_top'] = v1
    LAY['s'] = round(time.time() - t, 1)
    json.dump(LAY, open(os.path.join(OUT, 'shelf.json'), 'w'), indent=1)
    print('shelf %.0fs' % (time.time() - t), flush=True)


if __name__ == '__main__':
    main()
