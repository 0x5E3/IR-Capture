"""ircapture_eye.py: IR Capture's own magic eye, in its one camera (11-10).

Lowell, 11-10, on the noise eyes: "the magic eyes not having perspective". They were the bench's frames (rack.py's
Monitor unit, seen straight on by the frame camera), while every other piece in IR Capture is seen from the Tools
studio's 10 degrees above. Lowell chose (11-10) one set of frames in that one camera.

So: rack.py's own Eye (the 6E5-style tube end on: chrome escutcheon, glass dome, the phosphor target and its shadow
wedge, the heater ring), at a real 6E5's scale (ES 1.12), behind a hole in a shadow-catching panel, in the Tools studio
(toolkit.scene(): orthographic, 10 degrees above, key up left) with IR Capture's 11-10 additions (the 1.0 px filter,
the workshop room in the reflections). The background is transparent: the app lays the eye on its own panel.

Writes <out>/eye-base.png (unlit, with the escutcheon), eye-<state>.png for warm0..2 and x00..x55 (rack.py's states:
x is the eye's closure, 48 steps to shut and 8 past it), and eye.json (the square's size in cm, the centre, radii).
ircapture_eye_post.py makes SwellKit's irc-eye-base.webp, the 59-frame sheet irc-eye.webp (12 a row) and irc-eye.json.

Usage (from the desktop bench's design/render, or with it on the path):
  ~/bvenv/bin/python design/render/ircapture_eye.py <out> <fonts> [px/cm] [samples] [states]
  states: all (default), or a comma list (x00,x24,warm1) for a proof.
"""
import os, sys, math, json, time
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
BENCH = os.environ.get('BENCH_RENDER', '/home/claude/desktop-bench/design/render')
if os.path.isdir(BENCH): sys.path.insert(1, BENCH)

OUT = sys.argv[1]; FONTS = sys.argv[2]
PXCM = float(sys.argv[3]) if len(sys.argv) > 3 else 44.0
SAMPLES = int(sys.argv[4]) if len(sys.argv) > 4 else 128
WHICH = sys.argv[5] if len(sys.argv) > 5 else 'all'
os.makedirs(OUT, exist_ok=True)

argv0 = sys.argv
sys.argv = [argv0[0], OUT, 'eye', str(PXCM), str(SAMPLES)]
import bpy
import toolkit as TK
import parts as P
import metal_kit as MK
from gear_kit import cut, cyl_cutter
sys.argv = [argv0[0], FONTS, OUT]
import rack as RA
sys.argv = argv0

ES = float(os.environ.get('IRC_EYE_ES', '1.12'))
RA.set_eye(ES)
R_OUT = 2.35 * ES                  # the escutcheon's outer radius
R_SHOW = 1.82 * ES                 # the radius the bench's crop showed (glass and the escutcheon's inner bevel)
HALF = 2.75 * ES                   # the square's half side: the escutcheon and its shadow
FILTER = float(os.environ.get('IRC_FILTER', '1.0'))


def scene():
    s, cam = TK.scene(2 * HALF, 2 * HALF, 0.0)
    try: s.cycles.filter_width = FILTER
    except Exception: pass
    if os.environ.get('IRC_ROOM', '1') != '0': MK.room_world(s)
    s.render.film_transparent = True
    # (11-10 proof) the studio's top softbox showed as a hard bright rectangle on the dome and the cap, the flat plugin
    # look the rules rule out; it still lights the eye, only it is not mirrored (the room in the world still is)
    for o in s.objects:
        if o.name.split('.')[0] in ('top', 'topL'):
            try: o.visible_glossy = False
            except Exception: pass
    side = int(round(2 * HALF * PXCM / 4)) * 4
    s.render.resolution_x = s.render.resolution_y = side
    cam.data.ortho_scale = side / PXCM
    e = math.radians(TK.ELEV)
    # centred on the eye's face (z 0): the view plane's v of the origin is 0
    cam.location = (0, 200 * math.sin(e), 200 * math.cos(e)); cam.rotation_euler = (-e, 0, 0); cam.data.shift_y = 0.0
    return s, cam, side


def main():
    s, cam, side = scene()
    # the panel round the eye: a shadow catcher with the eye's hole (rack.py's monitor: 1.6 ES)
    bpy.ops.mesh.primitive_plane_add(size=40, location=(0, 0, 0)); pn = bpy.context.active_object
    cut(pn, cyl_cutter(1.6 * ES, 0, 0, -5, 5))
    pn.is_shadow_catcher = True
    chrome = RA.metal('chrome', '#eceeef', 0.06, grime=0.4)
    eye = RA.Eye(0.0, 0.0, chrome, 'irc')
    states = RA.EYE_STATES if WHICH == 'all' else ['unlit'] + [x for x in WHICH.split(',') if x != 'unlit']
    t0 = time.time()
    for st in states:
        eye.set(st)
        P.render(s, os.path.join(OUT, 'eye-base.png' if st == 'unlit' else 'eye-%s.png' % st))
    json.dump({'px': side, 'pxcm': PXCM, 'samples': SAMPLES, 'elev': TK.ELEV, 'es': ES, 'half_cm': HALF,
               'r_outer_cm': R_OUT, 'r_show_cm': R_SHOW, 'r_glass_cm': 1.42 * ES,
               'centre_px': [side / 2, side / 2], 'states': states, 's': round(time.time() - t0, 1)},
              open(os.path.join(OUT, 'eye.json'), 'w'), indent=1)


if __name__ == '__main__':
    main()
