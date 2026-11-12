# ircapture_nammeters_mock.py: the NAM meter bridge as the app lays it out (RackNAMMeters.swift), for a check before CI.
#
#   ~/bvenv/bin/python design/render/ircapture_nammeters_mock.py <Resources/SwellKit> <out.png>
#
# The gear sheet's three inputs (Line out OK at -8.2, SM57 12 dB low at -20.6, R121 clipped at -0.2) and a blank plate:
# the bars up to the level and the peak-hold bar shown through their columns, the digits' lit segments through their
# outlines (grown 1.6 pt, as the app strokes them), the LEDs, the names on the strips (not lettered here).
import sys, os, json
from PIL import Image, ImageDraw, ImageFilter

KIT, OUT = sys.argv[1], sys.argv[2]
J = json.load(open(os.path.join(KIT, 'irc-rack.json')))
u = J['units']['nammeters']; s = J['pxPerPoint']; nm = u['nammeters']
pic = lambda n: Image.open(os.path.join(KIT, 'pictures', n + '.webp')).convert('RGBA')
SEG7 = {'0': 'abcdef', '1': 'bc', '2': 'abdeg', '3': 'abcdg', '4': 'bcfg', '5': 'acdfg', '6': 'acdefg', '7': 'abc',
        '8': 'abcdefg', '9': 'abcdfg', '-': 'g', ' ': ''}


def bars(db, n):
    return max(0, min(n, int(round((db - nm['db0']) / nm['dbStep']))))


def cell_text(db, n):
    if db < -99.9: return [(' ', False)] * (n - 3) + [('-', False)] * 3
    t = '%.1f' % min(0.0, db)
    if t == '-0.0': t = '0.0'
    cells = []
    for c in t:
        if c == '.' and cells: cells[-1] = (cells[-1][0], True)
        else: cells.append((c, False))
    return [(' ', False)] * (n - len(cells)) + cells[-n:]


def lamps(peak, clipped):
    ch = -8.0 - peak; on = set()
    if clipped: on.add(3)
    if peak < -60 or ch > 3: on.add(0)
    elif ch < -3: on.add(2)
    elif not clipped: on.add(1)
    return on


def masked(im, layer, shapes):
    L = u['layers'][layer]; lp = pic(L['picture'])
    full = Image.new('RGBA', im.size, (0, 0, 0, 0))
    full.alpha_composite(lp, (int(round(L['rect'][0] * s)), int(round(L['rect'][1] * s))))
    m = Image.new('L', im.size, 0); d = ImageDraw.Draw(m)
    for kind, v in shapes:
        if kind == 'rect': d.rectangle(v, fill=255)
        else: d.polygon(v, fill=255, outline=255, width=max(1, int(round(3.2 * s))))
    a = full.getchannel('A'); a = Image.fromarray(__import__('numpy').minimum(__import__('numpy').asarray(a), __import__('numpy').asarray(m)))
    full.putalpha(a)
    im.alpha_composite(full)


chans = [('Line out', -8.2, -9.6, False), ('SM57 cap edge', -20.6, -23.1, False), ('R121', -0.2, -1.4, True)]
im = pic(u['picture'])
for i in range(len(nm['modules'])):
    if i >= len(chans):
        L = u['layers']['b%d' % i]; im.alpha_composite(pic(L['picture']), (int(round(L['rect'][0] * s)), int(round(L['rect'][1] * s)))); continue
    md = nm['modules'][i]; _, peak, level, clip = chans[i]
    n = len(md['bars'])
    shown = set(range(bars(level, n))); h = bars(peak, n) - 1
    if h >= 0: shown.add(h)
    masked(im, 'm%d-bars' % i, [('rect', [md['bars'][b][0] * s, (md['bars'][b][1] - 5) * s,
                                          (md['bars'][b][0] + md['bars'][b][2]) * s, (md['bars'][b][1] + md['bars'][b][3] + 5) * s]) for b in shown])
    segs = []
    for k, (c, dp) in enumerate(cell_text(peak, len(md['cells']))):
        cell = md['cells'][k]
        for ch in SEG7[c]: segs.append(cell['abcdefg'.index(ch)])
        if dp: segs.append(cell[7])
    masked(im, 'm%d-dig' % i, [('poly', [(x * s, y * s) for x, y in md['segs'][g]]) for g in segs])
    for k in lamps(peak, clip):
        L = u['layers']['m%d-l%d' % (i, k)]; im.alpha_composite(pic(L['picture']), (int(round(L['rect'][0] * s)), int(round(L['rect'][1] * s))))
im.convert('RGB').save(OUT)
print(OUT, im.size)
