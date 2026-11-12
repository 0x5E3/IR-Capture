#if os(macOS)
import SwiftUI
import CoreText
import IRCaptureCore

// RackResults.swift: the results unit of the rack bay (7U; Phase 7a, the visual audit's "results are a document").
//
// The take sheet stands in a card frame: a printed form, rendered blank (design/render/ircapture_rack_layers.py
// `results`), filled in here for each take as a typist would fill it in: the entries in Courier Prime with the uneven
// strike of a typewriter, a coloured-pencil dab for each channel's colour (the scope's colours), a red-pencil ring round
// a figure to look at, and the verdict stamped in the CHECKED box. All of it is ink on the paper, drawn multiplied over
// the lit sheet so the paper's light, tooth and curl show through. Under the sheet the unit's own keys: FINDER,
// RE-EXPORT, RECORD AGAIN (the base shows them up; a press shows the rendered pressed key).

/// What a take sheet says, already in the words and figures to be typed.
struct TakeSheet {
    struct Row {
        var name: String
        /// The channel's colour (index into micColors); nil for the reference (no dab).
        var colour: Int?
        var values: [String: String]        // peak, noise, tail, h2, h3, arrival
        /// Figures to ring in red pencil.
        var ring: Set<String> = []
    }
    var capture: String
    var date: String
    var interface: String
    var rate: String
    var rows: [Row]
    var files: [String]
    var notes: [String]
    /// excellent, check or again: the stamp.
    var verdict: String
    var seed: UInt64

    var verdictWords: String {
        switch verdict { case "excellent": return "Excellent"; case "again": return "Record again"; default: return "Check the notes" }
    }
}

extension TakeSheet {
    init(_ r: ResultSummary) {
        capture = r.title
        let df = DateFormatter(); df.locale = Locale(identifier: "en_US_POSIX"); df.dateFormat = "dd MMM yy"
        date = df.string(from: r.date).uppercased()
        interface = r.interface ?? "-"
        rate = r.fs > 0 ? "\(rateTag(r.fs).dropLast()) kHz" : "-"
        func f(_ v: Double?, _ d: Int) -> String { v.map { String(format: "%.\(d)f", $0) } ?? "-" }
        rows = r.diagnostics.enumerated().map { (i, item) -> Row in
            let d = item.diag, isRef = item.label == "reference"
            let h2 = d.harmonics.count > 0 ? d.harmonics[0] : nil, h3 = d.harmonics.count > 1 ? d.harmonics[1] : nil
            var row = Row(name: isRef ? "Reference" : item.label, colour: isRef ? nil : (r.names.firstIndex(of: item.label) ?? i),
                          values: ["peak": f(d.recordingPeakDBFS, 1), "noise": f(d.noiseFloorDB, 0), "tail": f(d.tailAboveNoiseMs, 0),
                                   "h2": isRef ? "-" : f(h2, 0), "h3": isRef ? "-" : f(h3, 0), "arrival": isRef ? "-" : f(d.arrivalMs, 2)])
            if d.recordingPeakDBFS > -0.3 || d.recordingPeakDBFS < -30 { row.ring.insert("peak") }
            if !isRef, let v = h2, v > -30 { row.ring.insert("h2") }
            if !isRef, let v = h3, v > -30 { row.ring.insert("h3") }
            return row
        }
        files = r.topFiles
        if !files.isEmpty { files.append("48 kHz  24-bit  500 ms") }
        var n: [String] = []
        var warnings = r.warnings
        if r.droppedOut, let w = warnings.first {
            n.append(w + " Quit other apps (browsers, video calls, other audio software) first.")
            warnings.removeFirst()
        }
        n += warnings
        n.append("\(r.fileCount) IR files, README.txt, report.json." + (r.referenced ? " Reference used." : ""))
        if !r.referenced { n.append("No reference: the IRs include the power amp. Arrival times are relative to the first mic.") }
        n += r.polarityNotes.map { "Polarity: " + $0 }
        n += r.exportNotes
        let user = r.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !user.isEmpty { n.append("Notes: " + user) }
        notes = n
        verdict = r.droppedOut ? "again" : r.warnings.isEmpty ? "excellent" : "check"
        seed = TakeSheet.hash(r.title + r.folder.path)
    }

    /// FNV-1a: the same take always types and stamps the same way.
    static func hash(_ s: String) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 { h ^= UInt64(b); h = h &* 0x100000001b3 }
        return h
    }
}

/// A small seeded generator (SplitMix64) for the typewriter's unevenness and the pencil's strokes.
struct InkRandom {
    var s: UInt64
    mutating func next() -> UInt64 {
        s &+= 0x9E3779B97F4A7C15
        var z = s
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func uniform() -> Double { Double(next() >> 11) / Double(1 << 53) }
    mutating func normal() -> Double {
        let u = max(1e-12, uniform()), v = uniform()
        return (-2 * log(u)).squareRoot() * cos(2 * .pi * v)
    }
}

// ------------------------------------------------------------------ the unit
/// The results unit: the sheet filled in for this take, its stamp, the keys. Without the unit's pictures: nothing
/// (the caller keeps the old results).
struct RackResultsUnit: View {
    let sheet: TakeSheet
    var finder: () -> Void = {}
    var reexport: () -> Void = {}
    var recordAgain: () -> Void = {}
    var recordAgainEnabled = true

    static var available: Bool { RackKit.ready("results")?.1.results != nil }

    var body: some View {
        if let r = RackKit.ready("results"), let rs = r.1.results {
            let kit = r.0, u = r.1, p = u.panel
            ZStack(alignment: .topLeading) {
                RackUnitPicture(kit: kit, unit: u, own: { $0.hasPrefix("k") },
                                overlay: AnyView(ink(kit: kit, u: u, rs: rs)))
                // the sheet, for VoiceOver and as a tooltip with every note (a long note may not fit its lines)
                let sr = rs.sheet
                Color.clear.contentShape(Rectangle())
                    .frame(width: sr[2], height: sr[3]).offset(x: sr[0] - p[0], y: sr[1] - p[1])
                    .help(sheet.notes.joined(separator: "\n"))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Take sheet, \(sheet.capture)")
                    .accessibilityValue(spoken)
                ForEach(Array(rs.keys.enumerated()), id: \.offset) { i, k in
                    key(i, k, kit: kit, u: u)
                        .offset(x: k.rect[0] - p[0], y: k.rect[1] - p[1])
                }
            }
            .frame(width: kit.panelWidth, height: CGFloat(u.u) * kit.uPt, alignment: .topLeading)
        }
    }

    var spoken: String {
        var s = ["Verdict: \(sheet.verdictWords)"]
        for row in sheet.rows {
            let v = row.values
            s.append("\(row.name): peak \(v["peak"] ?? "-") dBFS, noise \(v["noise"] ?? "-") dB, tail \(v["tail"] ?? "-") ms, H2 \(v["h2"] ?? "-"), H3 \(v["h3"] ?? "-"), arrival \(v["arrival"] ?? "-") ms")
        }
        if !sheet.files.isEmpty { s.append("Load these: " + sheet.files.dropLast().joined(separator: ", ")) }
        return (s + sheet.notes).joined(separator: ". ")
    }

    @ViewBuilder func ink(kit: RackKit, u: RackKit.Unit, rs: RackKit.Results) -> some View {
        let sr = rs.sheet
        ZStack(alignment: .topLeading) {
            TakeSheetInk(sheet: sheet, form: rs.form, size: CGSize(width: sr[2], height: sr[3]))
                .frame(width: sr[2], height: sr[3])
                .offset(x: sr[0], y: sr[1])
            if let st = rs.stamps[sheet.verdict], let img = SwellPictures.shared.image(st.picture, pxPerPoint: rs.pxPerPoint) {
                let pl = stampPlace(rs)
                Image(nsImage: img).resizable().interpolation(.high)
                    .frame(width: st.size[0], height: st.size[1])
                    .rotationEffect(.degrees(pl.angle))
                    .offset(x: pl.center.x - st.size[0] / 2, y: pl.center.y - st.size[1] / 2)
                    .blendMode(.multiply)
            }
        }
        .frame(width: u.size[0], height: u.size[1], alignment: .topLeading)
        .allowsHitTesting(false)
    }

    /// Where the stamp lands in the CHECKED box (pt in the base picture) and how far it is turned: a little off each
    /// time, the same for the same take.
    func stampPlace(_ rs: RackKit.Results) -> (center: CGPoint, angle: Double) {
        let sr = rs.sheet, k = sr[2] / rs.form.w, c = rs.form.checked
        var g = InkRandom(s: sheet.seed ^ 0x5A17)
        let dx = (g.uniform() - 0.5) * 0.7 * k, dy = (g.uniform() - 0.5) * 0.5 * k
        let center = CGPoint(x: sr[0] + (c[0] + c[2]) / 2 * k + dx, y: sr[1] + ((c[1] + c[3]) / 2 + 0.15) * k + dy)
        return (center, -6.5 + 3 * g.uniform())
    }

    @ViewBuilder func key(_ i: Int, _ k: RackKit.Results.Key, kit: RackKit, u: RackKit.Unit) -> some View {
        let down = u.layers["k\(i)-down"]
        let img = down.flatMap { SwellPictures.shared.image($0.picture, pxPerPoint: kit.pxPerPoint) }
        let off = down.map { CGPoint(x: $0.rect[0] - k.rect[0], y: $0.rect[1] - k.rect[1]) } ?? .zero
        let size = down.map { CGSize(width: $0.rect[2], height: $0.rect[3]) } ?? .zero
        let style = RackKeyStyle(down: img, offset: off, size: size)
        let frame = CGSize(width: k.rect[2], height: k.rect[3])
        switch k.id {
        case "finder":
            Button(action: finder) { Color.clear.frame(width: frame.width, height: frame.height) }
                .buttonStyle(style).accessibilityLabel("Show in Finder").help("Show the capture folder in the Finder")
        case "reexport":
            Button(action: reexport) { Color.clear.frame(width: frame.width, height: frame.height) }
                .buttonStyle(style).accessibilityLabel("Re-export")
                .help("Make other formats from the raw take of this capture without a new recording")
        default:
            Button(action: recordAgain) { Color.clear.frame(width: frame.width, height: frame.height) }
                .buttonStyle(style).disabled(!recordAgainEnabled).accessibilityLabel("Record again")
                .help(recordAgainEnabled ? "Record this capture again with the same settings" : "Record again repeats a capture made with the app")
        }
    }
}

/// A key of a rendered unit: the base picture shows it up; while pressed, its rendered pressed state over it.
struct RackKeyStyle: ButtonStyle {
    let down: NSImage?
    let offset: CGPoint
    let size: CGSize
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .overlay(alignment: .topLeading) {
                if configuration.isPressed, let down {
                    Image(nsImage: down).resizable().interpolation(.high)
                        .frame(width: size.width, height: size.height)
                        .offset(x: offset.x, y: offset.y)
                        .allowsHitTesting(false)
                }
            }
    }
}

// ------------------------------------------------------------------ the ink
/// Everything put on the sheet for this take, in the sheet's points: typed, pencilled, ringed. Multiplied over the
/// rendered paper (ink takes the paper's light and tooth).
struct TakeSheetInk: View {
    let sheet: TakeSheet
    let form: RackKit.Results.Form
    let size: CGSize

    static let ink = (r: 34.0, g: 32.0, b: 44.0)            // a black-violet ribbon, as the proofs' typing
    static let redPencil = CGColor(srgbRed: 0.76, green: 0.17, blue: 0.14, alpha: 0.85)

    var body: some View {
        Canvas { ctx, _ in
            ctx.withCGContext { cg in draw(cg) }
        }
        .blendMode(.multiply)
        .accessibilityHidden(true)
    }

    private var k: CGFloat { size.width / form.w }               // points a centimetre on the sheet
    private var fontPt: CGFloat { form.typedCm * k }
    private var adv: CGFloat { form.advance * fontPt }
    private func chars(_ x0: CGFloat, _ x1: CGFloat) -> Int { max(1, Int(((x1 - x0) * k) / adv)) }

    func draw(_ cg: CGContext) {
        var rng = InkRandom(s: sheet.seed)
        let font = CTFontCreateWithName("CourierPrime-Regular" as CFString, fontPt, nil)
        cg.textMatrix = .identity
        // the heading
        let vals = ["capture": sheet.capture, "date": sheet.date, "interface": sheet.interface, "rate": sheet.rate]
        for f in form.fields {
            typed(cg, font, Self.fit(vals[f.key] ?? "", chars(f.x0 + 0.1, f.x1)), x: f.x0 + 0.1, baseline: f.baseline, rng: &rng)
        }
        // the table: figures right-aligned in their column (as a typist tabs them), the name after its colour's dab
        let T = form.table, cols = T.cols
        var rows = sheet.rows
        var more = 0
        if rows.count > T.rows { more = rows.count - (T.rows - 1); rows = Array(rows.prefix(T.rows - 1)) }
        var widths: [String: Int] = [:]
        for c in cols.dropFirst() { widths[c.key] = rows.map { ($0.values[c.key] ?? "-").count }.max() ?? 1 }
        for (r, row) in rows.enumerated() {
            let base = T.baseline0 + CGFloat(r) * T.rowH
            if let ci = row.colour { dab(cg, x: T.dabX, y: base - 0.2, colour: micColors[ci % micColors.count], rng: &rng) }
            let nx = row.colour == nil ? cols[0].x + 0.1 : T.nameX
            typed(cg, font, Self.fit(row.name, chars(nx, cols[1].x - 0.35)), x: nx, baseline: base, rng: &rng)
            for (j, c) in cols.enumerated() where j > 0 {
                let v = row.values[c.key] ?? "-"
                let w = widths[c.key] ?? v.count
                let x = c.x + 0.1 + CGFloat(w - v.count) * form.advance * form.typedCm
                typed(cg, font, v, x: x, baseline: base, rng: &rng)
                if row.ring.contains(c.key) { ring(cg, x: x, len: v.count, baseline: base, rng: &rng) }
            }
        }
        if more > 0 {
            typed(cg, font, "+ \(more) more channels: see report.json", x: cols[0].x + 0.1, baseline: T.baseline0 + CGFloat(T.rows - 1) * T.rowH, rng: &rng)
        }
        // the files to load, then the notes, each on its printed lines
        let F = form.files
        var files = sheet.files
        if files.count > F.baselines.count {
            let extra = files.count - F.baselines.count + 1
            files = Array(files.prefix(F.baselines.count - 1)) + ["+ \(extra) more in the folder"]
        }
        for (i, f) in files.enumerated() {
            typed(cg, font, Self.fitMiddle(f, chars(F.x0, F.x1)), x: F.x0, baseline: F.baselines[i], rng: &rng)
        }
        let N = form.notes
        let n = chars(N.x0, N.x1)
        var lines: [String] = []
        for note in sheet.notes { lines += Self.wrap(note, n) }
        if lines.count > N.baselines.count {
            lines = Array(lines.prefix(N.baselines.count - 1)) + ["(more in report.json)"]
        }
        for (i, l) in lines.enumerated() { typed(cg, font, l, x: N.x0, baseline: N.baselines[i], rng: &rng) }
    }

    /// Typed: one strike a character, each a little off the line and a little lighter or darker than the last.
    func typed(_ cg: CGContext, _ font: CTFont, _ text: String, x: CGFloat, baseline: CGFloat, rng: inout InkRandom) {
        var px = x * k
        for ch in text {
            defer { px += adv }
            let u = Array(String(ch).utf16)
            let dy = CGFloat(rng.normal()) * 0.012 * k
            let dens = max(-30, min(30, rng.normal() * 14))
            if ch == " " { continue }
            var g = [CGGlyph](repeating: 0, count: u.count)
            guard CTFontGetGlyphsForCharacters(font, u, &g, u.count) else { continue }
            let I = Self.ink
            cg.setFillColor(CGColor(srgbRed: (I.r + dens) / 255, green: (I.g + dens) / 255, blue: (I.b + dens) / 255,
                                    alpha: 0.86 + 0.14 * rng.uniform()))
            cg.saveGState()
            cg.translateBy(x: px, y: baseline * k + dy)
            cg.scaleBy(x: 1, y: -1)
            var pos = CGPoint.zero
            CTFontDrawGlyphs(font, &g, &pos, 1, cg)
            cg.restoreGState()
        }
    }

    /// A dab of coloured pencil: short strokes scribbled in a patch (the proof's dab).
    func dab(_ cg: CGContext, x: CGFloat, y: CGFloat, colour: Color, rng: inout InkRandom) {
        let c = NSColor(colour).usingColorSpace(.sRGB) ?? .orange
        cg.setLineCap(.round)
        cg.setLineWidth(max(0.4, 0.03 * k))
        for _ in 0..<60 {
            let a = CGFloat(rng.normal()) * 0.2, b = CGFloat(rng.normal()) * 0.16
            let s = 0.85 + 0.15 * rng.uniform()
            cg.setStrokeColor(CGColor(srgbRed: c.redComponent * s, green: c.greenComponent * s, blue: c.blueComponent * s, alpha: 0.9))
            cg.move(to: CGPoint(x: (x + a - 0.12) * k, y: (y + b + 0.1) * k))
            cg.addLine(to: CGPoint(x: (x + a + 0.12) * k, y: (y + b - 0.1) * k))
            cg.strokePath()
        }
    }

    /// A red-pencil ring round a typed figure: a loose loop, a little more than once round.
    func ring(_ cg: CGContext, x: CGFloat, len: Int, baseline: CGFloat, rng: inout InkRandom) {
        let w = CGFloat(len) * form.advance * form.typedCm
        let cx = (x + w / 2) * k, cy = (baseline - 0.22) * k
        let rx = (w / 2 + 0.35) * k, ry = 0.5 * k
        let a0 = 2.2 + rng.uniform() * 0.6, turns = 1.12 + 0.08 * rng.uniform()
        let wob = rng.uniform() * 6.28
        cg.setStrokeColor(Self.redPencil)
        cg.setLineWidth(max(0.6, 0.055 * k))
        cg.setLineCap(.round); cg.setLineJoin(.round)
        let n = 90
        for i in 0...n {
            let t = Double(i) / Double(n)
            let a = a0 + t * turns * 2 * .pi
            let rr = 1 + 0.06 * sin(3 * a + wob) + 0.05 * t      // a hand's loop: uneven, opening as it goes round
            let p = CGPoint(x: cx + rx * CGFloat(rr * cos(a)), y: cy - ry * CGFloat(rr * sin(a)))
            if i == 0 { cg.move(to: p) } else { cg.addLine(to: p) }
        }
        cg.strokePath()
    }

    static func fit(_ s: String, _ n: Int) -> String { s.count <= n ? s : String(s.prefix(max(1, n - 1))) + "…" }

    /// A file name cut in the middle, keeping its end (the mic and .wav).
    static func fitMiddle(_ s: String, _ n: Int) -> String {
        guard s.count > n, n > 4 else { return s }
        let tail = (n - 1) * 3 / 5, head = n - 1 - tail
        return String(s.prefix(head)) + "…" + String(s.suffix(tail))
    }

    /// A note wrapped at whole words, n characters a line; the lines after its first indented two spaces.
    static func wrap(_ s: String, _ n: Int) -> [String] {
        var out: [String] = [], line = ""
        for w in s.split(separator: " ", omittingEmptySubsequences: true).map(String.init) {
            let lead = out.isEmpty ? "" : "  "
            var word = w
            while (lead + word).count > n {          // a word longer than a line: cut it
                if !line.isEmpty { out.append(line); line = "" }
                let cut = n - (out.isEmpty ? 0 : 2)
                out.append((out.isEmpty ? "" : "  ") + String(word.prefix(cut))); word = String(word.dropFirst(cut))
            }
            if line.isEmpty { line = (out.isEmpty ? "" : "  ") + word }
            else if (line + " " + word).count <= n { line += " " + word }
            else { out.append(line); line = "  " + word }
        }
        if !line.isEmpty { out.append(line) }
        return out
    }
}
#endif
