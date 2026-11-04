# key_variants_check.py: picks SwellNine.keySalt (SwellKit.swift), the salt of the hash that gives each button its worn
# key (rkit-key-<state>-a … -f), so that keys standing side by side get different keys (2026-11-04).
#   python3 design/render/key_variants_check.py          the best salt, and each group's keys with it
#   python3 design/render/key_variants_check.py <salt>   the groups with that salt
# The hash must match SwellNine.keyVariant(for:) exactly: the name lowercased and trimmed, a leading "‹ " and trailing
# "…" or "." removed, FNV-1a 32-bit over its UTF-8 starting from 2166136261 ^ salt, modulo the number of variants.
# GROUPS lists the keys shown together (the button's key name, as passed in KeyButtonStyle(key:)); update it when a
# row of keys changes.
import sys

VARIANTS = 'abcdef'
GROUPS = [
    ('shelf', ['Cab IR', 'Amp NAM', 'Help']),
    ('cab routes', ['‹ Record here', 'Import DAW recordings…', 'Re-export a past capture…']),
    ('cab deck', ['Check levels', 'Capture', 'Stop']),
    ('cab results', ['Show in Finder', 'Re-export…', 'Record again']),
    ('cab box', ['Show in Finder', 'Re-export…']),
    ('re-export sheet', ['Cancel', 'Re-export']),
    ('mic role', ['Mic', 'Off']),
    ('daw roles', ['Mic', 'Ref', 'Skip', 'Remove']),
    ('input chips', ['As a mic', 'As the reference', 'Use it as the reference']),
    ('reference', ['None (simplest)', 'Load box line out', 'Reference tap or pad']),
    ('daw route', ['Save test signal…', 'Load settings from a test signal…', 'Make IRs', 'Choose files…']),
    ('welcome', ['Back', 'Next', 'Start', 'Allow recording…', 'Open Privacy & Security']),
    ('help pages', ['Quick start', 'Wiring', 'The reference tap', 'Troubleshooting', 'Done']),
    ('help support', ['Contact Support…', 'Show Log File']),
    ('nam kind', ['Amp only', 'Full chain']),
    ('nam signal', ['Open tone3000.com/capture', 'Find it in Downloads', 'Choose sweep file']),
    ('nam transport', ['Check levels', 'Record', 'Stop']),           # the fallback panels (the cart has its own keys)
    ('nam inputs', ['Use', 'Off']),
    ('nam daw', ['Use', 'Skip', 'Remove', 'Prepare files']),
    ('nam results', ['Show in Finder', 'Open tone3000.com/capture', 'Record again']),
    ('gear preview', ['Capture', 'Check levels', 'Mic', 'Off']),
    ('gear deck', ['Check levels', 'Capture', 'Stop']),
]


def norm(t):
    t = t.lower().strip()
    if t.startswith('‹ '): t = t[2:]
    while t.endswith('…') or t.endswith('.'): t = t[:-1]
    return t


def variant(name, salt):
    h = (2166136261 ^ salt) & 0xFFFFFFFF
    for b in norm(name).encode('utf-8'):
        h = ((h ^ b) * 16777619) & 0xFFFFFFFF
    return VARIANTS[h % len(VARIANTS)]


def clashes(salt):
    n = 0
    for _, g in GROUPS:
        vs = [variant(k, salt) for k in g]
        n += len(vs) - len(set(vs))
    return n


def spread(salt):
    """How unevenly the keys use the six variants (lower is more even)."""
    names = {k for _, g in GROUPS for k in g}
    c = [sum(variant(k, salt) == v for k in names) for v in VARIANTS]
    return max(c) - min(c)


if len(sys.argv) > 1:
    salt = int(sys.argv[1])
else:
    salt = min(range(20000), key=lambda s: (clashes(s), spread(s), s))
print('salt', salt, 'clashes', clashes(salt), 'spread', spread(salt))
for name, g in GROUPS:
    print('  %-16s %s' % (name, '  '.join('%s=%s' % (k, variant(k, salt)) for k in g)))
