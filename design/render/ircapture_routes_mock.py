# ircapture_routes_mock.py: the fifth proof's units as the app draws them, from the kit (11-13, a check before CI).
#
#   python3 design/render/ircapture_routes_mock.py <Resources/SwellKit> <out.png> [daw|rex|trouble|all]
#
# The DAW route (step-daw, chart-daw, signal, tracks, go-daw), the re-export (step-rex, files-rex, go-rex) and the
# pre-flight with its TROUBLE box, each base with sample states laid over it: lamps lit, a selector turned, thumbwheel
# figures, the track sheet typed and its toggles thrown (plugs on the empty lines), the past capture's card typed and
# stamped, a fault typed in red. Not the app: a check that every place in irc-rack.json lands where it should (typing in
# Courier Prime, multiplied, as PaperInk does; the hit areas outlined).
import sys, os, json, math
from PIL import Image, ImageDraw, ImageFont, ImageChops
import numpy as np

KIT, OUTP = sys.argv[1], sys.argv[2]
WHICH = sys.argv[3] if len(sys.argv) > 3 else 'all'
J = json.load(open(os.path.join(KIT, 'irc-rack.json')))
K = J['pxPerPoint']
PIC = os.path.join(KIT, 'pictures')
FONT = os.path.join(KIT, 'fonts')


def img(n): return Image.open(os.path.join(PIC, n + '.webp')).convert('RGBA')
def P(v): return round(v * K)


def lay(out, U, name):
    L = U['layers'].get(name)
    if L is None: print('  no layer', U['picture'], name); return
    out.alpha_composite(img(L['picture']), (P(L['rect'][0]), P(L['rect'][1])))


def figures(out, W, values):
    sh = img(W['picture']); fw = sh.size[0] // 10
    for i, v in enumerate(values):
        if v is None or i >= len(W['windows']): continue
        f = sh.crop((v * fw, 0, (v + 1) * fw, sh.size[1]))
        r = W['windows'][i]
        out.alpha_composite(f.resize((max(1, P(r[2])), max(1, P(r[3]))), Image.LANCZOS), (P(r[0]), P(r[1])))


def outline(out, r, col=(255, 0, 0, 255)):
    ImageDraw.Draw(out).rectangle([P(r[0]), P(r[1]), P(r[0] + r[2]), P(r[1] + r[3])], outline=col, width=1)


class Typist:
    """Typing multiplied over a sheet: x, baseline in sheet cm."""
    def __init__(self, out, sheet, w_cm, typed_cm):
        self.out = out; self.sx, self.sy = sheet[0], sheet[1]; self.k = sheet[2] / w_cm
        self.ink = Image.new('RGB', out.size, (255, 255, 255)); self.d = ImageDraw.Draw(self.ink)
        self.f = ImageFont.truetype(os.path.join(FONT, 'CourierPrime-400.ttf'), max(6, P(typed_cm * self.k)))
        self.adv = 0.6 * typed_cm
    def type(self, x, b, t, col=(34, 32, 44)):
        for i, ch in enumerate(t):
            self.d.text((P(self.sx + (x + i * self.adv) * self.k), P(self.sy + b * self.k)), ch, font=self.f, fill=col, anchor='ls')
    def printed(self, x, b, t, cm, col=(104, 30, 24)):
        f = ImageFont.truetype(os.path.join(FONT, 'BarlowSemiCondensed-700-normal.ttf'), max(6, P(cm * self.k)))
        self.d.text((P(self.sx + x * self.k), P(self.sy + b * self.k)), t, font=f, fill=col, anchor='ls')
    def done(self):
        rgb = ImageChops.multiply(self.out.convert('RGB'), self.ink)
        self.out.paste(rgb, (0, 0), self.out.getchannel('A'))


units = []
if WHICH in ('daw', 'all'):
    # the strip: TEST SIGNAL and RECORD IN DAW done, MAKE IRS current
    U = J['units']['step-daw']; o = img(U['picture'])
    for n in ('l0-green', 'l1-green', 'l2-amber'): lay(o, U, n)
    units.append(o)
    units.append(img(J['units']['chart-daw']['picture']))
    # the test signal: RATE 48, LEVEL -18, 08 sweeps of 06.0 s, gap 02.5 s, 1 warm-up; SAVE SIGNAL down
    U = J['units']['signal']; S = U['signal']; o = img(U['picture'])
    lay(o, U, 'sel0-p1'); lay(o, U, 'sel1-p2'); lay(o, U, 'k0-down')
    figures(o, S['wheels'], [0, 8, 0, 6, 0, 0, 2, 5, 1])
    for k_ in S['keys']: outline(o, k_['rect'], (255, 255, 0, 255))
    for s_ in S['selectors']:
        for q in s_['labels']: outline(o, q, (255, 0, 255, 255))
    units.append(o)
    # the track sheet: three mics and a reference; lines 5 to 8 plugged
    U = J['units']['tracks']; T = U['tracks']; o = img(U['picture'])
    roles = ['mic', 'mic', 'mic', 'ref']
    for i, r in enumerate(roles): lay(o, U, 't%d-%s' % (i, r))
    for i in range(len(roles), T['form']['rows']): lay(o, U, 'p%d' % i)
    F = T['form']; ty = Typist(o, T['sheet'], F['w'], F['typedCm']); col = {c['key']: c['x'] for c in F['cols']}
    rows = [('Mesa 4x12 SM57.wav', 'SM57'), ('Mesa 4x12 R121.wav', 'R121'), ('Mesa 4x12 Room.wav', 'Room'), ('Mesa 4x12 Ref.wav', '')]
    for i in range(F['rows']):
        ty.printed(col['trk'] + 0.35, F['centres'][i] + 0.2, str(i + 1), 0.56)
        if i < len(rows):
            b = F['baselines'][i]
            for key, t in (('file', rows[i][0]), ('name', rows[i][1]), ('khz', '96'), ('bits', '24'), ('seconds', '71.0')):
                if t: ty.type(col[key] + 0.1, b, t)
    ty.done()
    rowh = T['pitch']
    for i, c in enumerate(T['toggles'][:len(roles)]):
        outline(o, [T['columns'][0] - T['column'] / 2, c[1] - rowh / 2, 3 * T['column'], rowh], (0, 255, 200, 255))
    for k_ in T['keys']: outline(o, k_['rect'], (255, 255, 0, 255))
    units.append(o)
    # MAKE IRS lit while the files are made
    U = J['units']['go-daw']; o = img(U['picture']); lay(o, U, 'k0-lit'); units.append(o)
if WHICH in ('rex', 'all'):
    U = J['units']['step-rex']; o = img(U['picture'])
    for n in ('l0-green', 'l1-green', 'l2-amber'): lay(o, U, n)
    units.append(o)
    # the past capture's card typed and stamped; UNIVERSAL and MIN PHASE lit; CHOOSE down
    U = J['units']['files-rex']; Fz = U['files']; o = img(U['picture'])
    lay(o, U, 'k0-lit'); lay(o, U, 'k3-lit'); lay(o, U, 'k5-down')
    fm = Fz['form']; ty = Typist(o, Fz['sheet'], fm['w'], fm['typedCm'])
    vals = {'name': ['Marshall_1960A_G12M_Edge'], 'notes': ['G12M 25, SM57 on the cone edge.', 'Captured 2026-10-30.'],
            'folder': ['~/Music/IR Capture/Marshall_1960A_G12M_Edge']}
    for f in fm['fields']:
        for t, b in zip(vals[f['key']], f['baselines']): ty.type(f['x0'], b, t)
    ty.done()
    st = Fz['stamp']; si = img(st['picture'])
    sw, sh = P(st['size'][0]), P(st['size'][1])
    si = si.resize((sw, sh), Image.LANCZOS).rotate(st['turn'], resample=Image.BICUBIC, expand=True)
    k = Fz['sheet'][2] / fm['w']
    cx, cy = Fz['sheet'][0] + st['right'] * k - st['size'][0] / 2, Fz['sheet'][1] + st['top'] * k + st['size'][1] / 2
    ink = Image.new('RGB', o.size, (255, 255, 255)); x0, y0 = P(cx) - si.size[0] // 2, P(cy) - si.size[1] // 2
    ink.paste(si.convert('RGB'), (x0, y0), si.getchannel('A'))
    o.paste(ImageChops.multiply(o.convert('RGB'), ink), (0, 0), o.getchannel('A'))
    for k_ in Fz['keys']: outline(o, k_['rect'], (255, 255, 0, 255))
    units.append(o)
    U = J['units']['go-rex']; o = img(U['picture']); lay(o, U, 'k1-lit')
    for k_ in U['go']['keys']: outline(o, k_['rect'], (255, 255, 0, 255))
    units.append(o)
if WHICH in ('trouble', 'all'):
    U = J['units']['preflight-trouble']; Pf = U['preflight']; o = img(U['picture'])
    F = Pf['form']; ty = Typist(o, Pf['sheet'], F['w'], F['typedCm'])
    lines = [('Mics', '1: SM57'), ('Reference', 'None'), ('Sample rate', '48 kHz on Scarlett 2i2'), ('Levels', 'Not checked yet'),
             ('Sweep level', 'Set automatically'), ('Room noise', 'Not measured yet'), ('Files', 'Universal, minimum phase')]
    for i, (a, b) in enumerate(lines):
        base = F['baseline0'] + i * F['rowH']
        ty.type(F['cols'][0]['x'] + 0.1, base, a); ty.type(F['cols'][1]['x'] + 0.1, base, b)
    T = F['trouble']
    msg = ['Capture stopped. The interface stopped answering (CoreAudio', '-10863). Nothing was saved. Check the cable and the interface,',
           'then click Capture again.']
    for t, b in zip(msg, T['baselines']): ty.type(T['x0'], b, t, (168, 36, 30))
    ty.done(); units.append(o)

W = max(u.size[0] for u in units); H = sum(u.size[1] for u in units) + 8 * (len(units) - 1)
out = Image.new('RGBA', (W, H), (40, 36, 30, 255)); y = 0
for u in units: out.alpha_composite(u, (0, y)); y += u.size[1] + 8
out.save(OUTP)
print(OUTP, out.size)
