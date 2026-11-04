from PIL import Image, ImageFilter
import sys
S = '/root/shots/'; T = '/root/tape/'


def window(shot, deck_png, under_png, under_scale, out, fill_row, head_box, gap=18):
    sc = Image.open(S + shot).convert('RGBA')
    top = sc.crop((0, 0, 1024, 182))                       # menu bar, shelf, the opening's top, the first card's edge
    head = sc.crop(head_box)                    # the stepper strip
    bottom = sc.crop((0, 676, 1024, 768))                  # the opening's bottom, window edge, dock
    bg = sc.getpixel((60, 400))                            # the wall beside the opening
    inner = sc.getpixel((150, 240))
    deck = Image.open(T + deck_png).convert('RGBA')
    dw = 820; deck = deck.resize((dw, round(deck.height * dw / deck.width)), Image.LANCZOS)
    und = Image.open(S + under_png).convert('RGBA')
    und = und.resize((round(und.width * under_scale), round(und.height * under_scale)), Image.LANCZOS)
    H = 182 + head.height + gap + deck.height + gap + und.height + 24 + (768 - 676)
    im = Image.new('RGBA', (1024, H), (0, 0, 0, 255))
    # extend the window body: repeat a 1 px slice of the screenshot's middle rows down the page
    mid = sc.crop((0, fill_row, 1024, fill_row + 1))
    for y in range(182, H - (768 - 676)): im.paste(mid, (0, y))
    im.paste(top, (0, 0)); im.paste(head, (0, 182))
    y = 182 + head.height + gap
    sh = Image.new('RGBA', deck.size, (0, 0, 0, 0)); a = deck.split()[3].point(lambda v: int(v * 0.55))
    sh.putalpha(a); sh = sh.filter(ImageFilter.GaussianBlur(8))
    shadow = Image.new('RGBA', deck.size, (0, 0, 0, 255)); shadow.putalpha(sh.split()[3])
    x = (1024 - dw) // 2 - 6
    im.alpha_composite(shadow, (x + 3, y + 8)); im.alpha_composite(deck, (x, y))
    y += deck.height + gap
    im.alpha_composite(und, (x + 6, y))
    im.paste(bottom, (0, H - (768 - 676)))
    im.convert('RGB').save(T + out, quality=92)
    print(out, im.size)


window('capture.png', 'tape-reel-40.png', 'meters4.png', 0.48, 'mock-cab.png', 316, (0, 182, 1024, 312))
window('nam-record.png', 'tape-cassette-40.png', 'ledladders.png', 0.47, 'mock-nam.png', 244, (0, 182, 1024, 238))
