#if os(macOS)
import SwiftUI
import AppKit

// Lettering.swift (11-11, Lowell's lettering plan): fixed legends printed in the render, live text on a part made for it.
//   PrintedKeys      the keys with their legends rendered on the cap (irc-legends.json); KeyButtonStyle draws one when
//                    its key name is in the table, its label kept for VoiceOver only
//   ScribbleStrip    a mic name hand-lettered (Swell Marker) on a strip of masking tape (irc-scribble.json)
//   VFDStatusLine    the shelf's status on the bench's VFD dot matrix: blue-green, one line (irc-gas.json "line")
//   GasDigits        an input's dBFS on orange seven-segment gas digits (irc-gas.json "dig")
// The displays follow the bench's views/gasdisp.js: the render holds them dark, the app lights the dots and segments
// over its cells with the render's geometry. Each reading is drawn once (SwiftUI redraws a Canvas only when its input
// changes); a digit changes at once, as a gas or a phosphor does.

// ------------------------------------------------------------------ the printed keys
struct PrintedKeys: Decodable {
    struct Key: Decodable {
        let legend: String
        let size: String
        let names: [String]
        /// The picture's size in points (the key, its bezel and outset_pt of shadow round it).
        let pt: [CGFloat]
        let outset_pt: CGFloat
        let files: [String: String]
    }
    let px_per_pt: CGFloat
    var keys: [String: Key]

    static let shared: PrintedKeys? = {
        let url = SwellKit.folder.appendingPathComponent("irc-legends.json")
        guard let data = try? Data(contentsOf: url), var p = try? JSONDecoder().decode(PrintedKeys.self, from: data) else { return nil }
        p.keys = p.keys.filter { _, k in
            ["off", "lit", "down", "litdown"].allSatisfy { st in k.files[st].map { SwellPictures.shared.cgImage($0 + ".webp") != nil } ?? false }
        }
        return p.keys.isEmpty ? nil : p
    }()

    /// The name as ircapture_legends.norm() has it: lowercased, a leading "‹ " and a trailing "…" or "." dropped.
    static func norm(_ s: String) -> String {
        var t = s.lowercased().trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("‹ ") { t.removeFirst(2) }
        while t.hasSuffix("…") || t.hasSuffix(".") { t.removeLast() }
        return t
    }
    private static let index: [String: Key] = {
        var d: [String: Key] = [:]
        for k in shared.map({ Array($0.keys.values) }) ?? [] { for n in k.names { d[k.size + "|" + norm(n)] = k } }
        return d
    }()
    /// The printed key for a button's name, nil if it has none (that button keeps the blank cap and its label).
    static func key(for name: String?, big: Bool) -> Key? {
        guard let name else { return nil }
        return index[(big ? "big" : "std") + "|" + norm(name)]
    }
    static func image(_ file: String) -> NSImage? { shared.flatMap { SwellPictures.shared.image(file, pxPerPoint: $0.px_per_pt) } }
}

// ------------------------------------------------------------------ the scribble strip
struct ScribbleKit: Decodable {
    struct Strip: Decodable {
        let file: String
        let pt: [CGFloat]
        /// The tape itself in the picture (x, y, w, h); the rest is its shadow.
        let tape: [CGFloat]
        /// Where the name is written (x from, x to) and the strip's middle line.
        let write: [CGFloat]
        let mid: CGFloat
    }
    let px_per_pt: CGFloat
    let strips: [String: Strip]
    static let shared: ScribbleKit? = {
        let url = SwellKit.folder.appendingPathComponent("irc-scribble.json")
        guard let data = try? Data(contentsOf: url), let k = try? JSONDecoder().decode(ScribbleKit.self, from: data),
              !k.strips.isEmpty, k.strips.values.allSatisfy({ SwellPictures.shared.cgImage($0.file + ".webp") != nil }) else { return nil }
        return k
    }()
    func strip(_ i: Int) -> Strip? {
        let v = strips.keys.sorted()
        return v.isEmpty ? nil : strips[v[((i % v.count) + v.count) % v.count]]
    }
}

extension Font {
    /// A name hand-lettered on a scribble strip: Swell Marker (Permanent Marker, Apache 2.0, renamed).
    static func swellMarker(_ size: CGFloat) -> Font { .custom("SwellMarker-Regular", size: size) }
}

enum MarkerFit {
    static let ink = Color(swellHex: 0x1B1712)
    static func width(_ s: String, _ size: CGFloat) -> CGFloat {
        let f = NSFont(name: "SwellMarker-Regular", size: size) ?? NSFont.systemFont(ofSize: size)
        return (s as NSString).size(withAttributes: [.font: f]).width
    }
    /// The name's size on a strip `avail` wide: 15 pt, shrunk to 10.5; past that, two lines of up to 9.5 pt.
    static func fit(_ s: String, avail: CGFloat) -> (size: CGFloat, lines: Int) {
        let t = s.isEmpty ? "SM57" : s
        let w15 = width(t, 15)
        if w15 <= avail { return (15, 1) }
        let one = 15 * avail / w15
        if one >= 10.5 { return (one, 1) }
        let two = min(9.5, max(7, 15 * (avail * 1.85) / w15))
        return (two, 2)
    }
}

/// A mic name hand-lettered on a strip of masking tape, live: typed into the strip, with the common names on the
/// chevron beside it. `strip` picks one of the four strips (each its own length, tear and age). Without the strips in
/// the kit the name stays in its glass window.
struct ScribbleNameField: View {
    @Binding var name: String
    var disabled = false
    var strip = 0
    @FocusState private var focused: Bool
    var body: some View {
        if let kit = ScribbleKit.shared, let s = kit.strip(strip), let img = SwellPictures.shared.image(s.file, pxPerPoint: kit.px_per_pt) {
            let avail = s.write[1] - s.write[0]
            let fit = MarkerFit.fit(name, avail: avail)
            let ink = MarkerFit.ink.opacity(disabled ? 0.45 : 0.92)
            HStack(spacing: 4) {
                ZStack(alignment: .topLeading) {
                    Image(nsImage: img).resizable().frame(width: s.pt[0], height: s.pt[1])
                        .accessibilityHidden(true)
                    // the name as written on the strip; while it is being typed, the field itself (one line)
                    ZStack(alignment: .leading) {
                        if !focused {
                            if name.isEmpty {
                                Text("Mic name").font(.swellMarker(13)).foregroundColor(MarkerFit.ink.opacity(0.28))
                            } else {
                                Text(name).font(.swellMarker(fit.size)).lineLimit(fit.lines).lineSpacing(-3)
                                    .foregroundColor(ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        TextField("", text: $name)
                            .textFieldStyle(.plain)
                            .font(.swellMarker(fit.lines == 2 ? 10.5 : fit.size))
                            .foregroundColor(ink)
                            .focused($focused)
                            .opacity(focused ? 1 : 0.001)
                            .accessibilityLabel("Mic name")
                    }
                    .frame(width: avail, height: s.tape[3] - 2, alignment: .leading)
                    .rotationEffect(.degrees(-0.5))
                    .offset(x: s.write[0], y: s.mid - (s.tape[3] - 2) / 2)
                }
                .frame(width: s.pt[0], height: s.pt[1], alignment: .topLeading)
                // laid out as the tape alone: its shadow and margin fall outside
                .padding(EdgeInsets(top: -s.tape[1], leading: -s.tape[0],
                                    bottom: -(s.pt[1] - s.tape[1] - s.tape[3]), trailing: -(s.pt[0] - s.tape[0] - s.tape[2])))
                Button {
                    PopUpMenu.show(commonMicNames.map { n in (title: n, checked: n == name, action: { name = n }) })
                } label: { GlassChevron().padding(5).contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .help("Common mic names")
                .accessibilityLabel("Common mic names")
            }
            .disabled(disabled)
        } else {
            MicNameField(name: $name, disabled: disabled)
        }
    }
}

// ------------------------------------------------------------------ the displays
struct GasKit: Decodable {
    struct Display: Decodable {
        let file: String
        let pt: [CGFloat]
        let px_per_pt: CGFloat
        /// The bezel in the picture (x, y, w, h): the display's layout box. The picture runs past it (the shadow).
        let bezel: [CGFloat]
        /// The display's face in the picture (x, y, w, h).
        let cells: [CGFloat]
        let n: Int
        let mtx: [CGFloat]?
        let pitch: CGFloat?
        let slant: CGFloat?
        var cellsRect: CGRect { CGRect(x: cells[0], y: cells[1], width: cells[2], height: cells[3]) }
        var image: NSImage? { SwellPictures.shared.image(file, pxPerPoint: px_per_pt) }
    }
    let displays: [String: Display]
    static let shared: GasKit? = {
        let url = SwellKit.folder.appendingPathComponent("irc-gas.json")
        guard let data = try? Data(contentsOf: url), let k = try? JSONDecoder().decode(GasKit.self, from: data) else { return nil }
        return k
    }()
    static func display(_ kind: String) -> Display? {
        guard let d = shared?.displays[kind], SwellPictures.shared.cgImage(d.file + ".webp") != nil else { return nil }
        return d
    }
    /// A dot's or a segment's own brightness, fixed by its place (gasdisp.js hash).
    static func hash(_ a: Int, _ b: Int) -> Double {
        var h = Int32(truncatingIfNeeded: a &* 374761393 &+ b &* 668265263)
        h = (h ^ Int32(bitPattern: UInt32(bitPattern: h) >> 13)) &* 1274126177
        let u = UInt32(bitPattern: h ^ Int32(bitPattern: UInt32(bitPattern: h) >> 16))
        return Double(u) / 4294967296
    }
}

/// The bezel box of a display picture: the picture drawn round it, its shadow outside the layout.
private struct DisplayPicture<Overlay: View>: View {
    let d: GasKit.Display
    @ViewBuilder var overlay: Overlay
    var body: some View {
        ZStack(alignment: .topLeading) {
            if let img = d.image { Image(nsImage: img).resizable().frame(width: d.pt[0], height: d.pt[1]).accessibilityHidden(true) }
            overlay
        }
        .frame(width: d.pt[0], height: d.pt[1], alignment: .topLeading)
        .offset(x: -d.bezel[0], y: -d.bezel[1])
        .frame(width: d.bezel[2], height: d.bezel[3], alignment: .topLeading)
    }
}

/// The shelf's status on the bench's VFD (its EQ screen's look: blue-green phosphor behind the filter glass), one
/// line of `n` 5 x 7 characters. The line never scrolls: the text is fitted to it by the caller. Powered with the app:
/// at its first appearance the filament warms (0.75 s), every dot lights a moment, then the line is painted in from the
/// left (the bench's VFD power-on); after that a new reading shows at once. Reduce Motion: no power-on.
struct VFDStatusLine: View {
    let text: String
    static var n: Int { GasKit.display("line")?.n ?? 26 }
    private static var poweredAt: Date?
    @State private var bootAt: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    static let core = Color(.sRGB, red: 225 / 255, green: 255 / 255, blue: 246 / 255)
    static let glow = Color(.sRGB, red: 62 / 255, green: 214 / 255, blue: 190 / 255)
    static let bootLength = 2.0

    var body: some View {
        if let d = GasKit.display("line"), let m = d.mtx, m.count == 4 {
            DisplayPicture(d: d) {
                TimelineView(.animation(paused: bootAt == nil)) { ctx in
                    let phase = boot(at: ctx.date)
                    VFDDots(text: text, n: d.n, mtx: m, cells: d.cellsRect, all: phase.all, reveal: phase.reveal)
                        .opacity(phase.level)
                }
            }
            .onAppear {
                guard VFDStatusLine.poweredAt == nil, !reduceMotion else { return }
                let now = Date(); VFDStatusLine.poweredAt = now; bootAt = now
                DispatchQueue.main.asyncAfter(deadline: .now() + VFDStatusLine.bootLength + 0.1) { bootAt = nil }
            }
            .accessibilityElement()
            .accessibilityLabel(text)
        } else {
            GlassWindow(size: 13) { Text(text).textCase(.uppercase).tracking(1.4).frame(minWidth: 172, alignment: .leading) }
        }
    }
    /// The power-on: the filament's fade (0 … 0.75 s, nothing lit yet but the warm-up of the whole face), every dot
    /// lit (0.75 … 1.15 s), dark a moment, the reading painted in from the left (1.25 … 2 s).
    func boot(at date: Date) -> (level: Double, all: Bool, reveal: Double) {
        guard let t0 = bootAt else { return (1, false, 1) }
        let t = date.timeIntervalSince(t0)
        if t < 0.75 { return (0, false, 1) }
        if t < 1.15 { return (SwellMotion.smooth(0.75, 0.95, t), true, 1) }
        if t < 1.25 { return (0, false, 1) }
        return (1, false, min(1, (t - 1.25) / 0.75))
    }
}

private struct VFDDots: View {
    let text: String
    let n: Int
    let mtx: [CGFloat]
    let cells: CGRect
    let all: Bool
    let reveal: Double
    var body: some View {
        let cols = n * 6 - 1
        let px = cells.width / mtx[2], py = cells.height / mtx[3]
        let r = 0.3 * min(px, py)
        let lit = all ? VFDDots.allDots(cols) : VFDDots.dots(text, n: n)
        let shownCols = all ? cols : Int((Double(cols) * reveal).rounded(.up))
        let dots = lit.filter { $0.0 < shownCols }
        let pts = dots.map { (i, j) -> (CGPoint, Double) in
            (CGPoint(x: cells.minX + (mtx[0] + CGFloat(i) + 0.5) * px, y: cells.minY + (mtx[1] + CGFloat(j) + 0.5) * py),
             0.86 + 0.14 * GasKit.hash(i, j))
        }
        ZStack {
            Canvas { g, _ in
                for (p, k) in pts { g.fill(Path(ellipseIn: CGRect(x: p.x - r * 1.6, y: p.y - r * 1.6, width: r * 3.2, height: r * 3.2)),
                                          with: .color(VFDStatusLine.glow.opacity(0.5 * k))) }
            }
            .blur(radius: r * 0.9)
            Canvas { g, _ in
                for (p, k) in pts {
                    g.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)), with: .color(VFDStatusLine.glow.opacity(k)))
                    let h = r * 0.45
                    g.fill(Path(ellipseIn: CGRect(x: p.x - h, y: p.y - h, width: 2 * h, height: 2 * h)), with: .color(VFDStatusLine.core.opacity(0.45 * k)))
                }
            }
        }
        .blendMode(.screen)
        .allowsHitTesting(false)
    }
    /// The lit dots of a line: (column, row), 6 columns a character.
    static func dots(_ s: String, n: Int) -> [(Int, Int)] {
        var out: [(Int, Int)] = []
        for (ci, ch) in s.uppercased().prefix(n).enumerated() {
            let g = GasFont.m57[ch] ?? GasFont.m57[" "] ?? []
            for (rr, row) in g.enumerated() { for (cc, b) in row.enumerated() where b == "1" { out.append((ci * 6 + cc, rr)) } }
        }
        return out
    }
    static func allDots(_ cols: Int) -> [(Int, Int)] {
        var out: [(Int, Int)] = []
        for i in 0..<cols where i % 6 < 5 { for j in 0..<7 { out.append((i, j)) } }
        return out
    }
}

/// A line for the VFD: `left` (the status), `right` (the rate) at the far end, `middle` (the interface) between them,
/// shortened to fit. Upper case, characters the font has.
func vfdLine(left: String, middle: String, right: String, n: Int) -> String {
    func clean(_ s: String) -> String {
        String(s.uppercased().map { GasFont.m57[$0] != nil ? $0 : ($0 == "–" || $0 == "—" ? "-" : " ") })
    }
    let l = clean(left), r = clean(right)
    // the interface's name: as many whole words as fit (a word cut short only when the first alone is too long)
    let room = n - l.count - r.count - 4
    var mid = ""
    for w in clean(middle).split(separator: " ") {
        let next = mid.isEmpty ? String(w) : mid + " " + w
        if next.count <= room { mid = next } else { break }
    }
    if mid.isEmpty, room >= 4 { mid = String(clean(middle).trimmingCharacters(in: .whitespaces).prefix(room)) }
    let body = mid.isEmpty ? l : l + "  " + mid
    let pad = max(1, n - body.count - r.count)
    return String((body + String(repeating: " ", count: pad) + r).prefix(n))
}

/// An input's peak on orange seven-segment gas digits (Panaplex style, slanted 8 degrees), the units printed beside
/// it on the panel. nil: the digits dark. A reading shows at once.
struct GasDigits: View {
    let value: Double?
    static let lit = Color(.sRGB, red: 1, green: 82 / 255, blue: 18 / 255)
    static let hot = Color(.sRGB, red: 1, green: 160 / 255, blue: 96 / 255)
    static var available: Bool { GasKit.display("dig") != nil }

    /// "-12.4" as the cells hold it: a sign or a blank, the digits, the point after the units digit.
    static func text(_ v: Double, n: Int) -> String {
        let c = max(-99.9, min(9.9, v))
        let s = String(format: "%.1f", c).replacingOccurrences(of: "-0.0", with: "0.0")
        return s
    }
    var body: some View {
        if let d = GasKit.display("dig") {
            DisplayPicture(d: d) {
                if let v = value { SegCanvas(text: GasDigits.text(v, n: d.n), d: d) }
            }
            .accessibilityElement()
            .accessibilityLabel(value.map { String(format: "%.1f dBFS", $0) } ?? "no reading")
        }
    }
}

private struct SegCanvas: View {
    let text: String
    let d: GasKit.Display
    struct Seg { let a: CGPoint; let b: CGPoint; let dot: Bool; let k: Double }
    var segs: [Seg] {
        let n = d.n, pitch = d.pitch ?? 1.3, t = tan((d.slant ?? 8) * .pi / 180)
        let c = d.cellsRect, cell = c.width / (CGFloat(n) * pitch + 0.5)
        // the characters, a point folded into the digit before it, right-aligned in the cells
        var chars: [(Character, Bool)] = []
        for ch in text {
            if ch == "." || ch == "," { if let l = chars.last, !l.1 { chars[chars.count - 1].1 = true; continue } }
            chars.append((GasFont.d7[ch] != nil ? ch : " ", false))
        }
        while chars.count < n { chars.insert((" ", false), at: 0) }
        chars = Array(chars.suffix(n))
        var out: [Seg] = []
        for (i, ch) in chars.enumerated() {
            let ox = c.minX + (0.25 + CGFloat(i) * pitch + (pitch - 1) / 2) * cell, oy = c.minY + 0.2 * cell
            func P(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: ox + (CGFloat(x) + (0.85 - CGFloat(y)) * t) * cell, y: oy + CGFloat(y) * cell) }
            for sg in GasFont.d7[ch.0] ?? "" {
                guard let s = GasFont.s7[sg], s.count == 4 else { continue }
                out.append(Seg(a: P(s[0], s[1]), b: P(s[2], s[3]), dot: false, k: 0.88 + 0.12 * GasKit.hash(i, Int(sg.asciiValue ?? 0))))
            }
            if ch.1, let p = GasFont.s7["p"], p.count >= 2 { let q = P(p[0], p[1]); out.append(Seg(a: q, b: q, dot: true, k: 0.95)) }
        }
        return out
    }
    var body: some View {
        let c = d.cellsRect, cell = c.width / (CGFloat(d.n) * (d.pitch ?? 1.3) + 0.5), w = 0.13 * cell
        let list = segs
        func draw(_ g: GraphicsContext, width: CGFloat, color: Color, alpha: Double) {
            for s in list {
                if s.dot {
                    let r = 0.07 * cell * width / w
                    g.fill(Path(ellipseIn: CGRect(x: s.a.x - r, y: s.a.y - r, width: 2 * r, height: 2 * r)), with: .color(color.opacity(alpha * s.k)))
                } else {
                    var p = Path(); p.move(to: s.a); p.addLine(to: s.b)
                    g.stroke(p, with: .color(color.opacity(alpha * s.k)), style: StrokeStyle(lineWidth: width, lineCap: .round))
                }
            }
        }
        return ZStack {
            Canvas { g, _ in draw(g, width: w * 1.9, color: GasDigits.lit, alpha: 0.5) }.blur(radius: cell * 0.06)
            Canvas { g, _ in draw(g, width: w * 0.92, color: GasDigits.lit, alpha: 1); draw(g, width: w * 0.38, color: GasDigits.hot, alpha: 0.4) }
        }
        .blendMode(.screen)
        .allowsHitTesting(false)
    }
}
#endif
