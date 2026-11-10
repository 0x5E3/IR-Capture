"""ircapture_eye_post.py: SwellKit's magic eye from ircapture_eye.py's renders (11-10), lossless (webp_out).

Usage: python3 design/render/ircapture_eye_post.py <render dir> <SwellKit dir>
Writes pictures/irc-eye-base.webp (the unlit eye with its escutcheon), pictures/irc-eye.webp (the 59 lit frames:
warm0..2, then x00..x55, 12 a row, each the same square as the base) and irc-eye.json (the square, the radii in px).
The frames are whole pictures of the eye (escutcheon included), so the app crossfades them over the base.
"""
import os, sys, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import webp_out  # noqa: F401  (every WEBP lossless)
from PIL import Image

SRC, KIT = sys.argv[1], sys.argv[2]
PIC = os.path.join(KIT, 'pictures')
J = json.load(open(os.path.join(SRC, 'eye.json')))
side = J['px']; per = 12
frames = ['warm0', 'warm1', 'warm2'] + ['x%02d' % i for i in range(56)]
missing = [f for f in frames if not os.path.exists(os.path.join(SRC, 'eye-%s.png' % f))]
if missing: sys.exit('missing frames: %s' % ', '.join(missing))


def load(p):
    im = Image.open(p); im.load()                  # (the iMac's RAM fault: every picture opened in full first)
    assert im.size == (side, side), (p, im.size)
    return im.convert('RGBA')


base = load(os.path.join(SRC, 'eye-base.png'))
base.save(os.path.join(PIC, 'irc-eye-base.webp'), 'WEBP')
rows = -(-len(frames) // per)
sheet = Image.new('RGBA', (per * side, rows * side), (0, 0, 0, 0))
for i, f in enumerate(frames):
    sheet.paste(load(os.path.join(SRC, 'eye-%s.png' % f)), ((i % per) * side, (i // per) * side))
sheet.save(os.path.join(PIC, 'irc-eye.webp'), 'WEBP')
k = side / (2 * J['half_cm'])                       # px a cm
out = {'about': 'IR Capture\'s own magic eye (design/render/ircapture_eye.py: rack.py\'s Eye in the Tools studio, '
                'orthographic, %g degrees above). irc-eye-base: unlit; irc-eye: frames %d a row, frame i at '
                '((i %% %d) * side, (i / %d) * side): warm0..2 (0..2), then x00..x55 (3..58), x the closure, 48 steps to '
                'shut and 8 past it. Each frame is the whole eye, escutcheon included: draw the base, then the frames '
                'over it. Radii in px of a frame, from its centre.' % (J['elev'], per, per, per),
       'side_px': side, 'per_row': per, 'frames': frames, 'centre_px': J['centre_px'],
       'r_outer_px': round(J['r_outer_cm'] * k, 2), 'r_show_px': round(J['r_show_cm'] * k, 2),
       'r_glass_px': round(J['r_glass_cm'] * k, 2), 'pxcm': J['pxcm'], 'samples': J['samples']}
json.dump(out, open(os.path.join(KIT, 'irc-eye.json'), 'w'), indent=1)
print('wrote irc-eye-base.webp, irc-eye.webp (%d x %d), irc-eye.json' % sheet.size)
