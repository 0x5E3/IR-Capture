# ircapture_meters_mock.py: the meter bridge as the app draws it, from the kit (11-11, a check before CI).
#
#   python3 design/render/ircapture_meters_mock.py <Resources/SwellKit> <out.png>
#
# Lays the base, the lit layers, the needles (turned about their pivot), the eye's frame, the gas segments (Rack.swift's
# geometry, GasFont's segments) and the names over each other for four sample channels, as Rack.swift's RackMeterBridge
# does, at the kit's own pixels. Not the app: a check that every place in irc-rack.json lands where it should.
import sys, os, json, math
from PIL import Image, ImageDraw, ImageFont, ImageFilter

KIT, OUTP = sys.argv[1], sys.argv[2]
J = json.load(open(os.path.join(KIT, 'irc-rack.json')))
U = J['units']['meters']; M = U['meters']; K = J['pxPerPoint']
PIC = os.path.join(KIT, 'pictures')
S7 = {'a': (0.17, 0.08, 0.83, 0.08), 'b': (0.92, 0.16, 0.92, 0.77), 'c': (0.92, 0.93, 0.92, 1.54), 'd': (0.17, 1.62, 0.83, 1.62),
      'e': (0.08, 0.93, 0.08, 1.54), 'f': (0.08, 0.16, 0.08, 0.77), 'g': (0.17, 0.85, 0.83, 0.85)}
D7 = {'0': 'abcdef', '1': 'bc', '2': 'abged', '3': 'abgcd', '4': 'fgbc', '5': 'afgcd', '6': 'afgedc', '7': 'abc', '8': 'abcdefg',
      '9': 'abcdfg', '-': 'g', ' ': ''}
CH = [dict(name='SM57 cap edge', vu=-0.4, peak=-6.4, lamps={1}, eye=3 + 50, blank=False),
      dict(name='R121 center', vu=-9, peak=-15.0, lamps={0}, eye=3 + 30, blank=False),
      dict(name='Room 3 m', vu=3.3, peak=-0.1, lamps={2, 3, 4}, eye=3 + 18, blank=False),
      dict(name='', vu=None, peak=None, lamps=set(), eye=None, blank=True)]


def img(n): return Image.open(os.path.join(PIC, n + '.webp')).convert('RGBA')


def angle(v):
    t = M['vuTable']
    if v is None: return t[0][1]
    x = max(t[0][0], min(t[-1][0], v))
    for (a, da), (b, db) in zip(t, t[1:]):
        if x <= b: return da + (x - a) / (b - a) * (db - da)
    return t[-1][1]


base = img(U['picture'])
out = base.copy()
for i, c in enumerate(CH):
    md = M['modules'][i]
    if c['blank']:
        L = U['layers']['b%d' % i]; out.alpha_composite(img(L['picture']), (round(L['rect'][0] * K), round(L['rect'][1] * K))); continue
    L = U['layers']['m%d-vu' % i]; out.alpha_composite(img(L['picture']), (round(L['rect'][0] * K), round(L['rect'][1] * K)))
    for k in c['lamps']:
        L = U['layers']['m%d-l%d' % (i, k)]; out.alpha_composite(img(L['picture']), (round(L['rect'][0] * K), round(L['rect'][1] * K)))
    # the needle, turned about its pivot (clockwise for a positive angle), clipped to the window
    N = M['needle']; nd = img(N['picture'])
    pvx, pvy = N['pivot'][0] * K, N['pivot'][1] * K
    big = Image.new('RGBA', out.size, (0, 0, 0, 0))
    big.alpha_composite(nd, (round(md['vuPivot'][0] * K - pvx), round(md['vuPivot'][1] * K - pvy)))
    big = big.rotate(-angle(c['vu']), resample=Image.BICUBIC, center=(md['vuPivot'][0] * K, md['vuPivot'][1] * K))
    w = md['vuWindow']; mask = Image.new('L', out.size, 0); ImageDraw.Draw(mask).rectangle([w[0] * K, w[1] * K, (w[0] + w[2]) * K, (w[1] + w[3]) * K], fill=255)
    sh = Image.new('RGBA', out.size, (0, 0, 0, 0)); sh.putalpha(big.getchannel('A').point(lambda v: int(v * 0.34)))
    sh = sh.filter(ImageFilter.GaussianBlur(0.8 * K)); sh = sh.transform(sh.size, Image.AFFINE, (1, 0, -0.7 * K, 0, 1, -1.0 * K))
    for layer in (sh, big):
        lay = Image.new('RGBA', out.size, (0, 0, 0, 0)); lay.paste(layer, (0, 0), Image.composite(layer, Image.new('RGBA', out.size), mask).getchannel('A'))
        out.alpha_composite(lay)
    # the eye
    if c['eye'] is not None:
        E = M['eye']; sheet = img(E['picture']); cw, chh = E['cell'][0] * K, E['cell'][1] * K
        n = min(c['eye'], len(E['states']) - 1); fr = sheet.crop((round((n % E['perRow']) * cw), round((n // E['perRow']) * chh), round((n % E['perRow'] + 1) * cw), round((n // E['perRow'] + 1) * chh)))
        out.alpha_composite(fr, (round((md['eye'][0] - E['center'][0]) * K), round((md['eye'][1] - E['center'][1]) * K)))
    # the gas digits
    if c['peak'] is not None:
        g = md['gas']; n = md['gasN']; pitch = 1.3; t = math.tan(math.radians(8))
        cell = g[2] * K / (n * pitch + 0.5)
        txt = '%.1f' % max(-99.9, min(9.9, c['peak']))
        chars = []
        for ch in txt:
            if ch == '.' and chars and not chars[-1][1]: chars[-1][1] = True; continue
            chars.append([ch if ch in D7 else ' ', False])
        while len(chars) < n: chars.insert(0, [' ', False])
        chars = chars[-n:]
        lay = Image.new('RGBA', out.size, (0, 0, 0, 0)); d = ImageDraw.Draw(lay)
        for j, (ch, dp) in enumerate(chars):
            ox = g[0] * K + (0.25 + j * pitch + (pitch - 1) / 2) * cell; oy = g[1] * K + 0.2 * cell
            Pp = lambda x, y: (ox + (x + (0.85 - y) * t) * cell, oy + y * cell)
            for sg in D7[ch]:
                s = S7[sg]; d.line([Pp(s[0], s[1]), Pp(s[2], s[3])], fill=(255, 82, 18, 255), width=max(1, round(0.13 * cell * 0.92)))
            if dp:
                q = Pp(1.13, 1.62); r = 0.07 * cell; d.ellipse([q[0] - r, q[1] - r, q[0] + r, q[1] + r], fill=(255, 82, 18, 255))
        out.alpha_composite(lay)
    # the name
    st = md['strip']; fp = os.path.join(KIT, 'fonts', 'SwellMarker-400-normal.ttf')
    f = ImageFont.truetype(fp, round(15 * K)); d = ImageDraw.Draw(out)
    d.text(((st[0] + 0.75 * 14) * K, (st[1] + st[3] / 2) * K), c['name'], font=f, fill=(27, 23, 18, 235), anchor='lm')
out.save(OUTP)
print(OUTP, out.size)
