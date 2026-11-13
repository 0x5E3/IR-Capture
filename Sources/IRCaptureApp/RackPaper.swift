#if os(macOS)
import SwiftUI
import CoreText
import IRCaptureCore

// RackPaper.swift: the Cab IR rack's paper units (Phase 7a, step 4).
//
//   chart       6U, the hook-up drawing and the BEFORE YOU START card, each in its card frame. Nothing on it changes:
//               rendered whole (design/render/ircapture_rack_layers.py `chart`), drawn as it is.
//   preflight   4U, BEFORE CAPTURE: a printed form rendered blank (`preflight`), filled in here as the take sheet is:
//               each line typed (the item, its reading), ticked in pencil, ringed in red pencil when it needs a look,
//               crossed in the OK column when it stops the capture, a word pencilled beside a noisy room. A line not
//               measured yet is typed and left unmarked. Ink multiplied over the lit paper.
//               (11-13, the fifth proof) `preflight-trouble`, 5U, when its pictures are in the kit: the form with a
//               TROUBLE box at its foot. A fault (the level check's or the capture's error, which CabDeckStatus showed in
//               red under the deck) is typed there in the ribbon's red half; the shelf's lamp is red, its VFD FAULT.
// Also here: the typewriter and the pencil, shared with the take sheet (RackResults.swift).

// ------------------------------------------------------------------ ink on paper
enum PaperInk {
    static let ribbon = (r: 34.0, g: 32.0, b: 44.0)          // a black-violet ribbon, as the proofs' typing
    /// (11-13) the ribbon's red half: the pre-flight's TROUBLE box (the fifth proof's red)
    static let ribbonRed = (r: 168.0, g: 36.0, b: 30.0)
    static let redPencil = CGColor(srgbRed: 0.76, green: 0.17, blue: 0.14, alpha: 0.85)
    static let graphite = (r: 70.0 / 255, g: 68.0 / 255, b: 74.0 / 255)

    /// Typed: one strike a character, each a little off the line and a little lighter or darker than the last.
    /// x and baseline in points; `adv` the character advance, `k` points a centimetre (for the strike's wander).
    static func type(_ cg: CGContext, _ font: CTFont, _ text: String, x: CGFloat, baseline: CGFloat, adv: CGFloat, k: CGFloat,
                     rng: inout InkRandom, ink: (r: Double, g: Double, b: Double) = ribbon) {
        var px = x
        for ch in text {
            defer { px += adv }
            let u = Array(String(ch).utf16)
            let dy = CGFloat(rng.normal()) * 0.012 * k
            let dens = max(-30, min(30, rng.normal() * 14))
            if ch == " " { continue }
            var g = [CGGlyph](repeating: 0, count: u.count)
            guard CTFontGetGlyphsForCharacters(font, u, &g, u.count) else { continue }
            let I = ink
            cg.setFillColor(CGColor(srgbRed: (I.r + dens) / 255, green: (I.g + dens) / 255, blue: (I.b + dens) / 255,
                                    alpha: 0.86 + 0.14 * rng.uniform()))
            cg.saveGState()
            cg.translateBy(x: px, y: baseline + dy)
            cg.scaleBy(x: 1, y: -1)
            var pos = CGPoint.zero
            CTFontDrawGlyphs(font, &g, &pos, 1, cg)
            cg.restoreGState()
        }
    }

    /// A red-pencil ring: a loose loop round (cx, cy), a little more than once round, uneven (points). `squareness`
    /// above 0 flattens the loop toward a rounded box, as a hand rings a long phrase (0: an oval, for a short figure).
    static func ring(_ cg: CGContext, cx: CGFloat, cy: CGFloat, rx: CGFloat, ry: CGFloat, width: CGFloat, squareness: Double = 0,
                     rng: inout InkRandom) {
        let e = 1 - 0.45 * max(0, min(1, squareness))          // the cosine and sine raised to e: 1 an ellipse
        func sp(_ v: Double) -> Double { v < 0 ? -pow(-v, e) : pow(v, e) }
        let a0 = 2.2 + rng.uniform() * 0.6, turns = 1.12 + 0.08 * rng.uniform()
        let wob = rng.uniform() * 6.28
        cg.setStrokeColor(redPencil)
        cg.setLineWidth(width)
        cg.setLineCap(.round); cg.setLineJoin(.round)
        let n = 90
        for i in 0...n {
            let t = Double(i) / Double(n)
            let a = a0 + t * turns * 2 * .pi
            let rr = 1 + 0.06 * sin(3 * a + wob) + 0.05 * t      // a hand's loop: uneven, opening as it goes round
            let p = CGPoint(x: cx + rx * CGFloat(rr * sp(cos(a))), y: cy - ry * CGFloat(rr * sp(sin(a))))
            if i == 0 { cg.move(to: p) } else { cg.addLine(to: p) }
        }
        cg.strokePath()
    }

    /// A soft pencil stroke through the points: a few overlapping passes, each a little off and a little lighter.
    static func pencil(_ cg: CGContext, _ pts: [CGPoint], r: Double, g: Double, b: Double, alpha: Double = 0.85,
                       width: CGFloat, jitter: CGFloat, passes: Int = 3, rng: inout InkRandom) {
        cg.setLineCap(.round); cg.setLineJoin(.round)
        for _ in 0..<passes {
            let s = 0.9 + 0.16 * rng.uniform()
            cg.setStrokeColor(CGColor(srgbRed: min(1, r * s), green: min(1, g * s), blue: min(1, b * s), alpha: alpha))
            cg.setLineWidth(width * CGFloat(0.7 + 0.3 * rng.uniform()))
            for (i, p) in pts.enumerated() {
                let q = CGPoint(x: p.x + CGFloat(rng.normal()) * jitter, y: p.y + CGFloat(rng.normal()) * jitter)
                if i == 0 { cg.move(to: q) } else { cg.addLine(to: q) }
            }
            cg.strokePath()
        }
    }

    /// Pencilled words in Swell Marker (the drawing's hand), baseline at (x, y) points; returns the width.
    @discardableResult
    static func hand(_ cg: CGContext, _ text: String, x: CGFloat, baseline: CGFloat, size: CGFloat, colour: CGColor,
                     draw: Bool = true) -> CGFloat {
        let font = CTFontCreateWithName("SwellMarker-Regular" as CFString, size, nil)
        let attr = NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): colour])
        let line = CTLineCreateWithAttributedString(attr)
        let w = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        if draw {
            cg.saveGState()
            cg.translateBy(x: x, y: baseline)
            cg.scaleBy(x: 1, y: -1)
            cg.textPosition = .zero
            CTLineDraw(line, cg)
            cg.restoreGState()
            // CTLineDraw moves the text position on by the line's width, and the text matrix is not part of the saved
            // graphics state: put it back, or the next typed line (CTFontDrawGlyphs) starts that far to the right
            cg.textMatrix = .identity
        }
        return w
    }
}

// ------------------------------------------------------------------ the chart panel (6U)
/// The hook-up drawing and the BEFORE YOU START card. Without the unit's picture: nothing (the caller keeps the old
/// drawing and checklist).
struct RackChartUnit: View {
    /// (11-13) the DAW route's: DWG 2 and the card IN THE DAW (`chart-daw`)
    var daw = false
    static var available: Bool { RackKit.ready("chart") != nil }

    /// The card's words, for VoiceOver (as typed on the card in ircapture_rack.instruction_card).
    static let card = [
        "Mute the studio monitors.",
        "An output to the amp's FX return or power amp in. Not the guitar input.",
        "Amp master low to start.",
        "Mics to the inputs. Set each one to MIC.",
        "Optional: the speaker terminals through the 20 dB pad to a line input. Set it to REF.",
        "Wear ear protection. Warm a tube amp up for 20 minutes.",
        "Check levels. Turn each preamp until OK lights.",
    ]

    var body: some View {
        if let r = RackKit.ready(daw ? "chart-daw" : "chart") {
            RackUnitPicture(kit: r.0, unit: r.1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(daw ? "DAW hook-up drawing: the computer's DAW on the interface's USB, interface output to the amp's FX return, the amp's speaker output to the cab, mic 1 and mic 2 to inputs 1 and 2, optional 20 dB pad from the speaker terminals to input 8, monitors off"
                                        : "Hook-up drawing: interface output to the amp's FX return, the amp's speaker output to the cab, mic 1 and mic 2 to inputs 1 and 2, optional 20 dB pad from the speaker terminals to input 8, monitors off")
                .accessibilityValue((daw ? "In the DAW: " : "Before you start: ") + (daw ? Self.dawCard : Self.card).enumerated().map { "\($0 + 1). \($1)" }.joined(separator: " "))
        }
    }
}

// ------------------------------------------------------------------ the pre-flight (4U)
/// BEFORE CAPTURE, filled in from the model's pre-flight. `sentences`: the pre-flight in full (tooltip, VoiceOver).
struct RackPreflightUnit: View {
    let lines: [PreflightLine]
    var sentences: [String] = []
    /// (11-13) a fault, typed in red in the TROUBLE box (preflight-trouble only)
    var trouble: String? = nil

    /// The 5U form with the TROUBLE box when it is in the kit, else the 4U form.
    static var key: String { RackKit.ready("preflight-trouble")?.1.preflight?.form.trouble != nil ? "preflight-trouble" : "preflight" }
    static var available: Bool { RackKit.ready(key)?.1.preflight != nil }
    /// The TROUBLE box is in the kit: CabDeckStatus is not drawn, its lines are on the shelf's VFD and here.
    static var troubleAvailable: Bool { key == "preflight-trouble" }

    var body: some View {
        if let r = RackKit.ready(Self.key), let pf = r.1.preflight {
            let kit = r.0, u = r.1, p = u.panel, sr = pf.sheet
            ZStack(alignment: .topLeading) {
                RackUnitPicture(kit: kit, unit: u, overlay: AnyView(
                    ZStack(alignment: .topLeading) {
                        PreflightSheetInk(lines: lines, form: pf.form, size: CGSize(width: sr[2], height: sr[3]), trouble: trouble)
                            .frame(width: sr[2], height: sr[3])
                            .offset(x: sr[0], y: sr[1])
                    }
                    .frame(width: u.size[0], height: u.size[1], alignment: .topLeading)
                    .allowsHitTesting(false)))
                Color.clear.contentShape(Rectangle())
                    .frame(width: sr[2], height: sr[3]).offset(x: sr[0] - p[0], y: sr[1] - p[1])
                    .help((sentences + (trouble.map { ["Trouble: " + $0] } ?? [])).joined(separator: "\n"))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Before capture")
                    .accessibilityValue(spoken + (trouble.map { " Trouble: " + $0 } ?? ""))
            }
            .frame(width: kit.panelWidth, height: CGFloat(u.u) * kit.uPt, alignment: .topLeading)
        }
    }

    var spoken: String {
        if !sentences.isEmpty { return sentences.joined(separator: " ") }
        return lines.map { l in
            let m: String
            switch l.mark { case .tick: m = "OK"; case .ring: m = "check"; case .cross: m = "stops the capture"; case .none: m = "not measured" }
            return "\(l.item): \(l.reading), \(m)."
        }.joined(separator: " ")
    }
}

/// The pre-flight's ink, in the sheet's points: typed, ticked, ringed, crossed. Each line is seeded by its own words, so
/// it types the same way while it reads the same (a line that changes is retyped; the others stay put).
struct PreflightSheetInk: View {
    let lines: [PreflightLine]
    let form: RackKit.Preflight.Form
    let size: CGSize
    var trouble: String? = nil

    var body: some View {
        Canvas { ctx, _ in ctx.withCGContext { cg in draw(cg) } }
            .blendMode(.multiply)
            .accessibilityHidden(true)
    }

    private var k: CGFloat { size.width / form.w }               // points a centimetre on the sheet
    private var fontPt: CGFloat { form.typedCm * k }
    private var adv: CGFloat { form.advance * fontPt }
    private var advCm: CGFloat { form.advance * form.typedCm }
    private func chars(_ x0: CGFloat, _ x1: CGFloat) -> Int { max(1, Int((x1 - x0) / advCm)) }

    func draw(_ cg: CGContext) {
        let font = CTFontCreateWithName("CourierPrime-Regular" as CFString, fontPt, nil)
        cg.textMatrix = .identity
        let F = form, cols = F.cols
        guard cols.count >= 3 else { return }
        let ix = cols[0].x + 0.1, rx = cols[1].x + 0.1, okx = cols[2].x
        for (i, line) in lines.prefix(F.rows).enumerated() {
            var rng = InkRandom(s: TakeSheet.hash(line.item + "|" + line.reading))
            let base = F.baseline0 + CGFloat(i) * F.rowH
            let item = TakeSheetInk.fit(line.item, chars(ix, cols[1].x - 0.35))
            PaperInk.type(cg, font, item, x: ix * k, baseline: base * k, adv: adv, k: k, rng: &rng)
            let reading = TakeSheetInk.fit(line.reading, chars(rx, okx - 0.5))
            PaperInk.type(cg, font, reading, x: rx * k, baseline: base * k, adv: adv, k: k, rng: &rng)
            let mid = base - 0.22                                   // the capitals' middle
            switch line.mark {
            case .tick:
                tick(cg, x: okx + 0.55, mid: mid, rng: &rng)
            case .ring, .cross:
                let w = CGFloat(reading.count) * advCm
                PaperInk.ring(cg, cx: (rx + w / 2) * k, cy: mid * k, rx: (w / 2 + 0.32) * k, ry: 0.46 * k,
                              width: max(0.6, 0.055 * k), squareness: 1, rng: &rng)
                if line.mark == .cross { cross(cg, x: okx + 0.55, mid: mid, rng: &rng) }
                if let a = line.aside {
                    let size = 0.62 * k
                    let ax = (rx + w + 0.9) * k
                    let aw = PaperInk.hand(cg, a, x: 0, baseline: 0, size: size, colour: PaperInk.redPencil, draw: false)
                    if ax + aw < (okx - 0.4) * k {
                        PaperInk.hand(cg, a, x: ax, baseline: (base + 0.02) * k, size: size, colour: PaperInk.redPencil)
                    }
                }
            case .none:
                break
            }
        }
        // (11-13) the TROUBLE box: the fault in the ribbon's red half, wrapped on its lines (the rest cut with "…"; the
        // whole message is in the tooltip)
        if let t = trouble, !t.isEmpty, let T = F.trouble {
            var rng = InkRandom(s: TakeSheet.hash("trouble|" + t))
            let n = chars(T.x0, T.x1)
            for (i, l) in CaptureCardInk.wrap(t, n, T.baselines.count).enumerated() where i < T.baselines.count {
                PaperInk.type(cg, font, l, x: T.x0 * k, baseline: T.baselines[i] * k, adv: adv, k: k, rng: &rng, ink: PaperInk.ribbonRed)
            }
        }
    }

    /// The proof's pencil tick: a short stroke down, a long one up and right.
    func tick(_ cg: CGContext, x: CGFloat, mid: CGFloat, rng: inout InkRandom) {
        let j = (0..<4).map { _ in CGFloat(rng.normal()) * 0.06 }
        // the proof's tick at 0.8: these rows are 1.25 cm, the proof's 1.42
        let pts = [CGPoint(x: (x + j[0]) * k, y: (mid + j[1]) * k), CGPoint(x: (x + 0.28) * k, y: (mid + 0.32) * k),
                   CGPoint(x: (x + 0.92 + j[2]) * k, y: (mid - 0.44 + j[3]) * k)]
        let G = PaperInk.graphite
        PaperInk.pencil(cg, pts, r: G.r, g: G.g, b: G.b, width: max(0.6, 0.07 * k), jitter: 0.03 * k, rng: &rng)
    }

    /// A red-pencil cross in the OK column: this line stops the capture.
    func cross(_ cg: CGContext, x: CGFloat, mid: CGFloat, rng: inout InkRandom) {
        let s: CGFloat = 0.45
        for (a, b) in [((-s, -s), (s, s)), ((s, -s), (-s, s))] {
            let pts = [CGPoint(x: (x + 0.55 + a.0) * k, y: (mid + a.1) * k), CGPoint(x: (x + 0.55 + b.0) * k, y: (mid + b.1) * k)]
            PaperInk.pencil(cg, pts, r: 0.76, g: 0.17, b: 0.14, width: max(0.6, 0.07 * k), jitter: 0.025 * k, rng: &rng)
        }
    }
}
#endif
