#if os(macOS)
import SwiftUI
import IRCaptureCore

// Rack.swift: the rack bay (Phase 7a, the visual audit of 2026-11-11; Lowell approved the three proofs).
//
// The scrolling area is a 19 inch rack standing against the wall under the shelf: rough shop-wood boards for its sides,
// top and bottom, the dark inside of the rack between them, and every job step a rack unit of whole U bolted in.
// Everything in the bay is at one scale, 14 pt a cm (a 19 inch panel 675.6 pt wide, 1U 62.23 pt), rendered straight on
// (design/render/ircapture_rack_layers.py) and posted with ircapture_rack_post.py into SwellKit/irc-rack.json:
//   units     each a base picture (live parts at rest: lamps dark) and its live layers (a lamp lit: only the pixels that
//             change, cut tight), placed by the panel's rectangle in the picture
//   cheeks    the side board (a long strip, laid end to end down the bay) and the top board
// Units are built one at a time (the audit's order of work); steps not built yet stand in the bay as they were.
// Without irc-rack.json or any of its pictures the page is laid out as before (StageOpening).

struct RackKit: Decodable {
    let pxPerPoint: CGFloat
    let ptPerCm: CGFloat
    let uPt: CGFloat
    let units: [String: Unit]
    let cheeks: Cheeks?
    let shelf: Shelf?             // the shelf from below (RackShelf.swift)

    struct Unit: Decodable {
        let picture: String
        let u: Int
        let size: [CGFloat]          // the picture, pt
        let panel: [CGFloat]         // the unit's slot in the picture: x, y, width, height (pt)
        let layers: [String: Layer]
        let meters: Meters?          // the meter bridge's own parts
        let results: Results?        // the results unit's own parts
        let preflight: Preflight?    // the pre-flight unit's own parts
        let patch: Patch?            // the patch unit's own parts (RackPatch.swift)
        let nammeters: NAMMeters?    // the NAM meter bridge's own parts (RackNAMMeters.swift)
        let deck: Deck?              // the reel deck's own parts (RackMachines.swift)
        let cart: Cart?              // the cart machine's own parts (RackMachines.swift)
        // (11-12) the fourth proof's units (RackSetup.swift, RackPlotter.swift)
        var connect: Connect? = nil
        var files: Files? = nil
        var sweep: Setup? = nil
        var formats: Setup? = nil
        var plotter: Plotter? = nil
    }
    /// The pre-flight (4U): BEFORE CAPTURE, a printed form with a ruled table (ITEM, READING, OK), typed by the app.
    struct Preflight: Decodable {
        struct Form: Decodable {
            let w: CGFloat; let h: CGFloat; let typedCm: CGFloat; let advance: CGFloat
            let headY: CGFloat; let rule: CGFloat; let rowH: CGFloat; let rows: Int; let baseline0: CGFloat
            let cols: [Results.Col]; let right: CGFloat
        }
        let sheet: [CGFloat]         // the sheet in the base picture (pt)
        let form: Form
    }
    /// The results (7U): the take sheet's printed form and where things go on it, the keys, the stamps.
    struct Results: Decodable {
        struct Field: Decodable { let key: String; let label: String; let x0: CGFloat; let x1: CGFloat; let baseline: CGFloat }
        struct Col: Decodable { let key: String; let label: String; let x: CGFloat }
        struct Table: Decodable {
            let headY: CGFloat; let rule: CGFloat; let rowH: CGFloat; let rows: Int; let baseline0: CGFloat
            let dabX: CGFloat; let nameX: CGFloat; let right: CGFloat; let cols: [Col]
        }
        struct Lines: Decodable { let labelY: CGFloat; let x0: CGFloat; let x1: CGFloat; let baselines: [CGFloat] }
        /// The form in the sheet's centimetres (x from its left edge, y down from its top; entries by their baselines).
        struct Form: Decodable {
            let w: CGFloat; let h: CGFloat; let typedCm: CGFloat; let advance: CGFloat
            let fields: [Field]; let checked: [CGFloat]; let table: Table; let files: Lines; let notes: Lines
        }
        struct Key: Decodable { let id: String; let rect: [CGFloat] }
        struct Stamp: Decodable { let picture: String; let size: [CGFloat] }
        let sheet: [CGFloat]         // the sheet in the base picture (pt)
        let form: Form
        let keys: [Key]              // each key's bezel in the base picture (pt); its pressed layer is "k<i>-down"
        let pxPerPoint: CGFloat      // the stamps'
        let stamps: [String: Stamp]  // excellent, check, again
    }
    /// The meter bridge (5U): four channel modules. Places are in the base picture (pt).
    struct Meters: Decodable {
        struct Module: Decodable {
            let gas: [CGFloat]       // the gas digits' face (x, y, w, h): the cells, as irc-gas.json's "cells"
            let gasN: Int
            let vuPivot: [CGFloat]   // the needle's pivot (under the window's lower edge)
            let vuWindow: [CGFloat]  // the VU's window: the needle is seen only in it
            let eye: [CGFloat]       // the eye's centre
            let strip: [CGFloat]     // the scribble strip (the tape)
            let lamps: [[CGFloat]]   // each lamp's centre
        }
        struct Eye: Decodable {
            let picture: String      // the states' sheet: warm0, warm1, warm2, x00 … x55, perRow to a row
            let perRow: Int
            let states: [String]
            let cell: [CGFloat]      // a cell (pt)
            let center: [CGFloat]    // the eye's centre in a cell
            let bore: CGFloat
        }
        struct Needle: Decodable {
            let picture: String
            let size: [CGFloat]
            let pivot: [CGFloat]     // in the needle's picture
        }
        let lamps: [String]
        let vuTable: [[Double]]      // VU, degrees from vertical (clockwise positive)
        let modules: [Module]
        let eye: Eye
        let needle: Needle
    }
    struct Layer: Decodable {
        let picture: String
        let rect: [CGFloat]          // in the base picture, pt
    }
    /// The shelf from below (11-12): the plank strip and the three boxes standing on it. Places in each picture, pt.
    struct Shelf: Decodable {
        struct Plank: Decodable {
            let picture: String
            let size: [CGFloat]
            let frontTop: CGFloat     // the plank's front top edge, from the strip's top
            let frontBottom: CGFloat
            let underBack: CGFloat    // where its underside meets the wall
        }
        struct Box: Decodable {
            struct Key: Decodable { let id: String; let rect: [CGFloat] }
            struct VFD: Decodable { let cells: [CGFloat]; let mtx: [CGFloat]; let n: Int }
            let picture: String
            let size: [CGFloat]
            let face: [CGFloat]       // the box's front face (x, y, w, h)
            let plankRow: CGFloat     // where the plank's front top edge falls in this picture
            let keys: [Key]
            let layers: [String: Layer]
            let lamp: [CGFloat]?
            let vfd: VFD?
            /// The box as a unit, for RackMachineKey (its keys' layers k<i>-lit, -down, -litdown).
            var unit: Unit {
                Unit(picture: picture, u: 0, size: size, panel: face, layers: layers, meters: nil, results: nil,
                     preflight: nil, patch: nil, nammeters: nil, deck: nil, cart: nil)
            }
            var pictures: [String] { [picture] + layers.values.map(\.picture) }
        }
        let plank: Plank?
        let boxes: [String: Box]?
    }
    struct Cheeks: Decodable {
        struct V: Decodable { let picture: String; let size: [CGFloat]; let boardLeft: CGFloat; let boardWidth: CGFloat }
        struct H: Decodable { let picture: String; let size: [CGFloat]; let boardTop: CGFloat; let boardBottom: CGFloat }
        let v: V
        let h: H
    }

    /// The panels' width: 48.26 cm.
    var panelWidth: CGFloat { (48.26 * ptPerCm).rounded() }
    var board: CGFloat { cheeks?.v.boardWidth ?? 1.9 * ptPerCm }

    func unit(_ key: String) -> Unit? { units[key] }

    static let shared: RackKit? = {
        let url = SwellKit.folder.appendingPathComponent("irc-rack.json")
        guard let data = try? Data(contentsOf: url), let k = try? JSONDecoder().decode(RackKit.self, from: data),
              let c = k.cheeks else { return nil }
        guard [c.v.picture, c.h.picture].allSatisfy({ SwellPictures.shared.cgImage($0 + ".webp") != nil }) else { return nil }
        return k
    }()
    /// A unit is drawn only when its base and every layer are in the kit.
    static func ready(_ key: String) -> (RackKit, Unit)? {
        guard let k = shared, let u = k.units[key] else { return nil }
        var files = [u.picture] + u.layers.values.map(\.picture)
        if let m = u.meters { files += [m.eye.picture, m.needle.picture] }
        if let r = u.results { files += r.stamps.values.map(\.picture) }
        if let d = u.deck { files += d.pictures }
        files += k.setupPictures(u)
        guard files.allSatisfy({ SwellPictures.shared.cgImage($0 + ".webp") != nil }) else { return nil }
        return (k, u)
    }
}

// ------------------------------------------------------------------ the bay
/// The rack: its boards round the units, the dark inside behind them, its shadow on the wall.
struct RackBay<Content: View>: View {
    let kit: RackKit
    @ViewBuilder let content: Content
    var body: some View {
        let b = kit.board
        VStack(spacing: 0) {
            RackBoard(kit: kit, bottom: false)
            content
                .frame(width: kit.panelWidth, alignment: .topLeading)
                .background(Color(swellHex: 0x060606))      // the inside of the rack, seen between the units
            RackBoard(kit: kit, bottom: true)
        }
        .padding(.horizontal, b)
        .background(alignment: .topLeading) {
            // the rack stands a few centimetres off the wall: its shadow falls right and down from the light
            Rectangle().fill(Color.black.opacity(0.62))
                .padding(.leading, 10).padding(.top, 16).padding(.trailing, -26).padding(.bottom, -30)
                .blur(radius: 16)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .leading) { RackCheek(kit: kit, right: false) }
        .overlay(alignment: .trailing) { RackCheek(kit: kit, right: true) }
    }
}

/// A side board, the full height of the bay: the strip laid end to end (a butt joint every 150 cm), clipped top and
/// bottom; its shadow falls on the wall beside it.
struct RackCheek: View {
    let kit: RackKit
    let right: Bool
    var body: some View {
        if let c = kit.cheeks, let st = SwellPictures.shared.stripImage(c.v.picture, pxPerPoint: kit.pxPerPoint) {
            let cg = st.0, scale = st.1
            let w = CGFloat(cg.width) / scale, len = CGFloat(cg.height) / scale
            Color.clear.frame(width: c.v.boardWidth).frame(maxHeight: .infinity)
                .overlay(alignment: .topLeading) {
                    GeometryReader { g in
                        let n = max(1, Int((g.size.height / max(len, 1)).rounded(.up)))
                        VStack(spacing: 0) {
                            ForEach(0..<n, id: \.self) { i in
                                Image(decorative: cg, scale: scale).resizable().interpolation(.high)
                                    .frame(width: w, height: len)
                                    // the right board and every other length turned end for end: not the same board twice
                                    .scaleEffect(x: 1, y: (i % 2 == 1) != right ? -1 : 1)
                            }
                        }
                        .fixedSize()
                        .offset(x: -c.v.boardLeft)
                    }
                    .mask(Rectangle().padding(.horizontal, -60))
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// The top or bottom board, between the side boards.
struct RackBoard: View {
    let kit: RackKit
    let bottom: Bool
    var body: some View {
        if let c = kit.cheeks, let st = SwellPictures.shared.stripImage(c.h.picture, pxPerPoint: kit.pxPerPoint) {
            let cg = st.0, scale = st.1
            let w = CGFloat(cg.width) / scale, h = CGFloat(cg.height) / scale
            let board = c.h.boardBottom - c.h.boardTop
            // the picture runs on past the board's ends (it is longer than the bay is wide): cut at the side boards;
            // above and below, its shadow and margin show (the top board's shadow falls on the first unit)
            Color.clear.frame(width: kit.panelWidth, height: board)
                .overlay(alignment: .topLeading) {
                    Image(decorative: cg, scale: scale).resizable().interpolation(.high)
                        .frame(width: w, height: h)
                        .scaleEffect(x: bottom ? -1 : 1, y: 1)       // the bottom board: the other end of the strip
                        .offset(y: -c.h.boardTop)
                }
                .mask { Rectangle().padding(.vertical, -max(c.h.boardTop, h - c.h.boardBottom)) }
                .zIndex(1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

// ------------------------------------------------------------------ a unit
/// A unit's base picture with its live layers over it, in a slot u units tall and a panel wide. The picture's shadow
/// margin overhangs the slot. `on`: the layers lit now; lamps are filaments (on 90 ms, off 240 ms), LEDs instant.
struct RackUnitPicture: View {
    let kit: RackKit
    let unit: RackKit.Unit
    var on: Set<String> = []
    var filament = true
    /// Layers the caller draws itself (in `overlay`), not switched here.
    var own: (String) -> Bool = { _ in false }
    /// Drawn over the picture, in the picture's points (origin its top left).
    var overlay: AnyView? = nil
    /// (11-12) Layers that switch at once whatever `filament` says (a selector turned, a toggle thrown).
    var instant: (String) -> Bool = { _ in false }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let p = unit.panel
        ZStack(alignment: .topLeading) {
            if let base = SwellPictures.shared.image(unit.picture, pxPerPoint: kit.pxPerPoint) {
                Image(nsImage: base).resizable().interpolation(.high).frame(width: unit.size[0], height: unit.size[1])
            }
            ForEach(unit.layers.keys.sorted().filter { !own($0) }, id: \.self) { k in
                if let l = unit.layers[k], let img = SwellPictures.shared.image(l.picture, pxPerPoint: kit.pxPerPoint) {
                    let lit = on.contains(k)
                    Image(nsImage: img).resizable().interpolation(.high)
                        .frame(width: l.rect[2], height: l.rect[3])
                        .offset(x: l.rect[0], y: l.rect[1])
                        .opacity(lit ? 1 : 0)
                        .animation(filament && !reduceMotion && !instant(k) ? SwellMotion.filament(lit) : nil, value: lit)
                }
            }
            if let overlay { overlay }
        }
        .frame(width: unit.size[0], height: unit.size[1], alignment: .topLeading)
        .offset(x: -p[0], y: -p[1])
        .frame(width: kit.panelWidth, height: CGFloat(unit.u) * kit.uPt, alignment: .topLeading)
        .accessibilityHidden(true)
    }
}

// ------------------------------------------------------------------ the step strip (1U)
/// The job's steps as a 1U strip: Cab IR's bronze strip with jewels, Amp NAM's graphite strip with flush LEDs. Done
/// steps green, the current step (the first not done) amber, the steps ahead dark. Without the rack's pictures, the
/// old panel (JobStepper).
struct RackStepStrip: View {
    let steps: [(String, Bool)]
    @Environment(\.swellTheme) private var theme
    var body: some View {
        let key = theme == .nam ? "step-nam" : "step-cab"
        if let r = RackKit.ready(key), r.1.layers.count >= 2 * steps.count {
            let kit = r.0, u = r.1
            let current = steps.firstIndex { !$0.1 }
            let on = Set(steps.indices.compactMap { i -> String? in
                steps[i].1 ? "l\(i)-green" : (i == current ? "l\(i)-amber" : nil)
            })
            RackUnitPicture(kit: kit, unit: u, on: on, filament: theme != .nam)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(steps.enumerated().map { i, s in
                    "Step \(i + 1), \(s.0): \(s.1 ? "done" : i == current ? "current" : "not done")"
                }.joined(separator: ". "))
        } else {
            JobStepper(steps: steps)
        }
    }
}

// ------------------------------------------------------------------ the meter bridge (5U)
/// One input on the meter bridge, as its module shows it.
struct RackChannel: Identifiable {
    let id: Int
    let name: String
    /// Peak minus target (0 VU is the target); nil rests the needle.
    var vu: Double? = nil
    /// The peak in dBFS for the gas digits; nil leaves them dark.
    var peak: Double? = nil
    /// The lamps lit: 0 LOW, 1 OK, 2 HIGH, 3 CLIP, 4 DIST.
    var lamps: Set<Int> = []
    var eye: (closure: Double?, lit: Bool) = (nil, false)
    /// For VoiceOver: the module's state in words.
    var spoken: String = "no reading"
}

/// The meter bridge (5U, design/render/ircapture_rack_layers.py `meters`): a frame holding four channel modules, one
/// for each input in use; a slot with no input holds a blank filler plate. Each module: IR Capture's VU (its lamp warms
/// with the power clock; the needle on the VU spring), the peak on gas digits lit by the app on the render's geometry,
/// the noise eye, the lamp row LOW · OK · HIGH · CLIP · DIST (jewels: filaments), the mic's name on its scribble strip.
/// More than four inputs: a second bridge under the first.
struct RackMeterBridge: View {
    let channels: [RackChannel]
    /// A mic's name to write on its strip (typed into the tape); nil: the name as given, not editable.
    var names: ((Int) -> Binding<String>?)? = nil
    @ObservedObject private var clock = PowerClock.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static var available: Bool { RackKit.ready("meters")?.1.meters != nil }

    var body: some View {
        if let r = RackKit.ready("meters"), let mt = r.1.meters {
            let kit = r.0, u = r.1
            let n = min(channels.count, mt.modules.count)
            let on = lit(n: n, slots: mt.modules.count)
            ZStack(alignment: .topLeading) {
                RackUnitPicture(kit: kit, unit: u, on: on, own: { $0.hasSuffix("-vu") },
                                overlay: AnyView(modules(kit: kit, u: u, mt: mt, n: n)))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Level meters")
                    .accessibilityValue(channels.prefix(n).map { "\($0.name): \($0.spoken)" }.joined(separator: ". "))
                // the strips that take a name: typed into the tape, outside the picture (so VoiceOver reaches them)
                ZStack(alignment: .topLeading) {
                    ForEach(0..<n, id: \.self) { i in
                        if let b = names?(channels[i].id) {
                            RackStripField(name: b, strip: mt.modules[i].strip, tilt: i % 2 == 0 ? -0.5 : 0.5,
                                           input: channels[i].id + 1)
                        }
                    }
                }
                .frame(width: u.size[0], height: u.size[1], alignment: .topLeading)
                .offset(x: -u.panel[0], y: -u.panel[1])
            }
            .frame(width: kit.panelWidth, height: CGFloat(u.u) * kit.uPt, alignment: .topLeading)
        }
    }

    /// The layers shown: each slot past the inputs a blank plate, each lit lamp.
    func lit(n: Int, slots: Int) -> Set<String> {
        var on = Set<String>()
        for i in 0..<slots where i >= n { on.insert("b\(i)") }
        for i in 0..<n { for k in channels[i].lamps { on.insert("m\(i)-l\(k)") } }
        return on
    }

    @ViewBuilder func modules(kit: RackKit, u: RackKit.Unit, mt: RackKit.Meters, n: Int) -> some View {
        ZStack(alignment: .topLeading) {
            // the VU lamps, warming with the power clock
            TimelineView(.animation(paused: !clock.warming || reduceMotion)) { ctx in
                let glow = reduceMotion ? 1 : clock.lampGlow(at: ctx.date)
                ZStack(alignment: .topLeading) {
                    ForEach(0..<n, id: \.self) { i in
                        if let l = u.layers["m\(i)-vu"], let img = SwellPictures.shared.image(l.picture, pxPerPoint: kit.pxPerPoint) {
                            Image(nsImage: img).resizable().interpolation(.high)
                                .frame(width: l.rect[2], height: l.rect[3]).offset(x: l.rect[0], y: l.rect[1])
                                .opacity(glow)
                        }
                    }
                }
                .frame(width: u.size[0], height: u.size[1], alignment: .topLeading)
            }
            ForEach(0..<n, id: \.self) { i in
                let md = mt.modules[i], ch = channels[i]
                RackNeedle(kit: kit, mt: mt, md: md, size: u.size, vu: ch.vu)
                if let p = ch.peak {
                    SegCanvas(text: GasDigits.text(p, n: md.gasN),
                              d: GasKit.Display(file: "", pt: u.size, px_per_pt: kit.pxPerPoint, bezel: [0, 0, u.size[0], u.size[1]],
                                                cells: md.gas, n: md.gasN, mtx: nil, pitch: 1.3, slant: 8))
                        .frame(width: u.size[0], height: u.size[1])
                }
                if ch.eye.lit {
                    RackEye(kit: kit, eye: mt.eye, closure: ch.eye.closure)
                        .offset(x: md.eye[0] - mt.eye.center[0], y: md.eye[1] - mt.eye.center[1])
                }
                if names?(ch.id) == nil { RackStripName(name: ch.name, strip: md.strip, tilt: i % 2 == 0 ? -0.5 : 0.5) }
            }
        }
        .frame(width: u.size[0], height: u.size[1], alignment: .topLeading)
    }
}

/// A VU's needle: the rendered needle turned about its pivot on the VU spring, its shadow on the card, seen only
/// through the window.
private struct RackNeedle: View {
    let kit: RackKit
    let mt: RackKit.Meters
    let md: RackKit.Meters.Module
    let size: [CGFloat]
    let vu: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var angle: Double {
        let t = mt.vuTable.filter { $0.count == 2 }.map { ($0[0], $0[1]) }
        return VUMeter.angle(vu, table: t)
    }
    var body: some View {
        let N = mt.needle, w = md.vuWindow
        let anchor = UnitPoint(x: N.pivot[0] / N.size[0], y: N.pivot[1] / N.size[1])
        let x = md.vuPivot[0] - N.pivot[0], y = md.vuPivot[1] - N.pivot[1]
        let a = angle
        if let img = SwellPictures.shared.image(N.picture, pxPerPoint: kit.pxPerPoint) {
            ZStack(alignment: .topLeading) {
                // its shadow on the card: down and right of it (the light is up and to the left)
                Image(nsImage: img).resizable().interpolation(.high).frame(width: N.size[0], height: N.size[1])
                    .colorMultiply(.black).opacity(0.34).blur(radius: 0.8)
                    .rotationEffect(.degrees(a), anchor: anchor)
                    .offset(x: x + 0.7, y: y + 1.0)
                Image(nsImage: img).resizable().interpolation(.high).frame(width: N.size[0], height: N.size[1])
                    .rotationEffect(.degrees(a), anchor: anchor)
                    .offset(x: x, y: y)
            }
            .animation(reduceMotion ? nil : SwellMotion.vuSpring, value: a)
            .frame(width: size[0], height: size[1], alignment: .topLeading)
            .mask(alignment: .topLeading) {
                Rectangle().frame(width: w[2], height: w[3]).offset(x: w[0], y: w[1])
            }
        }
    }
}

/// The noise eye of a module: the bore's states from the sheet (module 0's eye, the same tube in every module), the two
/// frames round the exact closure summed as MagicEye does; the tube's glow comes up with the power clock.
private struct RackEye: View {
    let kit: RackKit
    let eye: RackKit.Meters.Eye
    let closure: Double?
    @ObservedObject private var clock = PowerClock.shared
    @State private var shown = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var target: Double { max(0, min(Double(eye.states.count - 4), (closure ?? 0) * Double(eye.states.count - 4))) }
    func cell(_ i: Int) -> NSImage? {
        let w = (eye.cell[0] * kit.pxPerPoint).rounded(), h = (eye.cell[1] * kit.pxPerPoint).rounded()
        let r = CGRect(x: CGFloat(i % eye.perRow) * w, y: CGFloat(i / eye.perRow) * h, width: w, height: h)
        return SwellPictures.shared.sprite(eye.picture + ".webp", rect: r, pxPerPoint: kit.pxPerPoint)
    }
    var body: some View {
        TimelineView(.animation(paused: !clock.warming || reduceMotion)) { ctx in
            let glow = reduceMotion ? 1 : clock.eyeGlow(at: ctx.date)
            ZStack(alignment: .topLeading) {
                if glow < 1, let w = cell(2) {
                    Image(nsImage: w).resizable().interpolation(.high).opacity(min(1, glow * 3) * (1 - glow))
                }
                MagicEye.EyeFrames(x: reduceMotion ? target.rounded() : target) { n in cell(n) }
                    .animation(reduceMotion ? nil : SwellMotion.eye(closing: target > shown), value: target)
                    .opacity(glow)
            }
            .frame(width: eye.cell[0], height: eye.cell[1], alignment: .topLeading)
        }
        .onChange(of: target) { shown = $0 }
        .onAppear { shown = target }
    }
}

/// The mic's name hand-lettered on a module's scribble strip (the tape is in the base picture).
struct RackStripName: View {
    let name: String
    let strip: [CGFloat]
    let tilt: Double
    var body: some View {
        let inset: CGFloat = 10.5                       // 0.75 cm, as the render letters it
        let avail = strip[2] - 2 * inset
        let fit = MarkerFit.fit(name, avail: avail)
        Text(name).font(.swellMarker(fit.size)).lineLimit(fit.lines).lineSpacing(-3)
            .foregroundColor(MarkerFit.ink.opacity(0.92))
            .frame(width: avail, height: strip[3] - 2, alignment: .leading)
            .rotationEffect(.degrees(tilt))
            .offset(x: strip[0] + inset, y: strip[1] + 1)
            .accessibilityHidden(true)
    }
}

/// A mic's strip that takes its name: the name as written on the tape; while it is typed, the field itself (one line).
/// The common names on the strip's context menu.
private struct RackStripField: View {
    @Binding var name: String
    let strip: [CGFloat]
    let tilt: Double
    let input: Int
    @FocusState private var focused: Bool
    var body: some View {
        let inset: CGFloat = 10.5
        let avail = strip[2] - 2 * inset
        let fit = MarkerFit.fit(name, avail: avail)
        ZStack(alignment: .leading) {
            if !focused {
                if name.isEmpty {
                    Text("Mic name").font(.swellMarker(13)).foregroundColor(MarkerFit.ink.opacity(0.28))
                } else {
                    Text(name).font(.swellMarker(fit.size)).lineLimit(fit.lines).lineSpacing(-3)
                        .foregroundColor(MarkerFit.ink.opacity(0.92))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            TextField("", text: $name)
                .textFieldStyle(.plain)
                .font(.swellMarker(fit.lines == 2 ? 10.5 : fit.size))
                .foregroundColor(MarkerFit.ink.opacity(0.92))
                .focused($focused)
                .opacity(focused ? 1 : 0.001)
                .accessibilityLabel("Mic name, input \(input)")
        }
        .frame(width: avail, height: strip[3] - 2, alignment: .leading)
        .contextMenu {
            ForEach(commonMicNames, id: \.self) { n in Button(n) { name = n } }
        }
        .help("Enter the mic name. The name is used in the file names. Right-click for common names.")
        .rotationEffect(.degrees(tilt))
        .offset(x: strip[0] + inset, y: strip[1] + 1)
    }
}

/// The meter bridges for the inputs in use, four to a bridge. Without the bridge's pictures, nothing (the caller keeps
/// the old meters).
struct RackMeterBay: View {
    @EnvironmentObject var m: AppModel
    /// The name of a mic input (not the reference), for its strip.
    func nameBinding(_ ch: Int) -> Binding<String>? {
        guard let i = m.inputs.firstIndex(where: { $0.id == ch }), m.inputs[i].role == .mic else { return nil }
        return Binding(get: { m.inputs.first { $0.id == ch }?.name ?? "" },
                       set: { v in if let j = m.inputs.firstIndex(where: { $0.id == ch }) { m.inputs[j].name = v } })
    }
    var body: some View {
        let ch = m.meterChannels
        let groups = stride(from: 0, to: max(ch.count, 1), by: 4).map { Array(ch[min($0, ch.count)..<min($0 + 4, ch.count)]) }
        VStack(spacing: 0) {
            ForEach(Array(groups.enumerated()), id: \.offset) { _, g in
                // with the patch unit, the mic names are written here (the patch has no strips)
                RackMeterBridge(channels: g, names: RackPatchBay.available ? { ch in nameBinding(ch) } : nil)
            }
        }
    }
}

extension AppModel {
    /// Each input in use (mic or reference), in the interface's order, with its latest level reading.
    var meterChannels: [RackChannel] {
        inputs.filter { $0.role != .off }.sorted { $0.id < $1.id }.map { row in
            let r = levelReadings.first { $0.channel == row.id }
            var c = RackChannel(id: row.id, name: row.role == .mic ? row.name : label(for: row.id))
            c.eye = (nil, levelRunning)
            guard let r else { return c }
            c.peak = r.peakDBFS
            let noSignal = r.peakDBFS < -60
            c.vu = noSignal ? nil : -r.changeDB
            let d = r.changeDB
            if noSignal || d > 3 { c.lamps.insert(0) } else if d < -3 { c.lamps.insert(2) } else if !r.clipped { c.lamps.insert(1) }
            if r.clipped { c.lamps.insert(3) }
            if row.role != .ref && max(r.h2, r.h3) > -40 { c.lamps.insert(4) }
            if let n = noise[r.channel] {
                c.eye = (noSignal ? 0 : max(0, min(1, (r.peakDBFS - n - 20) / 40)), true)
            }
            let words = [r.clipped ? "clipping" : nil, noSignal ? "no signal" : abs(d) <= 3 ? "level OK" : String(format: "%+.0f dB from the target", -d),
                         c.lamps.contains(4) ? "distortion" : nil].compactMap { $0 }
            c.spoken = words.joined(separator: ", ") + String(format: ", peak %.1f dBFS", r.peakDBFS)
            return c
        }
    }

    /// The level check's advice for the input that most needs it, for the shelf's VFD (the sentence that stood under
    /// each meter): clipping first, then no signal, then the largest correction, then distortion.
    var levelGuidance: String? {
        let rs = levelReadings
        guard !rs.isEmpty else { return nil }
        func short(_ s: String) -> String {
            if s.hasPrefix("Input ") { return "IN " + s.dropFirst(6) }
            return String((s.split(separator: " ").first.map(String.init) ?? s).prefix(9)).uppercased()
        }
        if let r = rs.first(where: \.clipped) { return "CLIP  TURN \(short(r.label)) DOWN" }
        if let r = rs.first(where: { $0.peakDBFS < -60 }) { return "CHECK \(short(r.label)) CABLE" }
        if let r = rs.filter({ $0.label != "Reference" && abs($0.changeDB) > 3 }).max(by: { abs($0.changeDB) < abs($1.changeDB) }) {
            return "TURN \(short(r.label)) \(r.changeDB > 0 ? "UP" : "DOWN") \(Int(abs(r.changeDB).rounded())) DB"
        }
        if rs.contains(where: { $0.label != "Reference" && max($0.h2, $0.h3) > -30 }) { return "LOWER THE AMP VOLUME" }
        return "LEVELS OK"
    }
}

extension View {
    /// The rack bay round the page's steps when the kit has it, the stage opening otherwise.
    @ViewBuilder func inRackBay() -> some View {
        if let k = RackKit.shared {
            RackBay(kit: k) { self }
        } else {
            self
        }
    }
}
#endif
