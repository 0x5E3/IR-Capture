# ircapture_tape_mock2.py: round 3b layout mockups at the app's default window size (920 x 960 pt, drawn at 1x).
#
# Built from the round 2 CI screenshots (release preview-workshop-look: screenshot-capture.png, screenshot-nam-record.png,
# screenshot-gear.png at 2x) and the new proofs. The deck takes the place of the Set levels and Capture panels; the
# stepper lamps and the pre-flight card share one row above it; the meter bridge stays under it.
#
# CAB IR, worst case: six mics and a reference. The compact modules shrink about 8 % (0.46 of the 2x screenshot instead of
# 0.5) so all seven fit in one row; otherwise the reference wraps to a second row and the page needs about 60 pt more
# than the window has.
#
#   ~/bvenv/bin/python design/render/ircapture_tape_mock2.py <shots dir> <proof dir> <out dir>
import sys, os
from PIL import Image, ImageFilter, ImageDraw

SH, PR, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
os.makedirs(OUT, exist_ok=True)
WX0, WX1, WY0 = 52, 972, 26            # the app window in the 1024 x 768 screenshots
WW, WH = WX1 - WX0, 960
TOP = 182                              # rows kept from the screenshot's top: title bar, shelf, the opening's top edge
IN_X0, IN_X1 = 78 - WX0, 948 - WX0     # the opening's inner width, window coordinates


def gear(box, scale=0.5):
    g = Image.open(os.path.join(SH, 'gear.png')).convert('RGBA').crop(box)
    return g.resize((round(g.width * scale), round(g.height * scale)), Image.LANCZOS)


def shadowed(im, piece, x, y, r=6, dy=5, a=0.5):
    al = piece.split()[3].point(lambda v: int(v * a))
    sh = Image.new('RGBA', piece.size, (0, 0, 0, 0)); sh.putalpha(al); sh = sh.filter(ImageFilter.GaussianBlur(r))
    blk = Image.new('RGBA', piece.size, (0, 0, 0, 255)); blk.putalpha(sh.split()[3])
    im.alpha_composite(blk, (x + 2, y + dy)); im.alpha_composite(piece, (x, y))


def window(shot):
    sc = Image.open(os.path.join(SH, shot)).convert('RGBA').crop((WX0, WY0, WX1, 768))
    im = Image.new('RGBA', (WW, WH), (0, 0, 0, 255))
    top = sc.crop((0, 0, WW, TOP - WY0)); im.paste(top, (0, 0))
    fill = Image.open(os.path.join(SH, 'capture.png')).convert('RGBA').crop((WX0, WY0, WX1, 768))
    mid = fill.crop((0, 312 - WY0, WW, 313 - WY0))       # one row through the opening where it is empty: wall, moulding, floor
    for y in range(TOP - WY0, WH - 14): im.paste(mid, (0, y))
    bot = fill.crop((0, 694 - WY0, WW, 708 - WY0)); im.paste(bot, (0, WH - 14))
    # cover the screenshot's scroll bar on the right of the opening (the mockup has nothing to scroll)
    return im


def deck(png, width):
    d = Image.open(os.path.join(PR, png)).convert('RGBA')
    return d.resize((width, round(d.height * width / d.width)), Image.LANCZOS)


def cab():
    im = window('capture.png')
    y = TOP - WY0 + 14
    step = gear((122, 1930, 986, 2026)); card = gear((664, 2088, 1166, 2300))
    x0 = IN_X0 + 14
    shadowed(im, step, x0, y + 12, r=4, dy=3, a=0.4)
    cx = IN_X1 - 14 - card.width
    shadowed(im, card.rotate(-1.2, resample=Image.BICUBIC, expand=True), cx, y - 4, r=5)
    y += max(step.height + 12, card.height) + 8
    dk = deck('tape-reel-40.png', IN_X1 - IN_X0 - 20)
    shadowed(im, dk, IN_X0 + 10, y, r=8, dy=8, a=0.55)
    y += dk.height + 6
    s = 0.46
    mods = [gear((138 + i * 268, 794, 378 + i * 268, 1229), s) for i in range(6)] + [gear((138, 1252, 378, 1581), s)]
    gap = 8; tw = sum(m.width for m in mods) + gap * (len(mods) - 1)
    x = (WW - tw) // 2
    for m in mods:
        shadowed(im, m, x, y, r=4, dy=3, a=0.45); x += m.width + gap
    y += mods[0].height
    print('cab: content ends at %d pt of %d (bottom moulding from %d)' % (y, WH, WH - 26))
    im.convert('RGB').save(os.path.join(OUT, 'mock-cab-920x960.png'))
    return y


def nam():
    im = window('nam-record.png')
    y = TOP - WY0 + 14
    step = gear((122, 3312, 1100, 3416))
    shadowed(im, step, IN_X0 + 14, y, r=4, dy=3, a=0.4)
    y += step.height + 14
    dk = deck('tape-cart-40.png', IN_X1 - IN_X0 - 20)
    shadowed(im, dk, IN_X0 + 10, y, r=8, dy=8, a=0.55)
    y += dk.height + 8
    lad = gear((122, 3437, 1802, 3822))
    lad = lad.resize((IN_X1 - IN_X0 - 40, round(lad.height * (IN_X1 - IN_X0 - 40) / lad.width)), Image.LANCZOS)
    shadowed(im, lad, IN_X0 + 20, y, r=5, dy=4, a=0.45)
    y += lad.height
    print('nam: content ends at %d pt of %d' % (y, WH))
    im.convert('RGB').save(os.path.join(OUT, 'mock-nam-920x960.png'))


cab(); nam()
