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
from parts import mat, srgb, lathe
from gear_kit import rbox, cut, chamfer, surface_wear, screw, node, obj_coords, add_bump, mix_into, edge_mask, noise, mul, scratches
from instrument import grimy
import toolkit as TK
import shelf_gear as SG
import shelf_wood as SW
sys.argv = _argv
TK.OUT, TK.PXCM, TK.SAMPLES = OUT, PXCM, SAMPLES
ELEV = TK.ELEV
E = math.radians(ELEV)
CE, SE = math.cos(E), math.sin(E)

# the shelf's measures (cm)
PL = dict(thick=2.6, depth=12.0, edge=0.28, period=60.0, fade=10.0, pre=3.0)
BOX = dict(w=36.0, h=7.0, d=10.0, r=0.45, roll=0.25, z_front=11.0, foot_h=0.4, foot_r=0.6, foot_in=1.8, right=12.0, left=1.6, head=3.4)
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

def hammertone_fine(base='#1d1812', hi='#3a3226', name='hfine', cells=8.0):
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
    """The plank's front-edge and top maps, periodic over PL['period'] cm along x."""
    save = SW.LEN, SW.DEPTH
    SW.LEN, SW.DEPTH = 120.0, PL['depth']
    try:
        front = SW.face(K, 'front')
        top = _oak_top(K, 16.0)
    finally:
        SW.LEN, SW.DEPTH = save
    (fr, tp), xa = _periodic([front, top], K, -60.0, PL['period'], PL['fade'], -56.0, 56.0)
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
    """toolkit.piece_panel() with another finish (same size, rolled edges, a screw in each corner)."""
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
    fr, tp, xa = plank_maps(K)
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
    m = hammertone_fine(base='#1a1610', hi='#3d3224', name='hbox') if finish == 'bronze' else SG.crackle(base='#2e0d09')
    calm_up(m)
    o = rbox('box', w, h, d, zf - d, BOX['r'], roll=BOX['roll'])
    o.location = (0, fh + h / 2, 0); o.data.materials.append(m); TK.flat_faces(o)
    rm = SG.rubber()
    for fx in (-(w / 2 - BOX['foot_in']), w / 2 - BOX['foot_in']):
        bpy.ops.mesh.primitive_cylinder_add(radius=BOX['foot_r'], depth=fh + 0.05, vertices=40, location=(fx, fh / 2, zf - 1.3))
        f = bpy.context.active_object; f.rotation_euler = (math.radians(90), 0, 0); f.data.materials.append(rm)
        bpy.ops.object.shade_smooth()
    v_top = v_of(fh + h, zf - d) + BOX['head']; v_bot = v_of(0.0, PL['depth'])   # the wall's darkening round the box
    frame(s, cam, -w / 2 - BOX['left'], w / 2 + BOX['right'], v_bot, v_top)
    bpy.context.view_layer.update()
    lay = {'cm': [w, h], 'box_x': [-w / 2, w / 2],
           'px_left': proj(s, cam, (-w / 2, 0, zf))[0], 'px_right': proj(s, cam, (w / 2, 0, zf))[0],
           'row_lid_back': proj(s, cam, (0, fh + h, zf - d))[1], 'row_face_top': proj(s, cam, (0, fh + h, zf))[1],
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


def main():
    todo = (['panel-fine', 'panel-nam', 'plank', 'box-bronze', 'box-oxblood', 'trim-h', 'trim-v'] if WHAT == 'all'
            else WHAT.split(','))
    for pc in todo:
        t = time.time()
        if pc.startswith('box-'): piece_box(pc)
        elif pc.startswith('trim-'): piece_trim(pc[5:])
        else: globals()['piece_' + pc.replace('-', '_')]()
        print('piece', pc, '%.1fs' % (time.time() - t), flush=True)
        path = os.path.join(OUT, 'irc-render-%s.json' % pc)
        json.dump({'pxcm': PXCM, 'elev': ELEV, 'samples': SAMPLES, 'out': {pc: LAY['out'][pc]}}, open(path, 'w'), indent=1)


if __name__ == '__main__':
    main()
