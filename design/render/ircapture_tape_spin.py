# ircapture_tape_spin.py: the reel's rotation sprite, for the reel-speed test (Phase 7 round 3b concept, 2026-11-03).
#
# One 7 inch reel on a patch of the deck plate, in the same studio as every IR Capture piece, rendered at N angles over
# 120 degrees (the three windows repeat there), sharp and with motion blur. The light stays put while the reel turns, so
# each frame is shaded correctly (a 2D rotation of one picture would turn the highlights with it).
#
# Proof only: the tape pack is fixed at one radius. In the app the pack has to be its own layer between the flanges
# (rear flange, pack at a dozen radii, front flange and hold-down), so a turning reel and a changing pack combine.
#
#   FONTS_DIR=Resources/SwellKit/fonts ~/bvenv/bin/python design/render/ircapture_tape_spin.py <out dir> [px/cm] [samples] [frames] [blur deg]
import sys, os, math, json, time
_argv = sys.argv[:]
OUT = _argv[1] if len(_argv) > 1 else '/tmp/irspin'
PXCM = float(_argv[2]) if len(_argv) > 2 else 20.0
SAMPLES = int(_argv[3]) if len(_argv) > 3 else 8
N = int(_argv[4]) if len(_argv) > 4 else 24
BLUR = float(_argv[5]) if len(_argv) > 5 else 10.0
sys.argv = [_argv[0], OUT, 'reel', str(PXCM), str(SAMPLES), '0.5']
import ircapture_tape as T
sys.argv = _argv
import bpy
import toolkit as TK
import shelf_gear as SG
from gear_kit import rbox
TK.OUT, TK.PXCM, TK.SAMPLES = OUT, PXCM, SAMPLES
os.makedirs(OUT, exist_ok=True)

SZ = 20.0
s, cam = TK.scene(SZ, SZ, 0.2)
TK.catcher(-0.5)
plate = rbox('plate', SZ + 2, SZ + 2, 0.25, 0.0, 0.0); TK.flat_faces(plate); plate.data.materials.append(T.brushed_alu())
hub, full = T.REEL['hub'], T.REEL['pack_full']
rp = math.sqrt(hub * hub + (full * full - hub * hub) * 0.5)         # the pack half full
before = set(bpy.data.objects)
T.reel(0.0, 0.0, rp, 0.0, T.reel_alu(), T.oxide(), SG.chrome('chr', seed=3), SG.black_cast('bc'))
parts = [o for o in set(bpy.data.objects) - before if o.type == 'MESH']
pivot = bpy.data.objects.new('pivot', None); s.collection.objects.link(pivot)
for o in parts:
    mw = o.matrix_world.copy(); o.parent = pivot; o.matrix_world = mw
s.render.motion_blur_shutter = 1.0
try: s.render.motion_blur_position = 'START'
except Exception: pass
lay = {'frames': N, 'span_deg': 120, 'blur_deg': BLUR, 'pack_r_cm': round(rp, 3), 'pxcm': PXCM}
t0 = time.time()
for blur in (False, True):
    s.render.use_motion_blur = blur
    for i in range(N):
        a = math.radians(-120.0 * i / N)                      # clockwise as seen from the front, as the supply reel pays out
        pivot.animation_data_clear()
        pivot.rotation_euler = (0, 0, a); pivot.keyframe_insert('rotation_euler', frame=1)
        pivot.rotation_euler = (0, 0, a - math.radians(BLUR if blur else 0.0)); pivot.keyframe_insert('rotation_euler', frame=2)
        s.frame_set(1)
        TK.shoot(s, cam, 'spin-%s-%02d' % ('blur' if blur else 'sharp', i), SZ, SZ)
print('spin done %.0fs' % (time.time() - t0))
json.dump(lay, open(os.path.join(OUT, 'spin.json'), 'w'), indent=1)
