#if os(macOS)
import SwiftUI
import IRCaptureCore

// RackNAMMeters.swift: the NAM meter bridge (3U, Phase 7a; the third proof's unit_nammeters, approved "10/10 no notes").
//
// The solid-state rack's meters (design/render/ircapture_rack_layers.py `nammeters`): a graphite frame holding four
// channel modules, one for each input in use; a slot with no input holds a blank filler plate. Each module:
//   - twenty LED bars, -40 to 0 dBFS in 2 dB steps (green to -6, amber to -2, red), behind smoked glass. The render
//     holds every bar lit (`m<i>-bars`); the app shows the bars up to the level, and the peak-hold bar, through a mask
//     of their columns, as a real bargraph lights a run of bars.
//   - the peak in dBFS on four red seven-segment cells behind a red filter. The render holds every segment lit
//     (`m<i>-dig`); the app shows the lit segments through a mask of their outlines (`segs`, `cells`).
//   - LOW · OK · HIGH · CLIP as flush LEDs (`m<i>-l<k>`), lit instantly.
//   - the input's name on its scribble strip.
// LEDs are instant (Motion rules): nothing eases.

extension RackKit {
    struct NAMMeters: Decodable {
        struct Module: Decodable {
            let bars: [[CGFloat]]        // each bar's column (x, y, w, h): a bar pitch wide, the bar's height
            let segs: [[[CGFloat]]]      // each segment's outline (corners, pt)
            let cells: [[Int]]           // each cell's segments a b c d e f g and the point, as indices into segs
            let leds: [[CGFloat]]        // each LED's centre
            let strip: [CGFloat]         // the scribble strip (the tape)
        }
        let lamps: [String]              // LOW OK HIGH CLIP
        let db0: Double                  // the first bar's lower edge (dBFS)
        let dbStep: Double               // dB a bar
        let colours: [String]
        let modules: [Module]
    }
}

/// One input on the NAM meter bridge.
struct RackNAMChannel: Identifiable {
    let id: Int
    let name: String
    /// The bargraph's level (dBFS); nil: every bar dark.
    var level: Double? = nil
    /// The peak held over the last few seconds (dBFS): the peak-hold bar and the digits; nil: dark.
    var peak: Double? = nil
    /// The LEDs lit: 0 LOW, 1 OK, 2 HIGH, 3 CLIP.
    var lamps: Set<Int> = []
    var spoken: String = "no reading"
}

struct RackNAMMeterBridge: View {
    let channels: [RackNAMChannel]

    static var available: Bool { RackKit.ready("nammeters")?.1.nammeters != nil }

    var body: some View {
        if let r = RackKit.ready("nammeters"), let nm = r.1.nammeters {
            let kit = r.0, u = r.1
            let n = min(channels.count, nm.modules.count)
            RackUnitPicture(kit: kit, unit: u, on: lit(n: n, slots: nm.modules.count), filament: false,
                            own: { $0.hasSuffix("-bars") || $0.hasSuffix("-dig") },
                            overlay: AnyView(modules(kit: kit, u: u, nm: nm, n: n)))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Level meters")
                .accessibilityValue(n == 0 ? "No inputs in use" : channels.prefix(n).map { "\($0.name): \($0.spoken)" }.joined(separator: ". "))
        }
    }

    func lit(n: Int, slots: Int) -> Set<String> {
        var on = Set<String>()
        for i in 0..<slots where i >= n { on.insert("b\(i)") }
        for i in 0..<n { for k in channels[i].lamps { on.insert("m\(i)-l\(k)") } }
        return on
    }

    /// The bars lit for a level: as many as the level reaches, rounded (the proof's rule).
    static func bars(_ db: Double?, nm: RackKit.NAMMeters, count: Int) -> Int {
        guard let db else { return 0 }
        return max(0, min(count, Int(((db - nm.db0) / nm.dbStep).rounded())))
    }

    @ViewBuilder func modules(kit: RackKit, u: RackKit.Unit, nm: RackKit.NAMMeters, n: Int) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<n, id: \.self) { i in
                let md = nm.modules[i], ch = channels[i]
                let shown = Self.shownBars(ch, nm: nm, count: md.bars.count)
                if !shown.isEmpty, let l = u.layers["m\(i)-bars"] {
                    MaskedLayer(kit: kit, size: u.size, layer: l) { p in
                        for b in shown.sorted() {
                            let r = md.bars[b]
                            p.addRect(CGRect(x: r[0], y: r[1] - 5, width: r[2], height: r[3] + 10))
                        }
                    }
                }
                let lit = Self.segments(ch.peak, cells: md.cells)
                if !lit.isEmpty, let l = u.layers["m\(i)-dig"] {
                    MaskedLayer(kit: kit, size: u.size, layer: l, grow: 1.6) { p in
                        for s in lit.sorted() where s < md.segs.count {
                            let c = md.segs[s]
                            guard let f = c.first, f.count == 2 else { continue }
                            p.move(to: CGPoint(x: f[0], y: f[1]))
                            for q in c.dropFirst() where q.count == 2 { p.addLine(to: CGPoint(x: q[0], y: q[1])) }
                            p.closeSubpath()
                        }
                    }
                }
                RackStripName(name: ch.name, strip: md.strip, tilt: i % 2 == 0 ? -0.5 : 0.5)
            }
        }
        .frame(width: u.size[0], height: u.size[1], alignment: .topLeading)
    }

    /// The bars shown: the run up to the level, and the peak-hold bar.
    static func shownBars(_ ch: RackNAMChannel, nm: RackKit.NAMMeters, count: Int) -> Set<Int> {
        var on = Set(0..<bars(ch.level, nm: nm, count: count))
        let hold = bars(ch.peak, nm: nm, count: count) - 1
        if hold >= 0 { on.insert(hold) }
        return on
    }

    static let seg7: [Character: String] = ["0": "abcdef", "1": "bc", "2": "abdeg", "3": "abcdg", "4": "bcfg", "5": "acdfg",
                                            "6": "acdefg", "7": "abc", "8": "abcdefg", "9": "abcdfg", "-": "g", " ": ""]

    /// The cells' text for a peak: one decimal, right-aligned in the cells, the point lit after the units digit;
    /// below -99.9 dBFS (no signal), dashes.
    static func cellText(_ db: Double?, n: Int) -> [(Character, Bool)] {
        guard let db else { return [] }
        let blank: (Character, Bool) = (" ", false), dash: (Character, Bool) = ("-", false)
        if db < -99.9 { return Array(repeating: blank, count: max(0, n - 3)) + Array(repeating: dash, count: min(n, 3)) }
        let s = String(format: "%.1f", min(0, db)).replacingOccurrences(of: "-0.0", with: "0.0")
        var cells: [(Character, Bool)] = []
        for c in s {
            if c == ".", !cells.isEmpty { cells[cells.count - 1].1 = true } else { cells.append((c, false)) }
        }
        if cells.count > n { cells = Array(cells.suffix(n)) }
        return Array(repeating: blank, count: n - cells.count) + cells
    }

    static let segIndex: [Character: Int] = ["a": 0, "b": 1, "c": 2, "d": 3, "e": 4, "f": 5, "g": 6]

    /// The segments lit (indices into the module's segs).
    static func segments(_ db: Double?, cells: [[Int]]) -> Set<Int> {
        var on = Set<Int>()
        for (k, (c, dp)) in cellText(db, n: cells.count).enumerated() {
            let cell = cells[k]
            guard cell.count == 8 else { continue }
            for ch in seg7[c] ?? "" { if let j = segIndex[ch] { on.insert(cell[j]) } }
            if dp { on.insert(cell[7]) }
        }
        return on
    }
}

/// A layer of a unit's picture shown only through a path (the picture's points).
struct MaskedLayer: View {
    let kit: RackKit
    let size: [CGFloat]
    let layer: RackKit.Layer
    var grow: CGFloat = 0
    let path: (inout Path) -> Void
    var body: some View {
        if let img = SwellPictures.shared.image(layer.picture, pxPerPoint: kit.pxPerPoint) {
            let shape = Path { p in path(&p) }
            ZStack(alignment: .topLeading) {
                Image(nsImage: img).resizable().interpolation(.high)
                    .frame(width: layer.rect[2], height: layer.rect[3])
                    .offset(x: layer.rect[0], y: layer.rect[1])
            }
            .frame(width: size[0], height: size[1], alignment: .topLeading)
            .mask(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    shape.fill(Color.white)
                    if grow > 0 { shape.stroke(Color.white, style: StrokeStyle(lineWidth: 2 * grow, lineJoin: .round)) }
                }
                .frame(width: size[0], height: size[1], alignment: .topLeading)
            }
        }
    }
}

/// The NAM meter bridges for the inputs in use, four to a bridge; none in use: one bridge of blank plates.
struct RackNAMMeterBay: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        let ch = m.namMeterChannels
        let groups = stride(from: 0, to: max(ch.count, 1), by: 4).map { Array(ch[min($0, ch.count)..<min($0 + 4, ch.count)]) }
        VStack(spacing: 0) {
            ForEach(Array(groups.enumerated()), id: \.offset) { _, g in RackNAMMeterBridge(channels: g) }
        }
    }
}

extension AppModel {
    /// Each input set to Use, in the interface's order, with its latest reading. The target is -8 dBFS (NAMMeterTable):
    /// OK within 3 dB, LOW below, HIGH above, CLIP once clipped; no signal lights LOW.
    var namMeterChannels: [RackNAMChannel] {
        namRows.filter(\.use).sorted { $0.id < $1.id }.map { row in
            var c = RackNAMChannel(id: row.id, name: row.name.isEmpty ? "Input \(row.id + 1)" : row.name)
            guard let x = namMeters.first(where: { $0.id == row.id }) else { return c }
            c = RackNAMChannel.reading(id: row.id, name: c.name, peak: x.peakDB, level: x.levelDB, clipped: x.clipped)
            return c
        }
    }
}

extension RackNAMChannel {
    /// A module's state from a reading (peak held in dBFS, the bargraph's level, clipped).
    static func reading(id: Int, name: String, peak: Double, level: Double, clipped: Bool) -> RackNAMChannel {
        var c = RackNAMChannel(id: id, name: name)
        let noSignal = peak < -60
        c.peak = peak
        c.level = level
        let change = NAMMeterTable.target - peak
        if clipped { c.lamps.insert(3) }
        if noSignal || change > 3 { c.lamps.insert(0) } else if change < -3 { c.lamps.insert(2) } else if !clipped { c.lamps.insert(1) }
        let words = [clipped ? "clipping" : nil,
                     noSignal ? "no signal" : abs(change) <= 3 ? "level OK" : String(format: "%+.0f dB from the target", -change)].compactMap { $0 }
        c.spoken = words.joined(separator: ", ") + (noSignal ? "" : String(format: ", peak %.1f dBFS", peak))
        return c
    }
}
#endif
