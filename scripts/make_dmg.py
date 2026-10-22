#!/usr/bin/env python3
"""Builds dist/IR-Capture.dmg: the app, an Applications shortcut, the Quick start PDF, and a background
with a "drag to Applications" arrow. Runs on macOS (dmgbuild drives hdiutil; no Finder scripting needed).

  python3 scripts/make_dmg.py "dist/IR Capture.app" "dist/Quick start.pdf" dist/IR-Capture.dmg
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

W, H = 640, 400


def font(size, bold=False):
    for p in (["/System/Library/Fonts/Supplemental/Arial Bold.ttf"] if bold else []) + [
            "/System/Library/Fonts/Supplemental/Arial.ttf", "/System/Library/Fonts/Helvetica.ttc",
            "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" if bold else "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"]:
        try:
            return ImageFont.truetype(p, size)
        except OSError:
            continue
    return ImageFont.load_default()


def background(path: Path, scale: int):
    img = Image.new("RGB", (W * scale, H * scale), (247, 244, 238))
    d = ImageDraw.Draw(img)
    s = scale
    lamp = (232, 150, 46)
    d.rectangle([0, 0, W * s, 6 * s], fill=lamp)
    d.text((W * s / 2, 44 * s), "Drag IR Capture to Applications", fill=(40, 36, 32), font=font(22 * s, True), anchor="mm")
    d.text((W * s / 2, 72 * s), "Then open it from Applications. The Quick start has the wiring pictures.",
           fill=(110, 104, 96), font=font(13 * s), anchor="mm")
    # arrow between the two icons (icons sit at x=160 and x=480, y=190)
    y = 190 * s
    d.line([(250 * s, y), (382 * s, y)], fill=lamp, width=6 * s)
    d.polygon([(392 * s, y), (372 * s, y - 14 * s), (372 * s, y + 14 * s)], fill=lamp)
    d.text((W * s / 2, 378 * s), "Swell Amplification · swellamps.com", fill=(150, 144, 136), font=font(11 * s), anchor="mm")
    img.save(path)


def main():
    app, pdf, out = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
    bg = out.parent / "dmg-background.png"
    background(bg, 1)
    background(out.parent / "dmg-background@2x.png", 2)
    if "--background-only" in sys.argv:
        return
    import dmgbuild
    files = [str(app)] + ([str(pdf)] if pdf.exists() else [])
    settings = {
        "files": files,
        "symlinks": {"Applications": "/Applications"},
        "background": str(bg),
        "icon_size": 104,
        "text_size": 13,
        "window_rect": ((200, 140), (W, H)),
        "icon_locations": {app.name: (160, 190), "Applications": (480, 190), pdf.name: (320, 300)},
        "default_view": "icon-view",
        "show_status_bar": False, "show_tab_view": False, "show_toolbar": False, "show_pathbar": False, "show_sidebar": False,
        "format": "UDZO",
        "filesystem": "HFS+",
    }
    out.unlink(missing_ok=True)
    dmgbuild.build_dmg(str(out), app.stem, settings=settings)
    print("built", out)


if __name__ == "__main__":
    main()
