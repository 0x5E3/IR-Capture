# ircapture_patch_mock.py: the patch unit as the app lays it out (RackPatch.swift), for a check before CI.
#
#   ~/bvenv/bin/python design/render/ircapture_patch_mock.py <Resources/SwellKit> <out.png>
#
# Two units stacked: bank 0 of a six-input interface (inputs 1 to 3 MIC, 6 REF, 7 and 8 plugged) and bank 1 of an
# 18-input interface (inputs 9 to 16, input 12 MIC).
import sys, os, json
from PIL import Image

KIT, OUT = sys.argv[1], sys.argv[2]
J = json.load(open(os.path.join(KIT, 'irc-rack.json')))
u = J['units']['patch']; s = J['pxPerPoint']
pic = lambda n: Image.open(os.path.join(KIT, 'pictures', n + '.webp')).convert('RGBA')


def unit(bank, count, roles):
    im = pic(u['picture'])
    n = u['patch']['n']
    on = []
    for i in range(n):
        ch = bank * n + i
        if bank > 0: on.append('n%d-b%d' % (i, bank))
        if ch >= count: on.append('p%d' % i); continue
        r = roles.get(ch, 'off')
        if r != 'off': on.append('t%d-%s' % (i, r))
    for k in on:
        L = u['layers'][k]; x, y = int(round(L['rect'][0] * s)), int(round(L['rect'][1] * s))
        im.alpha_composite(pic(L['picture']), (x, y))
    return im


a = unit(0, 6, {0: 'mic', 1: 'mic', 2: 'mic', 5: 'ref'})
b = unit(1, 18, {11: 'mic'})
out = Image.new('RGBA', (a.size[0], a.size[1] + b.size[1]), (6, 6, 6, 255))
out.alpha_composite(a, (0, 0)); out.alpha_composite(b, (0, a.size[1]))
out.convert('RGB').save(OUT)
print(OUT, out.size)
