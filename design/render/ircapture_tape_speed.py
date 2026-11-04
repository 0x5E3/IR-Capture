# ircapture_tape_speed.py: reel speed tied to the sweep (Phase 7 round 3b concept, 2026-11-03).
#
# Lowell, 11-03: reel speed "tied to the sweep freq". The tape speed at the heads follows the sweep's pitch on an octave
# scale: 3 3/4 in/s at 20 Hz, 15 in/s at 22 kHz. A log sweep climbs octaves at a steady rate, so each sweep is a steady
# acceleration; in the gap after it the reels coast back down (time constant about 0.35 s) while the room tail rings
# out. During the room-noise check the reels stand still with the record jewel lit.
#
# Each reel turns at tape speed / its pack radius, so the emptying supply reel speeds up through the take and the
# filling take-up reel slows down, as on a real machine. The packs show the capture's progress: tape moved so far over
# the total for the take. The schedule is known before the take starts, so the total is exact and the packs end
# exactly full and empty. (The tape lengths are not real: 41 s at these speeds would hardly move a real 7 inch pack.)
#
# This script writes the preview: the supply reel's rotation sprite (ircapture_tape_spin.py) driven by the model, as an
# animation and a frame strip, plus the model as JSON for the app.
#
#   ~/bvenv/bin/python design/render/ircapture_tape_speed.py <spin dir> <out dir>
import sys, os, math, json
import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
FONTS = os.path.join(HERE, '..', '..', 'Resources', 'SwellKit', 'fonts')

# the capture schedule (reference/ircapture.py SweepSpec defaults, plus the app's 2 s room-noise check before it)
NOISE, LEAD, SWEEP, GAP, N = 2.0, 1.0, 6.0, 2.0, 5
F1, F2 = 20.0, 22000.0
IPS = 2.54                               # cm per inch
V_LO, V_HI = 3.75 * IPS, 15.0 * IPS      # cm/s at the heads: 3 3/4 and 15 in/s
TAU = 0.35                               # the coast-down after each sweep, s
HUB, FULL = 3.0, 8.3                     # pack radii, cm (ircapture_tape.REEL)
FPS = 30


def phase(t):
    """('noise' | 'lead' | 'sweep' | 'gap', sweep index, time into that part)."""
    if t < NOISE: return 'noise', -1, t
    t -= NOISE
    if t < LEAD: return 'lead', -1, t
    t -= LEAD
    k = int(t // (SWEEP + GAP)); u = t - k * (SWEEP + GAP)
    if k >= N: return 'end', N, u
    return ('sweep', k, u) if u < SWEEP else ('gap', k, u - SWEEP)


def freq(t):
    p, k, u = phase(t)
    return F1 * (F2 / F1) ** (u / SWEEP) if p == 'sweep' else None


def speed(t):
    """Tape speed at the heads, cm/s."""
    p, k, u = phase(t)
    if p == 'noise' or p == 'end': return 0.0
    if p == 'lead': return V_LO * min(1.0, u / 0.4)            # starting up
    if p == 'sweep': return V_LO + (V_HI - V_LO) * u / SWEEP    # octaves above 20 Hz, over the sweep's 10.1 octaves
    return V_LO + (V_HI - V_LO) * math.exp(-u / TAU)


TOTAL_T = NOISE + LEAD + N * (SWEEP + GAP)
_ts = np.arange(0, TOTAL_T + 1e-9, 1 / 600)
_vs = np.array([speed(t) for t in _ts])
_cum = np.concatenate([[0], np.cumsum((_vs[1:] + _vs[:-1]) / 2 / 600)])
TAPE = _cum[-1]


def progress(t): return float(np.interp(t, _ts, _cum) / TAPE)


def radii(p):
    A = FULL * FULL - HUB * HUB
    return math.sqrt(HUB * HUB + A * (1 - p)), math.sqrt(HUB * HUB + A * p)


def font(n, px): return ImageFont.truetype(os.path.join(FONTS, n), px)


def main(spin, out):
    os.makedirs(out, exist_ok=True)
    meta = json.load(open(os.path.join(spin, 'spin.json')))
    NF, SPAN, BL, RP = meta['frames'], meta['span_deg'], meta['blur_deg'], meta['pack_r_cm']
    step = SPAN / NF
    S = 220
    sharp = [Image.open(os.path.join(spin, 'spin-sharp-%02d.png' % i)).convert('RGB').resize((S, S), Image.LANCZOS) for i in range(NF)]
    blur = [Image.open(os.path.join(spin, 'spin-blur-%02d.png' % i)).convert('RGB').resize((S, S), Image.LANCZOS) for i in range(NF)]

    def sprite(theta_deg, dps):
        """theta: the reel's angle; dps: its speed in deg/s. Blurred frames blend in as a frame's turn passes the blur arc."""
        i = int(round((theta_deg % SPAN) / step)) % NF
        w = min(1.0, max(0.0, (dps / FPS - 0.5 * BL) / (0.5 * BL)))
        return sharp[i] if w == 0 else Image.blend(sharp[i], blur[i], w)

    W_, H_ = 760, 300
    f_b = font('Barlow-600-normal.ttf', 15); f_s = font('Barlow-400-normal.ttf', 13); f_c = font('BarlowSemiCondensed-600-normal.ttf', 12)
    bg, ink, dim, acc = (30, 27, 24), (230, 222, 205), (150, 140, 124), (232, 144, 46)
    T0, T1 = 0.0, NOISE + LEAD + 2 * (SWEEP + GAP)          # the preview: noise check, lead, two sweeps and their gaps
    gx0, gx1, gy0, gy1 = 270, W_ - 24, 66, 236
    vmax = V_HI * 1.08
    X = lambda t: gx0 + (gx1 - gx0) * (t - T0) / (T1 - T0)
    Y = lambda v: gy1 - (gy1 - gy0) * v / vmax

    def base():
        im = Image.new('RGB', (W_, H_), bg); d = ImageDraw.Draw(im)
        d.text((gx0, 14), 'Tape speed follows the sweep', font=f_b, fill=ink)
        d.text((gx0, 36), '3 3/4 in/s at 20 Hz, 15 in/s at 22 kHz; the reels coast down in each gap', font=f_s, fill=dim)
        for v, lab in ((V_LO, '3 3/4'), (7.5 * IPS, '7 1/2'), (V_HI, '15 in/s')):
            d.line([(gx0, Y(v)), (gx1, Y(v))], fill=(52, 47, 41)); d.text((gx1 - f_c.getlength(lab), Y(v) - 15), lab, font=f_c, fill=dim)
        tt = np.arange(T0, T1, 1 / 60); pts = [(X(t), Y(speed(t))) for t in tt]
        d.line(pts, fill=(120, 110, 96), width=2)
        for t, lab in ((0, 'NOISE'), (NOISE, ''), (NOISE + LEAD, 'SWEEP 1 (discarded)'), (NOISE + LEAD + SWEEP + GAP, 'SWEEP 2')):
            d.line([(X(t), gy0), (X(t), gy1)], fill=(60, 54, 47)); d.text((X(t) + 3, gy1 + 6), lab, font=f_c, fill=dim)
        return im

    B = base()
    theta = 0.0; frames = []
    n = int((T1 - T0) * FPS)
    for k in range(n):
        t = T0 + k / FPS
        p = progress(t); rs, rt = radii(p)
        v = speed(t); w_rad = v / rs                       # the supply reel (its real pack radius sets the speed)
        dps = math.degrees(w_rad)
        theta += dps / FPS
        im = B.copy(); d = ImageDraw.Draw(im)
        im.paste(sprite(theta, dps), (24, 40))
        d.line([(X(t), gy0), (X(t), gy1)], fill=acc, width=2)
        d.ellipse([X(t) - 4, Y(v) - 4, X(t) + 4, Y(v) + 4], fill=acc)
        ph, kk, u = phase(t); f = freq(t)
        state = {'noise': 'Room-noise check: reels still', 'lead': 'Starting', 'gap': 'Gap: room tail', 'sweep': 'Sweep'}.get(ph, '')
        if f: state += '  %s' % (('%.0f Hz' % f) if f < 1000 else ('%.1f kHz' % (f / 1000)))
        d.text((24, 270), state, font=f_s, fill=ink)
        d.text((gx0, 270), '%.1f in/s   supply reel %.0f rpm' % (v / IPS, dps / 6), font=f_s, fill=dim)
        frames.append(im)
    frames[0].save(os.path.join(out, 'reel-speed.webp'), save_all=True, append_images=frames[1:], duration=int(1000 / FPS), loop=0, quality=72, method=4)
    # the strip: eight moments through the first sweep and its gap
    ts = [NOISE + LEAD + x for x in (0.0, 1.5, 3.0, 4.5, 5.9, 6.3, 7.0, 7.9)]
    cell = 170; st = Image.new('RGB', (cell * len(ts) + 24, cell + 70), bg); d = ImageDraw.Draw(st)
    for i, t in enumerate(ts):
        fr = frames[int(round((t - T0) * FPS))].crop((24, 40, 24 + S, 40 + S)).resize((cell - 10, cell - 10), Image.LANCZOS)
        st.paste(fr, (12 + i * cell + 5, 12))
        v = speed(t); f = freq(t)
        lab = ('%.0f Hz' % f if f < 1000 else '%.1f kHz' % (f / 1000)) if f else 'gap +%.1f s' % (t - NOISE - LEAD - SWEEP)
        d.text((12 + i * cell + 8, cell + 8), lab, font=f_b, fill=ink)
        d.text((12 + i * cell + 8, cell + 30), '%.1f in/s' % (v / IPS), font=f_s, fill=dim)
    st.save(os.path.join(out, 'reel-speed-strip.png'))
    model = {'note': 'Tape speed at the heads, tied to the sweep. See design/render/ircapture_tape_speed.py.',
             'v_lo_cm_s': V_LO, 'v_hi_cm_s': V_HI, 'coast_tau_s': TAU, 'schedule_s': {'noise': NOISE, 'lead': LEAD, 'sweep': SWEEP, 'gap': GAP, 'sweeps': N},
             'tape_total_cm': float(round(TAPE, 1)), 'pack_cm': {'hub': HUB, 'full': FULL},
             'max_reel_rpm': float(round(max(math.degrees(speed(t) / radii(progress(t))[0]) / 6 for t in _ts[::60]), 1))}
    json.dump(model, open(os.path.join(out, 'reel-speed-model.json'), 'w'), indent=1)
    print(model)


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
