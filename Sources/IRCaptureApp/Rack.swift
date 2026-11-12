#if os(macOS)
import SwiftUI

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

    struct Unit: Decodable {
        let picture: String
        let u: Int
        let size: [CGFloat]          // the picture, pt
        let panel: [CGFloat]         // the unit's slot in the picture: x, y, width, height (pt)
        let layers: [String: Layer]
    }
    struct Layer: Decodable {
        let picture: String
        let rect: [CGFloat]          // in the base picture, pt
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
        let files = [u.picture] + u.layers.values.map(\.picture)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let p = unit.panel
        ZStack(alignment: .topLeading) {
            if let base = SwellPictures.shared.image(unit.picture, pxPerPoint: kit.pxPerPoint) {
                Image(nsImage: base).resizable().interpolation(.high).frame(width: unit.size[0], height: unit.size[1])
            }
            ForEach(unit.layers.keys.sorted(), id: \.self) { k in
                if let l = unit.layers[k], let img = SwellPictures.shared.image(l.picture, pxPerPoint: kit.pxPerPoint) {
                    let lit = on.contains(k)
                    Image(nsImage: img).resizable().interpolation(.high)
                        .frame(width: l.rect[2], height: l.rect[3])
                        .offset(x: l.rect[0], y: l.rect[1])
                        .opacity(lit ? 1 : 0)
                        .animation(filament && !reduceMotion ? SwellMotion.filament(lit) : nil, value: lit)
                }
            }
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
