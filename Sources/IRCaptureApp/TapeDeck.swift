#if os(macOS)
import SwiftUI
import AppKit

// TapeDeck.swift: the tape machines (Phase 7, 2026-11-04). Cab IR's open-reel recorder and Amp NAM's broadcast cart
// machine replace the Set levels and Capture / Record panels. Pictures: design/render/ircapture_tape_layers.py,
// made into the kit by ircapture_tape_post.py; their layout in SwellKit/tape-pieces.json.
//
// The reel deck is the deck picture (everything that stands still) with each reel laid over it in layers:
//   the rear flange's shadow on the plate      turned with the reel, round the shadow's own centre
//   the rear flange                            a solid lit disc, its three windows cut by a turning mask
//   the tape pack                              a full pack cut to the pack's radius (its edge drawn a shade darker)
//   the tape from the pack to its guide roller drawn (it moves with the pack's size)
//   the front flange's shadow on the pack      turned, kept inside the flange
//   the front flange, hub and boss             as the rear flange
//   the three hold-down prongs                 24 rendered frames over 120 degrees (their chrome highlights move)
// A turned flange under a fixed light keeps its highlights in place while it turns, so only the windows move.
//
// Reel speed follows the sweep (Lowell, 11-03; design/render/ircapture_tape_speed.py): the tape speed at the heads
// goes from 3 3/4 in/s at the sweep's start to 15 in/s at its end, an octave scale, so each sweep is a steady
// acceleration; in each gap the reels coast down. Each reel turns at tape speed over its pack's radius. The packs show
// the capture's progress. Reduce Motion: the reels stand still and the packs step.

// ------------------------------------------------------------------ the layout file
struct TapePieces: Decodable {
    struct Deck: Decodable {
        let size: [CGFloat]
        let outline: [CGFloat]
        let pt_per_cm: CGFloat
        let ellipse_y: CGFloat
        struct Reel: Decodable {
            let box: [CGFloat]
            let shadow_c_rear: [CGFloat]
            let shadow_c_front: [CGFloat]
            let c_rear: [CGFloat]
            let c_pack: [CGFloat]
            let c_front: [CGFloat]
            let r: CGFloat
            let hub: CGFloat
            let pack_full: CGFloat
            struct Win: Decodable { let a0_deg: CGFloat; let span_deg: CGFloat; let r0: CGFloat; let r1: CGFloat }
            let win: Win
            let tape_thick: CGFloat
            struct Prongs: Decodable { let frames: Int; let span_deg: CGFloat; let box: [CGFloat] }
            let prongs: Prongs
        }
        let reels: [String: Reel]
        struct Jewel: Decodable { let c: [CGFloat]; let d: CGFloat }
        let jewel: Jewel
        let wheels: [[CGFloat]]
        let wheel_box: [CGFloat]
        struct Roller: Decodable { let c: [CGFloat]; let r: CGFloat }
        let rollers: [Roller]
    }
    struct Cart: Decodable {
        let size: [CGFloat]
        let outline: [CGFloat]
        let label: [CGFloat]
        let keys: [String: [CGFloat]]
        let lamps: [String: [CGFloat]]
        let digits: [String: [CGFloat]]
        let colon: [CGFloat]
    }
    let deck: Deck?
    let cart: Cart?
    struct Box: Decodable { let size: [CGFloat]; let outline: [CGFloat]; let label: [CGFloat]; let tilt_deg: CGFloat }
    let boxes: [String: Box]?

    static let shared: TapePieces? = {
        let url = SwellKit.folder.appendingPathComponent("tape-pieces.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        do { return try JSONDecoder().decode(TapePieces.self, from: data) } catch { NSLog("SwellKit: tape-pieces.json: %@", "\(error)"); return nil }
    }()
    /// The deck, when its layout and every picture it needs are in the kit (otherwise the step panels stay).
    static let deck: Deck? = {
        guard let d = shared?.deck else { return nil }
        let names = ["tape-deck", "tape-wheels"] + ["s", "t"].flatMap { k in
            ["rear", "rearshadow", "pack", "front", "frontshadow", "prongs"].map { "tape-reel-\(k)-\($0)" } }
        return names.allSatisfy { SwellPictures.shared.cgImage($0 + ".webp") != nil } && d.reels["s"] != nil && d.reels["t"] != nil ? d : nil
    }()
    /// The results' tape box for "reel" (Cab IR) or "cart" (Amp NAM), when its picture is in the kit.
    static func box(_ kind: String) -> Box? {
        guard let b = shared?.boxes?[kind], SwellPictures.shared.cgImage("tape-box-\(kind).webp") != nil else { return nil }
        return b
    }
    static let cart: Cart? = {
        guard let c = shared?.cart else { return nil }
        var names = ["tape-cart", "tape-cart-colon"] + ["0", "2", "3"].map { "tape-cart-digits-\($0)" }
        names += ["check", "record", "stop"].flatMap { k in ["off", "lit", "down", "litdown"].map { "tape-cart-key-\(k)-\($0)" } }
        names += ["ready", "cue1", "cue2"].map { "tape-cart-lamp-\($0)" }
        return names.allSatisfy { SwellPictures.shared.cgImage($0 + ".webp") != nil } ? c : nil
    }()
}

private func R(_ a: [CGFloat]) -> CGRect { CGRect(x: a[0], y: a[1], width: a[2], height: a[3]) }
private func P(_ a: [CGFloat]) -> CGPoint { CGPoint(x: a[0], y: a[1]) }

/// A tape picture at its point size (the @2x file when there is one).
private struct TapeImage: View {
    let name: String
    let rect: CGRect
    var body: some View {
        if let img = SwellPictures.shared.tileImage(name, pxPerPoint: 2.4) {
            img.resizable().interpolation(.high).frame(width: rect.width, height: rect.height).accessibilityHidden(true)
        }
    }
}

/// Frame `index` of a sheet of `count` frames side by side (the @2x sheet when there is one).
private func tapeFrame(_ name: String, _ index: Int, of count: Int) -> Image? {
    for (suffix, ppp) in [("@2x", CGFloat(4.8)), ("", CGFloat(2.4))] {
        guard let cg = SwellPictures.shared.cgImage(name + suffix + ".webp") else { continue }
        let w = CGFloat(cg.width) / CGFloat(count)
        let r = CGRect(x: (w * CGFloat(index)).rounded(), y: 0, width: w.rounded(.down), height: CGFloat(cg.height))
        if let c = cg.cropping(to: r) { return Image(decorative: c, scale: ppp) }
    }
    return nil
}

// ------------------------------------------------------------------ reel speed
enum ReelSpeed {
    static let vLo = 3.75 * 2.54, vHi = 15.0 * 2.54      // cm/s at the heads
    static let tau = 0.35                                 // coast-down in each gap, s
    /// Tape speed t seconds into a playback.
    static func speed(_ run: TapeRun, _ t: Double) -> Double {
        switch run.kind {
        case .noise, .namLevel, .namRecord: return 0
        case .levelSweep, .capture: break
        }
        if t < 0 || t > run.total { return 0 }
        if t < run.lead { return vLo * min(1, t / 0.4) }
        let u = t - run.lead, period = run.sweep + run.gap
        let k = Int(u / period)
        if k >= run.count { return 0 }
        let w = u - Double(k) * period
        if w < run.sweep { return vLo + (vHi - vLo) * w / run.sweep }
        return vLo + (vHi - vLo) * exp(-(w - run.sweep) / tau)
    }
}

/// The reels' state, carried from frame to frame (a reference, so the timeline can advance it while drawing).
final class ReelMotion {
    var last: Date?
    var v = 0.0                 // tape speed, cm/s (negative: rewinding)
    var phiS = 0.0, phiT = 0.0  // reel angles, degrees clockwise
    var p = 0.0                 // 0: all the tape on the supply reel … 1: all on the take-up reel
    private var table: (start: Date, dt: Double, cum: [Double])?
    /// The tape moved, as a fraction of the take, t seconds into a capture (the schedule is known, so it ends at 1).
    private func progress(_ run: TapeRun, _ t: Double) -> Double {
        if table?.start != run.start {
            let dt = 1.0 / 100, n = Int(run.total / dt) + 2
            var cum = [0.0], prev = ReelSpeed.speed(run, 0)
            for i in 1..<n { let v = ReelSpeed.speed(run, Double(i) * dt); cum.append(cum[i - 1] + (v + prev) / 2 * dt); prev = v }
            table = (run.start, dt, cum)
        }
        guard let tb = table, let total = tb.cum.last, total > 0 else { return 0 }
        let x = max(0, t / tb.dt), i = min(tb.cum.count - 2, Int(x)), f = x - Double(i)
        return min(1, (tb.cum[i] + (tb.cum[i + 1] - tb.cum[i]) * f) / total)
    }
    /// Moves everything on to `now`. `rewind`: a capture is about to start with tape on the take-up reel.
    func advance(to now: Date, run: TapeRun?, rewind: Bool, hub: Double, full: Double) {
        let dt = min(0.1, max(0, now.timeIntervalSince(last ?? now)))
        last = now
        if rewind && p > 0 {
            v = -70; p = max(0, p - dt / 0.9)
        } else if let r = run, r.kind == .levelSweep || r.kind == .capture {
            let t = now.timeIntervalSince(r.start)
            v = ReelSpeed.speed(r, t)
            if r.kind == .capture { p = progress(r, t) }
        } else {
            v *= exp(-dt / ReelSpeed.tau)
            if abs(v) < 0.05 { v = 0 }
        }
        let a = full * full - hub * hub
        let rs = (hub * hub + a * (1 - p)).squareRoot(), rt = (hub * hub + a * p).squareRoot()
        phiS = (phiS + v / rs * dt * 180 / .pi).truncatingRemainder(dividingBy: 360)
        phiT = (phiT + v / rt * dt * 180 / .pi).truncatingRemainder(dividingBy: 360)
    }
}

// ------------------------------------------------------------------ the deck's face, drawn from a state
/// Everything the reel deck shows at one moment (so the CI preview can draw it without a capture running).
struct DeckState {
    var phiS = 0.0, phiT = 0.0
    var p = 0.0
    var seconds = 0
    var recording = false
}

/// The window cut-outs of a flange (an even-odd path: the box with three annular windows taken out).
private struct FlangeMask: Shape {
    let reel: TapePieces.Deck.Reel
    let center: CGPoint      // in the box's own points
    let phi: Double
    let ey: CGFloat
    func path(in rect: CGRect) -> Path {
        var p = Path(rect)
        let w = reel.win
        for k in 0..<3 {
            let a0 = Double(w.a0_deg) + Double(k) * 120 - phi, a1 = a0 + Double(w.span_deg)
            let n = 24
            func pt(_ r: CGFloat, _ a: Double) -> CGPoint {
                CGPoint(x: center.x + r * CGFloat(cos(a * .pi / 180)), y: center.y - r * CGFloat(sin(a * .pi / 180)) * ey)
            }
            p.move(to: pt(w.r1, a0))
            for i in 1...n { p.addLine(to: pt(w.r1, a0 + (a1 - a0) * Double(i) / Double(n))) }
            for i in 0...n { p.addLine(to: pt(w.r0, a1 - (a1 - a0) * Double(i) / Double(n))) }
            p.closeSubpath()
        }
        return p
    }
}

private struct TapeEllipse: Shape {
    let center: CGPoint
    let r: CGFloat
    let ey: CGFloat
    func path(in rect: CGRect) -> Path {
        Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r * ey, width: 2 * r, height: 2 * r * ey))
    }
}

/// One reel's layers, in the deck picture's points.
private struct ReelStack: View {
    let key: String
    let reel: TapePieces.Deck.Reel
    let ey: CGFloat
    let phi: Double
    let packR: CGFloat
    let tape: Path
    var body: some View {
        let box = R(reel.box)
        let local = { (a: [CGFloat]) in CGPoint(x: a[0] - box.minX, y: a[1] - box.minY) }
        let anchor = { (a: [CGFloat]) in UnitPoint(x: (a[0] - box.minX) / box.width, y: (a[1] - box.minY) / box.height) }
        ZStack(alignment: .topLeading) {
            Group {
                TapeImage(name: "tape-reel-\(key)-rearshadow", rect: box)
                    .rotationEffect(.degrees(phi), anchor: anchor(reel.shadow_c_rear))
                TapeImage(name: "tape-reel-\(key)-rear", rect: box)
                    .mask(FlangeMask(reel: reel, center: local(reel.c_rear), phi: phi, ey: ey).fill(style: FillStyle(eoFill: true)))
                if packR > reel.hub + 0.5 {
                    // the pack's edge (the tape's side, seen 10 degrees from above), then its face
                    TapeImage(name: "tape-reel-\(key)-pack", rect: box).brightness(-0.16)
                        .mask(TapeEllipse(center: CGPoint(x: local(reel.c_pack).x, y: local(reel.c_pack).y - reel.tape_thick), r: packR, ey: ey))
                    TapeImage(name: "tape-reel-\(key)-pack", rect: box)
                        .mask(TapeEllipse(center: local(reel.c_pack), r: packR, ey: ey))
                }
            }
            .offset(x: box.minX, y: box.minY)
            tape.stroke(Color(swellHex: 0x4E3523), style: StrokeStyle(lineWidth: max(1, reel.tape_thick), lineCap: .butt))
            tape.offsetBy(dx: 0, dy: -reel.tape_thick * 0.35).stroke(Color(swellHex: 0x8C6A4C, opacity: 0.7), lineWidth: 0.45)
            Group {
                TapeImage(name: "tape-reel-\(key)-frontshadow", rect: box)
                    .rotationEffect(.degrees(phi), anchor: anchor(reel.shadow_c_front))
                    .mask(TapeEllipse(center: local(reel.c_front), r: reel.r, ey: ey))
                TapeImage(name: "tape-reel-\(key)-front", rect: box)
                    .mask(FlangeMask(reel: reel, center: local(reel.c_front), phi: phi, ey: ey).fill(style: FillStyle(eoFill: true)))
            }
            .offset(x: box.minX, y: box.minY)
            let pb = R(reel.prongs.box)
            let n = reel.prongs.frames, step = Double(reel.prongs.span_deg) / Double(n)
            let i = ((Int((phi / step).rounded()) % n) + n) % n
            if let f = tapeFrame("tape-reel-\(key)-prongs", i, of: n) {
                f.resizable().interpolation(.high).frame(width: pb.width, height: pb.height).offset(x: pb.minX, y: pb.minY)
            }
        }
        .allowsHitTesting(false)
    }
}

/// The tangent from circle 1 to circle 2 (centres in screen points, radii in points; s = +1 counter-clockwise round
/// it, -1 clockwise, as ircapture_tape.tape_path), worked in the reels' plane (y over the ellipse factor).
private func tangent(_ c1s: CGPoint, _ r1: CGFloat, _ s1: CGFloat, _ c2s: CGPoint, _ r2: CGFloat, _ s2: CGFloat, ey: CGFloat) -> (CGPoint, CGPoint) {
    let c1 = CGPoint(x: c1s.x, y: -c1s.y / ey), c2 = CGPoint(x: c2s.x, y: -c2s.y / ey)
    let D = CGPoint(x: c2.x - c1.x, y: c2.y - c1.y)
    let dd = D.x * D.x + D.y * D.y, k = s2 * r2 - s1 * r1
    let L = max(0, dd - k * k).squareRoot()
    let pD = CGPoint(x: -D.y, y: D.x)
    let t = CGPoint(x: (L * D.x - k * pD.x) / dd, y: (L * D.y - k * pD.y) / dd)
    let pt = CGPoint(x: -t.y, y: t.x)
    let a = CGPoint(x: c1.x - s1 * r1 * pt.x, y: c1.y - s1 * r1 * pt.y)
    let b = CGPoint(x: c2.x - s2 * r2 * pt.x, y: c2.y - s2 * r2 * pt.y)
    return (CGPoint(x: a.x, y: -a.y * ey), CGPoint(x: b.x, y: -b.y * ey))
}

/// The four wheels of the mechanical counter. A changed digit rolls in from below (crossfades with Reduce Motion).
private struct CounterWheels: View {
    let d: TapePieces.Deck
    let value: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let wb = R(d.wheel_box), w0 = d.wheels.first?[0] ?? wb.minX
        let s = String(format: "%04d", max(0, min(9999, value)))
        ZStack(alignment: .topLeading) {
            ForEach(0..<min(4, d.wheels.count), id: \.self) { i in
                let digit = Int(String(Array(s)[i])) ?? 0
                ZStack {
                    if let f = tapeFrame("tape-wheels", digit, of: 10) {
                        f.resizable().interpolation(.high).frame(width: wb.width, height: wb.height)
                            .id(digit)
                            .transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                                                              removal: .move(edge: .top).combined(with: .opacity)))
                    }
                }
                .frame(width: wb.width, height: wb.height)
                .clipped()
                .animation(.easeInOut(duration: 0.22), value: digit)
                .offset(x: wb.minX + (d.wheels[i][0] - w0), y: wb.minY)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(value) seconds left")
    }
}

extension HorizontalAlignment {
    private enum DeckJewel: AlignmentID { static func defaultValue(in d: ViewDimensions) -> CGFloat { d[HorizontalAlignment.center] } }
    static let deckJewel = HorizontalAlignment(DeckJewel.self)
}

/// The reel deck's face at a given state, with its keys (passed in, so the preview can give dummy ones).
struct ReelDeckFace<Keys: View>: View {
    let d: TapePieces.Deck
    let state: DeckState
    @ViewBuilder let keys: Keys
    var body: some View {
        let ey = d.ellipse_y
        let a = (d.reels["s"]!.pack_full * d.reels["s"]!.pack_full - d.reels["s"]!.hub * d.reels["s"]!.hub)
        let hub = d.reels["s"]!.hub
        // a few turns of leader stay on each hub (the tape is threaded through the heads to the take-up reel even
        // when it is all wound back), so an empty reel still shows its turns and the tape still runs to it
        let leader = 0.22 * d.pt_per_cm
        let rs = max(hub + leader, (hub * hub + a * CGFloat(1 - state.p)).squareRoot())
        let rt = max(hub + leader, (hub * hub + a * CGFloat(state.p)).squareRoot())
        let sR = d.reels["s"]!, tR = d.reels["t"]!
        let span = { (pack: TapePieces.Deck.Reel, r: CGFloat, roller: TapePieces.Deck.Roller, supply: Bool) -> Path in
            var p = Path()
            if r > hub + 0.5, supply {
                let (x, y) = tangent(P(pack.c_pack), r, -1, P(roller.c), roller.r, 1, ey: ey); p.move(to: x); p.addLine(to: y)
            } else if r > hub + 0.5 {
                let (x, y) = tangent(P(roller.c), roller.r, 1, P(pack.c_pack), r, -1, ey: ey); p.move(to: x); p.addLine(to: y)
            }
            return p
        }
        ZStack(alignment: .topLeading) {
            TapeImage(name: "tape-deck", rect: CGRect(x: 0, y: 0, width: d.size[0], height: d.size[1]))
            ReelStack(key: "s", reel: sR, ey: ey, phi: state.phiS, packR: rs, tape: span(sR, rs, d.rollers[0], true))
            ReelStack(key: "t", reel: tR, ey: ey, phi: state.phiT, packR: rt, tape: span(tR, rt, d.rollers[1], false))
            CounterWheels(d: d, value: state.seconds)
            keys
                .frame(width: d.size[0], height: 44, alignment: Alignment(horizontal: .deckJewel, vertical: .center))
                .offset(x: d.jewel.c[0] - d.size[0] / 2, y: d.jewel.c[1] - 22)
        }
        .frame(width: d.size[0], height: d.size[1], alignment: .topLeading)
    }
}

/// The deck at the width it is given (its outline fills the width; its shadow margin overhangs).
struct ScaledMachine<Content: View>: View {
    let size: [CGFloat]
    let outline: [CGFloat]
    var maxScale: CGFloat = 1.3
    @ViewBuilder let content: Content
    var body: some View {
        GeometryReader { g in
            let s = min(maxScale, g.size.width / outline[2])
            content
                .scaleEffect(s, anchor: .topLeading)
                .offset(x: -outline[0] * s, y: -outline[1] * s)
        }
        .aspectRatio(outline[2] / outline[3], contentMode: .fit)
    }
}

// ------------------------------------------------------------------ Cab IR: the reel deck with the app's state
struct ReelDeck: View {
    @EnvironmentObject var m: AppModel
    let d: TapePieces.Deck
    @State private var motion = ReelMotion()
    @State private var coasting = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var rewinding: Bool { if case .some(.preparing) = m.busy, m.job == .cab, !m.cabImport { return true }; return false }
    var recording: Bool { m.tapeRun.map { [.noise, .levelSweep, .capture].contains($0.kind) } ?? false }
    var secondsLeft: Int {
        if case .some(.recording(let p)) = m.busy { return Int(((1 - p) * m.signalSeconds).rounded(.up)) }
        return Int(m.signalSeconds.rounded())
    }
    var body: some View {
        let moving = !reduceMotion && (m.tapeRun != nil || rewinding || coasting)
        ScaledMachine(size: d.size, outline: d.outline) {
            // at the display's own rate (ProMotion: 120 Hz); paused whenever the reels stand still
            TimelineView(.animation(paused: !moving)) { ctx in
                ReelDeckFace(d: d, state: state(at: ctx.date)) { keys }
            }
        }
        .onChange(of: m.tapeRun) { r in
            if r == nil { coasting = true }
        }
        .task(id: coasting) {
            guard coasting else { return }
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            coasting = false
        }
        .onChange(of: m.result?.folder) { f in if f != nil { motion.p = 1 } }
    }

    func state(at date: Date) -> DeckState {
        let r = d.reels["s"]!
        let cm = Double(d.pt_per_cm)
        if reduceMotion {
            motion.last = date
            if case .some(.recording(let p)) = m.busy { motion.p = p } else if rewinding { motion.p = 0 }
        } else {
            motion.advance(to: date, run: m.tapeRun, rewind: rewinding, hub: Double(r.hub) / cm, full: Double(r.pack_full) / cm)
        }
        return DeckState(phiS: motion.phiS, phiT: motion.phiT, p: motion.p, seconds: secondsLeft, recording: recording)
    }

    @ViewBuilder var keys: some View {
        HStack(spacing: 8) {
            HStack(spacing: 14) {
                Button("Check levels") { m.toggleLevelCheck() }
                    .buttonStyle(KeyButtonStyle(key: "Check levels", lit: m.levelRunning, size: 12))
                    .disabled(m.busy != nil || m.device == nil)
                    .help(m.levelRunning ? "Click again or Stop to end the level check" : "Loop short sweeps to set the levels")
                Button("Capture") { m.startCapture() }
                    .buttonStyle(KeyButtonStyle(key: "Capture", lit: m.busy?.progress != nil, size: 13))
                    .disabled(m.busy != nil || m.captureProblem != nil)
                    .help(m.captureProblem ?? "Play the sweeps, record every input and save the IRs")
            }
            JewelLamp(colour: "red", on: recording, diameter: d.jewel.d * 0.82)
                .frame(width: d.jewel.d, height: d.jewel.d)
                .alignmentGuide(.deckJewel) { $0[HorizontalAlignment.center] }
                .accessibilityElement().accessibilityLabel(recording ? "Recording" : "Not recording")
            Button("Stop") { if m.levelRunning { m.stopLevelChecks() } else { m.cancelCapture() } }
                .buttonStyle(KeyButtonStyle(key: "Stop", size: 12))
                .disabled(!(m.levelRunning || m.busy?.progress != nil))
        }
    }
}

// ------------------------------------------------------------------ Amp NAM: the cart machine
/// The training signal's map for the cart's label: T3K-sweep-v3.wav's envelope (reference/nam_v3_map.json, copied
/// into the kit), peak and RMS per 0.25 s.
struct NAMSignalMap: Decodable {
    let block_s: Double
    let peak_db: [Double]
    let rms_db: [Double]
    static let shared: NAMSignalMap? = {
        let url = SwellKit.folder.appendingPathComponent("nam_v3_map.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(NAMSignalMap.self, from: data)
    }()
    var seconds: Double { Double(peak_db.count) * block_s }
}

/// The cart's end label, printed: title, rule, the CHECK sections shaded, the envelope, the two cue clicks.
struct CartLabel: View {
    let playhead: Double?            // seconds into the training signal; nil: none
    var body: some View {
        Canvas { ctx, size in
            let W = size.width, H = size.height, u = H / 1.9          // u: points a cm on the label (it is 1.9 cm tall)
            let ink = Color(swellHex: 0x2C221A), dim = Color(swellHex: 0x46382C), red = Color(swellHex: 0xAA3C32)
            ctx.draw(Text("TRAINING SIGNAL v3").font(.swellLegend(0.3 * u)).foregroundColor(ink), at: CGPoint(x: 0.25 * u, y: 0.06 * u), anchor: .topLeading)
            ctx.draw(Text("190 s  ·  48 kHz  ·  MONO").font(.swellLegend(0.24 * u)).foregroundColor(dim), at: CGPoint(x: W - 0.25 * u, y: 0.1 * u), anchor: .topTrailing)
            var rule = Path(); rule.move(to: CGPoint(x: 0.25 * u, y: 0.5 * u)); rule.addLine(to: CGPoint(x: W - 0.25 * u, y: 0.5 * u))
            ctx.stroke(rule, with: .color(red), lineWidth: max(0.5, 0.03 * u))
            guard let mp = NAMSignalMap.shared else { return }
            let y0 = 0.62 * u, y1 = 1.42 * u, x0 = 0.25 * u, x1 = W - 0.25 * u, ym = (y0 + y1) / 2, T = mp.seconds
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
                var l = Path(); l.move(to: CGPoint(x: X(tc), y: y0 - 0.06 * u)); l.addLine(to: CGPoint(x: X(tc), y: y1 + 0.06 * u))
                ctx.stroke(l, with: .color(red), lineWidth: max(0.5, 0.025 * u))
            }
            let f = Font.swellLegend(0.22 * u), yl = y1 + 0.03 * u
            ctx.draw(Text("CHECK").font(f).foregroundColor(dim), at: CGPoint(x: X(0), y: yl), anchor: .topLeading)
            ctx.draw(Text("CUE 1, 2").font(f).foregroundColor(red), at: CGPoint(x: X(12.5), y: yl), anchor: .topLeading)
            ctx.draw(Text("TRAINING").font(f).foregroundColor(dim), at: CGPoint(x: (x0 + x1) / 2, y: yl), anchor: .top)
            ctx.draw(Text("CHECK").font(f).foregroundColor(dim), at: CGPoint(x: x1, y: yl), anchor: .topTrailing)
            if let t = playhead {
                var ph = Path(); ph.move(to: CGPoint(x: X(t), y: y0 - 0.1 * u)); ph.addLine(to: CGPoint(x: X(t), y: y1 + 0.1 * u))
                ctx.stroke(ph, with: .color(Color(swellHex: 0xD01A10)), lineWidth: max(0.8, 0.06 * u))
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Training signal map")
        .accessibilityValue(playhead.map { "\(Int($0)) seconds" } ?? "")
    }
}

/// A square lens pushbutton of the cart: its four rendered states.
struct CartKeyStyle: ButtonStyle {
    let key: String
    let rect: CGRect
    var lit = false
    func makeBody(configuration: Configuration) -> some View {
        Face(configuration: configuration, key: key, rect: rect, lit: lit)
    }
    private struct Face: View {
        let configuration: ButtonStyleConfiguration
        let key: String
        let rect: CGRect
        let lit: Bool
        @Environment(\.isEnabled) private var isEnabled
        var body: some View {
            let down = configuration.isPressed && isEnabled
            let st = lit ? (down ? "litdown" : "lit") : (down ? "down" : "off")
            TapeImage(name: "tape-cart-key-\(key)-\(st)", rect: rect)
                .brightness(isEnabled ? 0 : -0.06)
                .contentShape(Rectangle())
                .accessibilityAddTraits(lit ? .isSelected : [])
        }
    }
}

struct CartState {
    var playhead: Double? = 0
    var secondsLeft = 190
    var ready = false
    var cues = false
}

/// The cart machine's face at a given state, its three keys passed in.
struct CartFace<Keys: View>: View {
    let c: TapePieces.Cart
    let state: CartState
    @ViewBuilder let keys: Keys
    @ViewBuilder func lamp(_ k: String, _ on: Bool) -> some View {
        if on, let r = c.lamps[k] { TapeImage(name: "tape-cart-lamp-\(k)", rect: R(r)).offset(x: r[0], y: r[1]) }
    }
    @ViewBuilder func digit(_ p: String, _ d: Int) -> some View {
        if let r = c.digits[p], let f = tapeFrame("tape-cart-digits-\(p)", d, of: 10) {
            f.resizable().interpolation(.high).frame(width: r[2], height: r[3]).offset(x: r[0], y: r[1])
        }
    }
    var body: some View {
        let s = max(0, min(599, state.secondsLeft))
        ZStack(alignment: .topLeading) {
            TapeImage(name: "tape-cart", rect: CGRect(x: 0, y: 0, width: c.size[0], height: c.size[1]))
            CartLabel(playhead: state.playhead).frame(width: c.label[2], height: c.label[3]).offset(x: c.label[0], y: c.label[1])
            lamp("ready", state.ready)
            lamp("cue1", state.cues)
            lamp("cue2", state.cues)
            digit("0", s / 60)
            digit("2", (s % 60) / 10)
            digit("3", s % 10)
            TapeImage(name: "tape-cart-colon", rect: R(c.colon)).offset(x: c.colon[0], y: c.colon[1])
            keys
        }
        .frame(width: c.size[0], height: c.size[1], alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Cart machine, \(s / 60) minutes \(s % 60) seconds left")
    }
}

struct CartMachine: View {
    @EnvironmentObject var m: AppModel
    let c: TapePieces.Cart
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
        let running = m.tapeRun?.kind == .namRecord || m.tapeRun?.kind == .namLevel
        ScaledMachine(size: c.size, outline: c.outline) {
            TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 1.0 / 30, paused: !running)) { ctx in
                CartFace(c: c, state: state(at: ctx.date)) { keys }
            }
        }
    }
    @ViewBuilder var keys: some View {
        let k = { (n: String) in R(c.keys[n] ?? [0, 0, 1, 1]) }
        Button("Check") { m.toggleNAMLevelCheck() }
            .buttonStyle(CartKeyStyle(key: "check", rect: k("check"), lit: m.namLevelRunning))
            .disabled(m.busy != nil)
            .help(m.namLevelRunning ? "Click again or Stop to end the level check" : "Loop the loudest 6 seconds to set the levels")
            .offset(x: k("check").minX, y: k("check").minY)
        Button("Record") { m.startNAMCapture() }
            .buttonStyle(CartKeyStyle(key: "record", rect: k("record"), lit: m.busy?.progress != nil))
            .disabled(m.busy != nil || m.namDirectProblem != nil)
            .help(m.namDirectProblem ?? "Play the training signal (3 min 10 s) and record every input")
            .offset(x: k("record").minX, y: k("record").minY)
        Button("Stop") { if m.namLevelRunning { m.stopLevelChecks() } else { m.cancelCapture() } }
            .buttonStyle(CartKeyStyle(key: "stop", rect: k("stop")))
            .disabled(!(m.namLevelRunning || m.busy?.progress != nil))
            .offset(x: k("stop").minX, y: k("stop").minY)
    }
}

// ------------------------------------------------------------------ results: the capture's tape box
/// The kraft box a capture goes back into, its track sheet typed: the capture's name, what is on it, the files to
/// load, and a stamp with the result.
struct TapeBox: View {
    let kind: String              // "reel" or "cart"
    let box: TapePieces.Box
    let title: String
    let lines: [(String, String)]
    let stamp: (String, Color)
    var body: some View {
        let lab = R(box.label)
        let small = lab.height < 100           // the cart carton's short label: one line each, a smaller stamp
        ZStack(alignment: .topLeading) {
            TapeImage(name: "tape-box-\(kind)", rect: CGRect(x: 0, y: 0, width: box.size[0], height: box.size[1]))
            VStack(alignment: .leading, spacing: small ? 2 : 4) {
                Text(title).font(.swellMono(small ? 11 : 12, bold: true)).lineLimit(1).minimumScaleFactor(0.6)
                Rectangle().fill(Color(swellHex: 0xAA3C32, opacity: 0.8)).frame(height: 0.8)
                ForEach(Array(lines.enumerated()), id: \.offset) { _, l in
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(l.0).font(.swellLegend(8.5)).foregroundColor(Color(swellHex: 0x5A4A3A)).frame(width: small ? 48 : 40, alignment: .leading)
                        Text(l.1).font(.swellMono(9)).lineLimit(small ? 1 : 2).truncationMode(.middle).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                HStack {
                    Spacer()
                    Text(stamp.0).font(.swellLegend(small ? 8.5 : 11, bold: true)).textCase(.uppercase).tracking(small ? 0.8 : 1.2)
                        .foregroundColor(stamp.1.opacity(0.85))
                        .padding(.horizontal, small ? 4 : 6).padding(.vertical, small ? 1 : 2)
                        .overlay(RoundedRectangle(cornerRadius: 2).stroke(stamp.1.opacity(0.75), lineWidth: small ? 1.1 : 1.4))
                        .rotationEffect(.degrees(0))  // level (11-04)
                }
            }
            .foregroundColor(Color(swellHex: 0x231A12))
            .padding(.horizontal, 9).padding(.vertical, small ? 5 : 7)
            .frame(width: lab.width, height: lab.height, alignment: .topLeading)
            .clipped()
            .rotationEffect(.degrees(-Double(box.tilt_deg)))
            .offset(x: lab.minX, y: lab.minY)
        }
        .frame(width: box.size[0], height: box.size[1], alignment: .topLeading)
        .padding(.leading, -box.outline[0]).padding(.top, -box.outline[1])
        .padding(.trailing, -(box.size[0] - box.outline[0] - box.outline[2])).padding(.bottom, -(box.size[1] - box.outline[1] - box.outline[3]))
        .accessibilityElement(children: .combine)
    }
}
#endif
