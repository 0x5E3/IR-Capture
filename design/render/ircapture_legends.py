"""IR Capture's printed keys (11-11, Lowell: "key legends rendered on the keys", as the bench's UNLOCK/REMOVE).

One table, read by the render (ircapture_kit.py legend-<id>), the post (ircapture_kit_post.py writes irc-legends.json)
and so the app: each key name the app passes (KeyButtonStyle(key:)) is looked up here; a name with a printed key is drawn
as that picture at its own size, its label kept for VoiceOver only; any other name keeps the blank cap and app text.

Each printed key is rendered at one scale, 12 pt a cm on screen (PT_PER_CM): a standard key's cap 1.8 cm tall (the key
27 pt with its bezel), its capitals 0.62 cm (7.4 pt); a big key's cap 2.9 cm (40 pt), its capitals 0.9 cm (10.8 pt).
No capital under 6 pt (MIN_CAP_PT). The cap's width is the legend's own plus its margins.

LEGENDS: id -> (legend, size, [key names]). The key names are exactly the app's `key:` strings; the wear (which of the
six key looks) is picked by the same hash as SwellNine.keyVariant(for:) on the first name, so a key keeps its wear.
Wording marked (?) shortens the app's label: Lowell's call (the full label stays as the help tag).
"""

PT_PER_CM = 12.0
MIN_CAP_PT = 6.0
SIZES = {
    'std': dict(cap_h=1.8, cap_cm=0.62, margin=0.55, min_w=2.4),
    'big': dict(cap_h=2.9, cap_cm=0.90, margin=0.95, min_w=6.6),
}
TRACK = 0.12

LEGENDS = {
    # the shelf
    'cab-ir':        ('CAB IR', 'std', ['Cab IR']),
    'amp-nam':       ('AMP NAM', 'std', ['Amp NAM']),
    'help':          ('HELP', 'std', ['Help']),
    # transport
    'check':         ('CHECK LEVELS', 'std', ['Check levels']),
    'check-big':     ('CHECK LEVELS', 'big', ['Check levels']),
    'capture':       ('CAPTURE', 'std', ['Capture']),
    'capture-big':   ('CAPTURE', 'big', ['Capture']),
    'record-big':    ('RECORD', 'big', ['Record']),
    'stop':          ('STOP', 'std', ['Stop']),
    'make-irs-big':  ('MAKE IRS', 'big', ['Make IRs']),
    'prepare-big':   ('PREPARE', 'big', ['Prepare files']),                     # (?) Prepare files
    'record-again':  ('RECORD AGAIN', 'std', ['Record again']),
    # roles and choices
    'mic':           ('MIC', 'std', ['Mic']),
    'off':           ('OFF', 'std', ['Off']),
    'ref':           ('REF', 'std', ['Ref']),
    'skip':          ('SKIP', 'std', ['Skip']),
    'use':           ('USE', 'std', ['Use']),
    'remove':        ('REMOVE', 'std', ['Remove']),
    'amp-only':      ('AMP ONLY', 'std', ['Amp only']),
    'full-chain':    ('FULL CHAIN', 'std', ['Full chain']),
    'ref-none':      ('NONE', 'std', ['None (simplest)']),                     # (?)
    'ref-loadbox':   ('LOAD BOX', 'std', ['Load box line out']),               # (?)
    'ref-tap':       ('TAP OR PAD', 'std', ['Reference tap or pad']),          # (?)
    'as-mic':        ('AS MIC', 'std', ['As a mic']),                          # (?)
    'as-ref':        ('AS REF', 'std', ['As the reference', 'Use it as the reference']),   # (?) "(detected)" moves to the chip's line
    # routes and files
    'record-here':   ('‹ RECORD HERE', 'std', ['‹ Record here']),
    'import-daw':    ('IMPORT DAW', 'std', ['Import DAW recordings…']),        # (?)
    'reexport-past': ('RE-EXPORT OLD', 'std', ['Re-export a past capture…']),  # (?)
    'finder':        ('FINDER', 'std', ['Show in Finder']),                    # (?) as the shelf sheet's FINDER
    'reexport':      ('RE-EXPORT', 'std', ['Re-export…', 'Re-export']),
    'change':        ('CHANGE', 'std', ['Change…']),
    'choose-files':  ('CHOOSE FILES', 'std', ['Choose files…']),
    'choose-file':   ('CHOOSE FILE', 'std', ['Choose sweep file']),            # (?) also "Choose a different file…"
    'save-signal':   ('SAVE SIGNAL', 'std', ['Save test signal…']),            # (?)
    'load-signal':   ('LOAD SIGNAL', 'std', ['Load settings from a test signal…']),   # (?)
    'downloads':     ('DOWNLOADS', 'std', ['Find it in Downloads']),           # (?)
    'upload-page':   ('UPLOAD PAGE', 'std', ['Open tone3000.com/capture']),    # (?) no brand on gear
    'midi-setup':    ('AUDIO SETUP', 'std', ['Open Audio MIDI Setup']),        # (?)
    'privacy':       ('PRIVACY', 'std', ['Open Privacy & Security']),          # (?)
    'allow-rec':     ('ALLOW', 'std', ['Allow recording…']),                   # (?)
    # sheets and help
    'cancel':        ('CANCEL', 'std', ['Cancel']),
    'done':          ('DONE', 'std', ['Done']),
    'back':          ('BACK', 'std', ['Back']),
    'next':          ('NEXT', 'std', ['Next']),
    'start':         ('START', 'std', ['Start']),
    'support':       ('SUPPORT', 'std', ['Contact Support…']),                 # (?)
    'log-file':      ('LOG FILE', 'std', ['Show Log File']),                   # (?)
    'help-quick':    ('QUICK START', 'std', ['Quick start']),
    'help-wiring':   ('WIRING', 'std', ['Wiring']),
    'help-tap':      ('REF TAP', 'std', ['The reference tap']),                # (?)
    'help-trouble':  ('TROUBLE', 'std', ['Troubleshooting']),                  # (?)
    # (11-12) the fourth proof's rack units (approved): rendered as part of their unit (ircapture_rack_layers.py), not
    # as printed keys of their own. The files unit's latching keys and the plotter's PRINT
    'f-universal':   ('UNIVERSAL', 'std', ['Universal']),
    'f-allrates':    ('ALL RATES', 'std', ['All sample rates']),
    'f-iridium':     ('IRIDIUM', 'std', ['Strymon Iridium']),
    'f-minphase':    ('MIN PHASE', 'std', ['Minimum-phase versions']),
    'f-mixes':       ('MIXES', 'std', ['Mixes of two mics']),
    'print':         ('PRINT', 'std', ['Print']),
    # the file options unit's custom files (latching); figures keep their fill (ircapture_rack.key)
    'c-441':         ('44.1', 'std', ['custom 44.1']),
    'c-48':          ('48', 'std', ['custom 48']),
    'c-882':         ('88.2', 'std', ['custom 88.2']),
    'c-96':          ('96', 'std', ['custom 96']),
    'c-full':        ('FULL', 'std', ['custom FULL']),
    'c-1024':        ('1024', 'std', ['custom 1024']),
    'c-2048':        ('2048', 'std', ['custom 2048']),
    'c-4096':        ('4096', 'std', ['custom 4096']),
    'c-16':          ('16', 'std', ['custom 16']),
    'c-24':          ('24', 'std', ['custom 24']),
    'c-32f':         ('32 FLOAT', 'std', ['custom 32 FLOAT']),
    'c-set':         ('KEEP TIMING', 'std', ['custom KEEP TIMING']),
    'c-individual':  ('EACH MIC', 'std', ['custom EACH MIC']),
    # (11-13) the fifth proof's units (approved): the DAW route's track sheet and its last key, the re-export's past
    # capture (each key's wear as the proof's: its name picks it)
    'r-add-files':   ('ADD FILES', 'std', ['Choose files…']),
    'r-clear':       ('CLEAR', 'std', ['Clear the files']),
    'r-make-irs':    ('MAKE IRS', 'std', ['Make IRs']),
    'r-choose':      ('CHOOSE', 'std', ['Choose a past capture']),
}
# the ids above that are rendered only inside a rack unit (ircapture_kit.py's `legends` and ircapture_lettering_post.py
# skip them: they have no printed-key picture of their own)
RACK_ONLY = {k for k in LEGENDS if k.startswith(('f-', 'c-', 'r-')) or k == 'print'}

KEY_SALT = 14007
VARIANTS = 'abcdef'


def norm(t):
    t = t.lower().strip()
    if t.startswith('‹ '): t = t[2:]
    while t.endswith('…') or t.endswith('.'): t = t[:-1]
    return t


def variant(name, salt=KEY_SALT):
    """SwellNine.keyVariant(for:) exactly (key_variants_check.py's)."""
    h = (2166136261 ^ salt) & 0xFFFFFFFF
    for b in norm(name).encode('utf-8'):
        h = ((h ^ b) * 16777619) & 0xFFFFFFFF
    return VARIANTS[h % len(VARIANTS)]


def cap_pt(lid):
    return SIZES[LEGENDS[lid][1]]['cap_cm'] * PT_PER_CM


if __name__ == '__main__':
    for lid, (txt, sz, names) in LEGENDS.items():
        print('%-14s %-14s %s  %.1f pt  wear %s  %s' % (lid, txt, sz, cap_pt(lid), variant(names[0]), ' / '.join(names)))
    assert all(cap_pt(l) >= MIN_CAP_PT for l in LEGENDS)
