# The toggle proof (11-13, eleventh chat): the bat toggles as built against longer, wider-thrown bats, with and
# without a push-on cream cap. Not a unit of the app.
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ircapture_rack as R
from ircapture_rack import *

VARS = [('A', 2.2, 24, ''), ('B', 2.9, 34, ''), ('C', 2.9, 34, '#e2d6bb')]


def lab():
    K.set_seed('rack-tgl-lab')
    s, cam, h = unit_scene(4)
    backing(h)
    rack_panel(4, 'black', 'tgllab')
    for gi, (tag, L, th, tip) in enumerate(VARS):
        R.TGL.update(L=L, throw=th, tip=tip)
        x0 = -19.0 + gi * 7.6
        engrave(tag, x0 + 2.4, 6.3, 0.62)
        for j, p in enumerate((1, 0, -1)):
            with moved(x0 + j * 2.4, 3.0, 0): toggle(p)
        engrave('MIC', x0, 0.4, 0.44, track=0.12); engrave('OFF', x0 + 2.4, 0.4, 0.44, track=0.12); engrave('REF', x0 + 4.8, 0.4, 0.44, track=0.12)
        xs = x0 + 2.4
        sc = 0.78 if tag == 'A' else 0.9
        engrave('MIC', xs - 1.6, -1.6, 0.44, track=0.12); engrave('OFF', xs, -1.6, 0.44, track=0.12); engrave('REF', xs + 1.6, -1.6, 0.44, track=0.12)
        for j, p in enumerate((-1, 0, 1, 0)):
            with moved(xs, -2.9 - j * 1.3, 0): side_toggle(p, sc)
    shoot(s, cam, 'toggle-lab', PW, h)


lab()
