# ircapture_shelf_mock.py: the shelf from below as the app lays it out (RackShelf.swift), from the kit's pictures, as a
# check before CI (2026-11-12).
#
#   ~/bvenv/bin/python design/render/ircapture_shelf_mock.py <Resources/SwellKit> <out.png> [width pt] [job] [lamp] [text]
#
# job: cab | nam (the lit key); lamp: off | amber | red; text: the VFD's line. The wall is the pegboard tile; the
# plank strip at its rendered height; the boxes on it: the jobs box at the left padding, the help box at the right, the
# status box centred between them (the HStack's spacers); the VFD's dots lit with gas_disp's 5 x 7 font.
import sys, os, json
sys.path.insert(0, '/home/claude/desktop-bench/design/render')
from PIL import Image, ImageDraw, ImageFilter
import numpy as np

KIT, OUTP = sys.argv[1], sys.argv[2]
WPT = float(sys.argv[3]) if len(sys.argv) > 3 else 920
JOB = sys.argv[4] if len(sys.argv) > 4 else 'cab'
LAMP = sys.argv[5] if len(sys.argv) > 5 else 'off'
TEXT = sys.argv[6] if len(sys.argv) > 6 else 'READY  SCARLETT 18I20  96K'
PIC = os.path.join(KIT, 'pictures')
J = json.load(open(os.path.join(KIT, 'irc-rack.json')))
S = J['shelf']; PX = J['pxPerPoint']
FACE_TOP, PAD, GAP = 30.0, 26.0, 14.0          # RackShelf.faceTop, .pad, .gapBelow


def pic(name): return Image.open(os.path.join(PIC, name + '.webp')).convert('RGBA')


pl = S['plank']; boxes = S['boxes']
jb = boxes['jobs']
plank_top = FACE_TOP + (jb['plankRow'] - jb['face'][1]) - pl['frontTop']
H = plank_top + pl['size'][1] + 20
W = int(WPT * PX); Hp = int(H * PX)
out = Image.new('RGBA', (W, Hp), (40, 42, 46, 255))
try:
    peg = Image.open(os.path.join(PIC, 'frame-peg.webp')).convert('RGBA')
    s = PX / 1.6; peg = peg.resize((max(1, int(peg.size[0] * s)), max(1, int(peg.size[1] * s))))
    for y in range(0, Hp, peg.size[1]):
        for x in range(0, W, peg.size[0]): out.alpha_composite(peg, (x, y))
except FileNotFoundError:
    pass
P = lambda v: int(round(v * PX))
strip = pic(pl['picture'])
x = 0
while x < W:
    out.alpha_composite(strip.crop((0, 0, min(strip.size[0], W - x), strip.size[1])), (x, P(plank_top))); x += strip.size[0]

# the boxes' face x: jobs at the padding, help flush right, status centred between them
fx = {'jobs': PAD, 'help': WPT - PAD - boxes['help']['face'][2]}
left = PAD + jb['face'][2]; right = fx['help']
fx['status'] = left + (right - left - boxes['status']['face'][2]) / 2
for nm in ('jobs', 'status', 'help'):
    b = boxes[nm]
    ox, oy = fx[nm] - b['face'][0], FACE_TOP - b['face'][1]          # the picture's top left, pt
    im = pic(b['picture'])
    on = set()
    if nm == 'jobs': on.add('k%d-lit' % (0 if JOB == 'cab' else 1))
    if nm == 'status' and LAMP != 'off': on.add('lamp-' + LAMP)
    for k in sorted(b['layers']):
        if k in on:
            L = b['layers'][k]; li = pic(L['picture'])
            im.alpha_composite(li, (P(L['rect'][0]), P(L['rect'][1])))
    if 'vfd' in b:
        import gas_disp as GD
        c = b['vfd']['cells']; m = b['vfd']['mtx']
        px_, py_ = c[2] / m[2], c[3] / m[3]
        lit = GD.mtx_lit(b['vfd']['n'], 1, [TEXT[:b['vfd']['n']]])
        glow = Image.new('RGBA', im.size, (0, 0, 0, 0)); g = ImageDraw.Draw(glow)
        core = Image.new('RGBA', im.size, (0, 0, 0, 0)); d = ImageDraw.Draw(core)
        r = 0.3 * min(px_, py_)
        for (i, j) in lit:
            cx, cy = (c[0] + (m[0] + i + 0.5) * px_) * PX, (c[1] + (m[1] + j + 0.5) * py_) * PX
            R_ = r * PX
            g.ellipse([cx - 1.6 * R_, cy - 1.6 * R_, cx + 1.6 * R_, cy + 1.6 * R_], fill=(62, 214, 190, 120))
            d.ellipse([cx - R_, cy - R_, cx + R_, cy + R_], fill=(62, 214, 190, 255))
            d.ellipse([cx - 0.45 * R_, cy - 0.45 * R_, cx + 0.45 * R_, cy + 0.45 * R_], fill=(225, 255, 246, 200))
        glow = glow.filter(ImageFilter.GaussianBlur(r * PX * 0.9))
        base = np.asarray(im, np.float32)
        for lay_ in (glow, core):
            a = np.asarray(lay_, np.float32); al = a[..., 3:4] / 255
            base[..., :3] = 255 - (255 - base[..., :3]) * (255 - a[..., :3] * al) / 255     # screen
        im = Image.fromarray(np.clip(base, 0, 255).astype(np.uint8), 'RGBA')
    out.alpha_composite(im, (P(ox), P(oy)))
out.convert('RGB').save(OUTP)
print('mock', out.size, 'plank top %.1f pt, shelf %.1f pt' % (plank_top, plank_top + pl['underBack'] + GAP))
