"""Every post script's WEBP goes out lossless (157th chat; Lowell 11-06: "Why not 100%? Does anyone care about disk
space?", the pictures in Git LFS).

Importing this module is enough: it wraps PIL's Image.save so any WEBP written (to a path ending .webp, or with
format 'WEBP', a file or a BytesIO) is lossless with exact RGB under transparent pixels, whatever quality the script
asks for. Lossy WEBP keeps colour at half resolution at any quality (the 156th chat measured q86 34 dB, q100 37 dB on the
red flake crop), which is the smoothing Lowell saw.

    import webp_out            # first thing after the PIL import, in any design/render/*_post*.py

POST_LOSSY=1 restores each script's own lossy settings (its size caps and quality steps then work as they did).
WEBP_EFFORT (default 90) and WEBP_METHOD (default 4) set the lossless encoder's effort: the pixels are exact either way;
100 and 6 are about 7 times slower for under 1 % fewer bytes on textured renders (measured 2000 x 1500, 11-07).

webp_out.LOSSLESS says which: scripts that search for a quality under a byte cap check it and encode once instead.
"""
import os
from PIL import Image

LOSSLESS = os.environ.get('POST_LOSSY') != '1'
EFFORT = int(os.environ.get('WEBP_EFFORT', '90'))
METHOD = int(os.environ.get('WEBP_METHOD', '4'))
_LOSSY_KEYS = ('quality', 'alpha_quality', 'method', 'lossless', 'exact', 'minimize_size', 'kmin', 'kmax')


def _is_webp(fp, format):
    if format: return str(format).upper() == 'WEBP'
    return isinstance(fp, (str, os.PathLike)) and os.fspath(fp).lower().endswith('.webp')


def options():
    """The lossless encoder's keywords, for scripts that call save themselves."""
    return dict(lossless=True, quality=EFFORT, method=METHOD, exact=True)


if LOSSLESS and not getattr(Image.Image.save, '_webp_out', False):
    _save = Image.Image.save

    def save(self, fp, format=None, **params):
        if _is_webp(fp, format):
            for k in _LOSSY_KEYS: params.pop(k, None)
            params.update(options())
            im = self if self.mode in ('RGB', 'RGBA') else self.convert('RGBA' if 'A' in self.mode or self.mode == 'P' else 'RGB')
            return _save(im, fp, format or 'WEBP', **params)
        return _save(self, fp, format, **params)

    save._webp_out = True
    Image.Image.save = save
