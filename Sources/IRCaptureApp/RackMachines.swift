#if os(macOS)
import SwiftUI
import IRCaptureCore

// RackMachines.swift: the recorders as rack units (Phase 7a). Cab IR's reel deck (8U, the second proof's, approved) and
// Amp NAM's cart machine (3U, the third proof's, approved), rendered straight on at the bay's scale
// (design/render/ircapture_rack_layers.py `deck` and `cart`, posted by ircapture_rack_post.py into irc-rack.json).
//
// The deck is its base picture (everything that stands still: plate, turntables, heads, guides, the tape through the
// heads, the counter with blank drums, the keys up, REC dark) with each reel laid over it in layers, as the 11-04 deck
// (TapeDeck.swift) but straight on, so every circle is a circle:
//   the rear flange's shadow on the plate      turned with the reel, round the shadow's own centre
//   the rear flange                            a solid disc, its three windows cut by a turning mask
//   the tape pack                              a full pack cut to the pack's radius
//   the tape from the pack to its roller       drawn (it moves with the pack's size; seen edge on, a point wide)
//   the front flange's shadow on the pack      turned
//   the front flange, hub and boss             as the rear flange
//   the three hold-down prongs                 24 rendered frames over 120 degrees
// and over both reels the head hood, lifted off the base (it stands in front of the reels' lower inner edges).
// The counter's figures are the first drum's ten crops, one laid on each drum. The keys are clear buttons over the
// rendered keys; pressed and lit, their rendered states (diff layers) over them. REC is a filament.
//
// The cart is its base (the cartridge in its slot with a blank label, keys out, LEDs and timer dark) with the label
// printed by the app over the paper (the signal's map and the playhead, multiplied), the lit keys, the LEDs (instant)
// and the timer: every segment lit in one layer, shown through a mask of the lit segments (the NAM meter bridge's way).
// The reel motion (ReelMotion, ReelSpeed) and the cart's state (CartState) are the 11-04 machines'.

extension RackKit {
    struct Deck: Decodable {
        struct Win: Decodable { let a0: CGFloat; let span: CGFloat; let r0: CGFloat; let r1: CGFloat }
        struct Prongs: Decodable { let picture: String; let frames: Int; let span: CGFloat; let box: [CGFloat] }
        struct Reel: Decodable {
            let box: [CGFloat]           // every layer's place (x, y, w, h)
            let c: [CGFloat]             // the reel's centre
            let r: CGFloat; let hub: CGFloat; let packFull: CGFloat
            let win: Win
            let roller: [CGFloat]; let rollerR: CGFloat   // its tension roller (the free span runs to it)
            let rear: String; let rearshadow: String; let pack: String; let front: String; let frontshadow: String
            let rearShadowC: [CGFloat]; let frontShadowC: [CGFloat]
            let prongs: Prongs
        }
        struct Key: Decodable { let id: String; let rect: [CGFloat] }
        struct Wheels: Decodable { let picture: String; let rects: [[CGFloat]] }
        struct Hood: Decodable { let picture: String; let rect: [CGFloat] }
        let reels: [String: Reel]
        let keys: [Key]                  // in layer order: k0 CHECK LEVELS, k1 CAPTURE, k2 STOP
        let wheels: Wheels
        let hood: Hood?                  // the head hood, lifted off the base: it stands in front of the reels
        var pictures: [String] {
            reels.values.flatMap { [$0.rear, $0.rearshadow, $0.pack, $0.front, $0.frontshadow, $0.prongs.picture] } + [wheels.picture]
                + (hood.map { [$0.picture] } ?? [])
        }
    }
    struct Cart: Decodable {
        struct Key: Decodable { let id: String; let rect: [CGFloat] }
        let label: [CGFloat]             // the blank label on the cartridge
        let keys: [Key]                  // k0 CHECK, k1 RECORD, k2 STOP
        let segs: [[[CGFloat]]]          // each timer segment's outline
        let cells: [[Int]]               // each cell's segments a..g (minutes, tens, units)
    }
}

private func rectOf(_ a: [CGFloat]) -> CGRect { CGRect(x: a[0], y: a[1], width: a[2], height: a[3]) }

// ------------------------------------------------------------------ a machine's keys
/// A key of a rendered machine, at its place in the unit's picture: a clear button over the rendered key; pressed or
/// lit, its rendered state over it (lit caps are filaments on the deck, instant on the cart).
struct RackMachineKey: View {
    let kit: RackKit
    let unit: RackKit.Unit
    let index: Int
    let rect: [CGFloat]
    let label: String
    var lit = false
    var filament = true
    let action: () -> Void
    var body: some View {
        Button(action: action) { Color.clear.frame(width: rect[2], height: rect[3]) }
            .buttonStyle(RackMachineKeyStyle(kit: kit, unit: unit, index: index, rect: rect, lit: lit, filament: filament))
            .accessibilityLabel(label)
            .accessibilityAddTraits(lit ? .isSelected : [])
            .offset(x: rect[0], y: rect[1])
    }
}

private struct RackMachineKeyStyle: ButtonStyle {
    let kit: RackKit
    let unit: RackKit.Unit
    let index: Int
    let rect: [CGFloat]
    let lit: Bool
    let filament: Bool
    func makeBody(configuration: Configuration) -> some View {
        Face(configuration: configuration, style: self)
    }
    private struct Face: View {
        let configuration: ButtonStyleConfiguration
        let style: RackMachineKeyStyle
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        func layer(_ state: String) -> some View {
            Group {
                if let l = style.unit.layers["k\(style.index)-\(state)"],
                   let img = SwellPictures.shared.image(l.picture, pxPerPoint: style.kit.pxPerPoint) {
                    Image(nsImage: img).resizable().interpolation(.high)
                        .frame(width: l.rect[2], height: l.rect[3])
                        .offset(x: l.rect[0] - style.rect[0], y: l.rect[1] - style.rect[1])
                }
            }
        }
        var body: some View {
            let down = configuration.isPressed && isEnabled
            configuration.label
                .contentShape(Rectangle())
                .overlay(alignment: .topLeading) {
                    ZStack(alignment: .topLeading) {
                        layer("lit").opacity(style.lit && !down ? 1 : 0)
                            .animation(style.filament && !reduceMotion ? SwellMotion.filament(style.lit) : nil, value: style.lit)
                        if down { layer(style.lit ? "litdown" : "down") }
                    }
                    .allowsHitTesting(false)
                }
        }
    }
}

// ------------------------------------------------------------------ the reel deck (8U)
/// A flange with its three windows cut out (even-odd: the box less the windows), in the reel picture's points.
private struct RackFlangeMask: Shape {
    let win: RackKit.Deck.Win
    let center: CGPoint
    let phi: Double
    func path(in rect: CGRect) -> Path {
        var p = Path(rect)
        for k in 0..<3 {
            let a0 = Double(win.a0) + Double(k) * 120 - phi, a1 = a0 + Double(win.span)
            let n = 24
            func pt(_ r: CGFloat, _ a: Double) -> CGPoint {
                CGPoint(x: center.x + r * CGFloat(cos(a * .pi / 180)), y: center.y - r * CGFloat(sin(a * .pi / 180)))
            }
            p.move(to: pt(win.r1, a0))
            for i in 1...n { p.addLine(to: pt(win.r1, a0 + (a1 - a0) * Double(i) / Double(n))) }
            for i in 0...n { p.addLine(to: pt(win.r0, a1 - (a1 - a0) * Double(i) / Double(n))) }
            p.closeSubpath()
        }
        return p
    }
}

private struct RackDisc: Shape {
    let center: CGPoint
    let r: CGFloat
    func path(in rect: CGRect) -> Path { Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)) }
}

/// One reel's layers, in the unit picture's points.
private struct RackReel: View {
    let kit: RackKit
    let reel: RackKit.Deck.Reel
    let phi: Double
    let packR: CGFloat
    let tape: Path
    func picture(_ name: String, _ box: CGRect) -> some View {
        Group {
            if let img = SwellPictures.shared.image(name, pxPerPoint: kit.pxPerPoint) {
                Image(nsImage: img).resizable().interpolation(.high).frame(width: box.width, height: box.height)
            }
        }
    }
    var body: some View {
        let box = rectOf(reel.box)
        let c = CGPoint(x: reel.c[0] - box.minX, y: reel.c[1] - box.minY)
        let anchor = { (a: [CGFloat]) in UnitPoint(x: (a[0] - box.minX) / box.width, y: (a[1] - box.minY) / box.height) }
        ZStack(alignment: .topLeading) {
            Group {
                picture(reel.rearshadow, box).rotationEffect(.degrees(phi), anchor: anchor(reel.rearShadowC))
                picture(reel.rear, box).mask(RackFlangeMask(win: reel.win, center: c, phi: phi).fill(style: FillStyle(eoFill: true)))
                if packR > reel.hub + 0.5 {
                    picture(reel.pack, box).mask(RackDisc(center: c, r: packR))
                    // the outermost wind's edge, a shade darker than the pack's face
                    RackDisc(center: c, r: packR - 0.3).stroke(Color(swellHex: 0x24180F, opacity: 0.35), lineWidth: 0.7)
                        .frame(width: box.width, height: box.height)
                }
            }
            .offset(x: box.minX, y: box.minY)
            // the free span, seen edge on (straight on the tape's width runs into the plate): a point wide
            tape.stroke(Color(swellHex: 0x4E3523), style: StrokeStyle(lineWidth: 1.0, lineCap: .butt))
            Group {
                picture(reel.frontshadow, box).rotationEffect(.degrees(phi), anchor: anchor(reel.frontShadowC))
                    .mask(RackDisc(center: c, r: reel.r))
                picture(reel.front, box).mask(RackFlangeMask(win: reel.win, center: c, phi: phi).fill(style: FillStyle(eoFill: true)))
            }
            .offset(x: box.minX, y: box.minY)
            prongs
        }
        .allowsHitTesting(false)
    }
    @ViewBuilder var prongs: some View {
        let pr = reel.prongs, pb = rectOf(pr.box)
        let n = max(1, pr.frames), step = Double(pr.span) / Double(n)
        let i = ((Int((phi / step).rounded()) % n) + n) % n
        if let cg = SwellPictures.shared.cgImage(pr.picture + ".webp") {
            let w = CGFloat(cg.width) / CGFloat(n)
            if let f = SwellPictures.shared.sprite(pr.picture + ".webp", rect: CGRect(x: (w * CGFloat(i)).rounded(), y: 0, width: w.rounded(.down), height: CGFloat(cg.height)),
                                                   pxPerPoint: kit.pxPerPoint) {
                Image(nsImage: f).resizable().interpolation(.high).frame(width: pb.width, height: pb.height).offset(x: pb.minX, y: pb.minY)
            }
        }
    }
}

/// The counter's four drums: each the first drum's crop showing its figure. A changed figure rolls in from below
/// (crossfades with Reduce Motion).
private struct RackCounter: View {
    let kit: RackKit
    let wheels: RackKit.Deck.Wheels
    let value: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func figure(_ d: Int) -> NSImage? {
        guard let cg = SwellPictures.shared.cgImage(wheels.picture + ".webp") else { return nil }
        let w = CGFloat(cg.width) / 10
        return SwellPictures.shared.sprite(wheels.picture + ".webp", rect: CGRect(x: (w * CGFloat(d)).rounded(), y: 0, width: w.rounded(.down), height: CGFloat(cg.height)),
                                           pxPerPoint: kit.pxPerPoint)
    }
    var body: some View {
        let s = Array(String(format: "%04d", max(0, min(9999, value))))
        ZStack(alignment: .topLeading) {
            ForEach(0..<min(4, wheels.rects.count), id: \.self) { i in
                let r = wheels.rects[i], digit = Int(String(s[i])) ?? 0
                ZStack {
                    if let f = figure(digit) {
                        Image(nsImage: f).resizable().interpolation(.high).frame(width: r[2], height: r[3])
                            .id(digit)
                            .transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                                                              removal: .move(edge: .top).combined(with: .opacity)))
                    }
                }
                .frame(width: r[2], height: r[3])
                .clipped()
                .animation(.easeInOut(duration: 0.22), value: digit)
                .offset(x: r[0], y: r[1])
            }
        }
        .allowsHitTesting(false)
    }
}

/// The deck at a given state, its keys passed in (placed in the unit picture's points; the preview gives dummy ones).
struct RackDeckFace<Keys: View>: View {
    let kit: RackKit
    let unit: RackKit.Unit
    let deck: RackKit.Deck
    let state: DeckState
    @ViewBuilder let keys: Keys
    var body: some View {
        let s = deck.reels["s"]!, t = deck.reels["t"]!
        let a = s.packFull * s.packFull - s.hub * s.hub
        // a few turns of leader stay on each hub (the tape stays threaded to the take-up reel when it is all wound back)
        let leader = 0.22 * kit.ptPerCm
        let rs = max(s.hub + leader, (s.hub * s.hub + a * CGFloat(1 - state.p)).squareRoot())
        let rt = max(t.hub + leader, (t.hub * t.hub + a * CGFloat(state.p)).squareRoot())
        let P = { (v: [CGFloat]) in CGPoint(x: v[0], y: v[1]) }
        let span = { (r: RackKit.Deck.Reel, pr: CGFloat, supply: Bool) -> Path in
            var p = Path()
            let (x, y) = supply ? tangent(P(r.c), pr, -1, P(r.roller), r.rollerR, 1, ey: 1)
                                : tangent(P(r.roller), r.rollerR, 1, P(r.c), pr, -1, ey: 1)
            p.move(to: x); p.addLine(to: y)
            return p
        }
        ZStack(alignment: .topLeading) {
            RackUnitPicture(kit: kit, unit: unit, on: state.recording ? ["rec"] : [], own: { $0.hasPrefix("k") },
                            overlay: AnyView(ZStack(alignment: .topLeading) {
                                RackReel(kit: kit, reel: s, phi: state.phiS, packR: rs, tape: span(s, rs, true))
                                RackReel(kit: kit, reel: t, phi: state.phiT, packR: rt, tape: span(t, rt, false))
                                if let h = deck.hood, let img = SwellPictures.shared.image(h.picture, pxPerPoint: kit.pxPerPoint) {
                                    Image(nsImage: img).resizable().interpolation(.high)
                                        .frame(width: h.rect[2], height: h.rect[3]).offset(x: h.rect[0], y: h.rect[1])
                                        .allowsHitTesting(false)
                                }
                                RackCounter(kit: kit, wheels: deck.wheels, value: state.seconds)
                            }
                            .frame(width: unit.size[0], height: unit.size[1], alignment: .topLeading)))
            ZStack(alignment: .topLeading) { keys }
                .frame(width: unit.size[0], height: unit.size[1], alignment: .topLeading)
                .offset(x: -unit.panel[0], y: -unit.panel[1])
        }
        .frame(width: kit.panelWidth, height: CGFloat(unit.u) * kit.uPt, alignment: .topLeading)
    }
}

/// Cab IR's recorder: the reel deck with the app's state (in place of the 11-04 ReelDeck, whose motion it keeps).
struct RackDeck: View {
    @EnvironmentObject var m: AppModel
    @State private var motion = ReelMotion()
    @State private var coasting = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static var available: Bool {
        guard let d = RackKit.ready("deck")?.1.deck else { return false }
        return d.reels["s"] != nil && d.reels["t"] != nil && d.keys.count == 3 && d.wheels.rects.count == 4
    }
    var rewinding: Bool { if case .some(.preparing) = m.busy, m.job == .cab, !m.cabImport { return true }; return false }
    var recording: Bool { m.tapeRun.map { [.noise, .levelSweep, .capture].contains($0.kind) } ?? false }
    var secondsLeft: Int {
        if case .some(.recording(let p)) = m.busy { return Int(((1 - p) * m.signalSeconds).rounded(.up)) }
        return Int(m.signalSeconds.rounded())
    }

    var body: some View {
        if Self.available, let r = RackKit.ready("deck"), let d = r.1.deck {
            let kit = r.0, u = r.1
            let moving = !reduceMotion && (m.tapeRun != nil || rewinding || coasting)
            // at the display's own rate (ProMotion: 120 Hz); paused whenever the reels stand still
            TimelineView(.animation(paused: !moving)) { ctx in
                RackDeckFace(kit: kit, unit: u, deck: d, state: state(at: ctx.date, kit: kit, d: d)) { keys(kit, u, d) }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Recorder")
            .accessibilityValue("\(secondsLeft) seconds left" + (recording ? ", recording" : ""))
            .onChange(of: m.tapeRun) { run in
                if run == nil { coasting = true }
            }
            .task(id: coasting) {
                guard coasting else { return }
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                coasting = false
            }
            .onChange(of: m.result?.folder) { f in if f != nil { motion.p = 1 } }
        }
    }

    func state(at date: Date, kit: RackKit, d: RackKit.Deck) -> DeckState {
        let r = d.reels["s"]!
        let cm = Double(kit.ptPerCm)
        if reduceMotion {
            motion.last = date
            if case .some(.recording(let p)) = m.busy { motion.p = p } else if rewinding { motion.p = 0 }
        } else {
            motion.advance(to: date, run: m.tapeRun, rewind: rewinding, hub: Double(r.hub) / cm, full: Double(r.packFull) / cm)
        }
        return DeckState(phiS: motion.phiS, phiT: motion.phiT, p: motion.p, seconds: secondsLeft, recording: recording)
    }

    @ViewBuilder func keys(_ kit: RackKit, _ u: RackKit.Unit, _ d: RackKit.Deck) -> some View {
        ForEach(Array(d.keys.enumerated()), id: \.offset) { i, k in
            switch k.id {
            case "check":
                RackMachineKey(kit: kit, unit: u, index: i, rect: k.rect, label: "Check levels", lit: m.levelRunning) { m.toggleLevelCheck() }
                    .disabled(m.busy != nil || m.device == nil)
                    .help(m.levelRunning ? "Click again or Stop to end the level check" : "Loop short sweeps to set the levels")
            case "capture":
                RackMachineKey(kit: kit, unit: u, index: i, rect: k.rect, label: "Capture", lit: m.busy?.progress != nil) { m.startCapture() }
                    .disabled(m.busy != nil || m.captureProblem != nil)
                    .help(m.captureProblem ?? "Play the sweeps, record every input and save the IRs")
            default:
                RackMachineKey(kit: kit, unit: u, index: i, rect: k.rect, label: "Stop") {
                    if m.levelRunning { m.stopLevelChecks() } else { m.cancelCapture() }
                }
                .disabled(!(m.levelRunning || m.busy?.progress != nil))
            }
        }
    }
}

// ------------------------------------------------------------------ the cart machine (3U)
/// The cartridge's end label, printed: the title, a rule, the training signal's map with the CHECK sections shaded and
/// the two cue clicks marked, and the playhead. The rack's lettering rule (no printed capital under 6 pt) leaves room
/// on a 1.9 cm label for the title and the length only; the sections are told by their shading.
struct RackCartLabel: View {
    let playhead: Double?
    var body: some View {
        Canvas { ctx, size in
            let W = size.width, H = size.height, u = H / 1.9          // points a cm on the label (it is 1.9 cm tall)
            let ink = Color(swellHex: 0x2C221A), red = Color(swellHex: 0xAA3C32)
            let f = Font.swellLegend(9.2)                             // capitals about 6.4 pt
            ctx.draw(Text("TRAINING SIGNAL v3").font(f).tracking(0.6).foregroundColor(ink), at: CGPoint(x: 0.25 * u, y: 0.02 * u), anchor: .topLeading)
            ctx.draw(Text("190 s").font(f).tracking(0.6).foregroundColor(ink), at: CGPoint(x: W - 0.25 * u, y: 0.02 * u), anchor: .topTrailing)
            var rule = Path(); rule.move(to: CGPoint(x: 0.25 * u, y: 0.78 * u)); rule.addLine(to: CGPoint(x: W - 0.25 * u, y: 0.78 * u))
            ctx.stroke(rule, with: .color(red), lineWidth: max(0.5, 0.03 * u))
            guard let mp = NAMSignalMap.shared else { return }
            let y0 = 0.92 * u, y1 = 1.76 * u, x0 = 0.25 * u, x1 = W - 0.25 * u, ym = (y0 + y1) / 2, T = mp.seconds
            let X = { (t: Double) in x0 + (x1 - x0) * CGFloat(t / T) }
            for (a, b) in [(0.0, 9.0), (181.0, 190.0)] {
                ctx.fill(Path(CGRect(x: X(a), y: y0, width: X(b) - X(a), height: y1 - y0)), with: .color(Color(swellHex: 0xD8A070)))
            }
            let n = mp.peak_db.count, cols = max(1, Int((x1 - x0) * 2))
            var pk = Path(), rm = Path()
            for c in 0..<cols {
                let i0 = c * n / cols, i1 = max(i0 + 1, (c + 1) * n / cols)
                let x = x0 + (x1 - x0) * (CGFloat(c) + 0.5) / CGFloat(cols)
                let hp = CGFloat(max(0, (mp.peak_db[i0..<i1].max()! + 48) / 48)) * (y1 - y0) / 2
                let hr = CGFloat(max(0, (mp.rms_db[i0..<i1].max()! + 48) / 48)) * (y1 - y0) / 2
                pk.move(to: CGPoint(x: x, y: ym - hp)); pk.addLine(to: CGPoint(x: x, y: ym + hp))
                rm.move(to: CGPoint(x: x, y: ym - hr)); rm.addLine(to: CGPoint(x: x, y: ym + hr))
            }
            let lw = (x1 - x0) / CGFloat(cols)
            ctx.stroke(pk, with: .color(Color(swellHex: 0x7E6650)), lineWidth: lw)
            ctx.stroke(rm, with: .color(Color(swellHex: 0x342820)), lineWidth: lw)
            for tc in [10.5, 11.5] {
                var l = Path(); l.move(to: CGPoint(x: X(tc), y: y0 - 0.04 * u)); l.addLine(to: CGPoint(x: X(tc), y: y1 + 0.04 * u))
                ctx.stroke(l, with: .color(red), lineWidth: max(0.5, 0.025 * u))
            }
            if let t = playhead {
                var ph = Path(); ph.move(to: CGPoint(x: X(t), y: y0 - 0.08 * u)); ph.addLine(to: CGPoint(x: X(t), y: y1 + 0.08 * u))
                ctx.stroke(ph, with: .color(Color(swellHex: 0xD01A10)), lineWidth: max(0.8, 0.06 * u))
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Training signal map")
        .accessibilityValue(playhead.map { "\(Int($0)) seconds" } ?? "")
    }
}

/// The cart at a given state, its keys passed in (placed in the unit picture's points).
struct RackCartFace<Keys: View>: View {
    let kit: RackKit
    let unit: RackKit.Unit
    let cart: RackKit.Cart
    let state: CartState
    @ViewBuilder let keys: Keys
    var body: some View {
        let s = max(0, min(599, state.secondsLeft))
        var on: Set<String> = ["colon"]
        if state.ready { on.insert("l0") }
        if state.cues { on.insert("l1"); on.insert("l2") }
        let lit = Self.segments(s, cells: cart.cells)
        let lb = rectOf(cart.label)
        return ZStack(alignment: .topLeading) {
            RackUnitPicture(kit: kit, unit: unit, on: on, filament: false, own: { $0.hasPrefix("k") || $0 == "dig" },
                            overlay: AnyView(ZStack(alignment: .topLeading) {
                                RackCartLabel(playhead: state.playhead)
                                    .frame(width: lb.width, height: lb.height)
                                    .blendMode(.multiply)
                                    .offset(x: lb.minX, y: lb.minY)
                                if let l = unit.layers["dig"] {
                                    MaskedLayer(kit: kit, size: unit.size, layer: l, grow: 1.6) { p in
                                        for i in lit.sorted() where i < cart.segs.count {
                                            let c = cart.segs[i]
                                            guard let f = c.first, f.count == 2 else { continue }
                                            p.move(to: CGPoint(x: f[0], y: f[1]))
                                            for q in c.dropFirst() where q.count == 2 { p.addLine(to: CGPoint(x: q[0], y: q[1])) }
                                            p.closeSubpath()
                                        }
                                    }
                                }
                            }
                            .frame(width: unit.size[0], height: unit.size[1], alignment: .topLeading)))
            ZStack(alignment: .topLeading) { keys }
                .frame(width: unit.size[0], height: unit.size[1], alignment: .topLeading)
                .offset(x: -unit.panel[0], y: -unit.panel[1])
        }
        .frame(width: kit.panelWidth, height: CGFloat(unit.u) * kit.uPt, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Cart machine, \(s / 60) minutes \(s % 60) seconds left")
    }

    /// The timer's segments lit for s seconds left, M:SS.
    static func segments(_ s: Int, cells: [[Int]]) -> Set<Int> {
        let chars = Array(String(s / 60)) + Array(String(format: "%02d", s % 60))
        var on = Set<Int>()
        for (k, c) in chars.suffix(cells.count).enumerated() where cells[k].count >= 7 {
            for ch in RackNAMMeterBridge.seg7[c] ?? "" { if let j = RackNAMMeterBridge.segIndex[ch] { on.insert(cells[k][j]) } }
        }
        return on
    }
}

/// Amp NAM's recorder: the cart machine with the app's state (in place of the 11-04 CartMachine).
struct RackCart: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static var available: Bool {
        guard let c = RackKit.ready("cart")?.1.cart else { return false }
        return c.keys.count == 3 && c.cells.count == 3
    }

    func state(at date: Date) -> CartState {
        var st = CartState(ready: m.namSignal != nil, cues: m.namResult != nil)
        let total = NAMSignalMap.shared?.seconds ?? 190
        if let r = m.tapeRun, r.kind == .namRecord {
            let t = max(0, date.timeIntervalSince(r.start))
            st.playhead = min(total, t); st.secondsLeft = Int((total - min(total, t)).rounded(.up))
        } else if let r = m.tapeRun, r.kind == .namLevel {
            let t = date.timeIntervalSince(r.start)
            st.playhead = r.offset + min(t, r.total - 0.2); st.secondsLeft = Int(total.rounded())
        } else if case .some(.namRecording(let p)) = m.busy {
            st.playhead = p * total; st.secondsLeft = Int(((1 - p) * total).rounded(.up))
        } else {
            st.playhead = m.namResult != nil ? total : 0; st.secondsLeft = Int(total.rounded())
        }
        return st
    }

    var body: some View {
        if Self.available, let r = RackKit.ready("cart"), let c = r.1.cart {
            let kit = r.0, u = r.1
            let running = m.tapeRun?.kind == .namRecord || m.tapeRun?.kind == .namLevel
            TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 1.0 / 30, paused: !running)) { ctx in
                RackCartFace(kit: kit, unit: u, cart: c, state: state(at: ctx.date)) { keys(kit, u, c) }
            }
        }
    }

    @ViewBuilder func keys(_ kit: RackKit, _ u: RackKit.Unit, _ c: RackKit.Cart) -> some View {
        ForEach(Array(c.keys.enumerated()), id: \.offset) { i, k in
            switch k.id {
            case "check":
                RackMachineKey(kit: kit, unit: u, index: i, rect: k.rect, label: "Check", lit: m.namLevelRunning, filament: false) { m.toggleNAMLevelCheck() }
                    .disabled(m.busy != nil)
                    .help(m.namLevelRunning ? "Click again or Stop to end the level check" : "Loop the loudest 6 seconds to set the levels")
            case "record":
                RackMachineKey(kit: kit, unit: u, index: i, rect: k.rect, label: "Record", lit: m.busy?.progress != nil, filament: false) { m.startNAMCapture() }
                    .disabled(m.busy != nil || m.namDirectProblem != nil)
                    .help(m.namDirectProblem ?? "Play the training signal (3 min 10 s) and record every input")
            default:
                RackMachineKey(kit: kit, unit: u, index: i, rect: k.rect, label: "Stop", filament: false) {
                    if m.namLevelRunning { m.stopLevelChecks() } else { m.cancelCapture() }
                }
                .disabled(!(m.namLevelRunning || m.busy?.progress != nil))
            }
        }
    }
}
#endif
