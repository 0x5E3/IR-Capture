#if os(macOS)
import SwiftUI
import AppKit
import CoreText
import PDFKit
import IRCaptureCore

// RackPlotter.swift: the response plotter (6U, Phase 7a; the fourth proof, approved 11-12), in place of the scope.
//
// An X-Y recorder: response chart paper (20 Hz to 20 kHz, 60 dB, printed in the forms' oxblood) on its bed, chrome
// rails above and below, an aluminium arm across them and the pen carriage on it (design/render/ircapture_rack_layers.py
// `plotter`). The paper is the base picture, rendered blank. When a take's results arrive the app inks each mic's curve
// in its felt-pen colour, left to right, one mic after another (1.6 s each, the old beam's), moving the arm and the
// carriage as it goes (each rendered alone where it parks, moved here), then parks them; the capture's name and the pens'
// key are typed on the title line. Ink multiplied over the paper.
//
// PRINT (Lowell's idea, 11-12) opens a menu: the style (Plotter: the chart paper and pen colours, or Black and white:
// every curve black, told apart by line style), the curves (all mics on one chart, each mic on its own page, the
// automatic mixes, or mics and mixes), then Print… (the macOS print dialog, which also saves a PDF) or Save PDF to the
// capture folder. The pages are drawn here as vectors.

extension RackKit {
    struct Plotter: Decodable {
        struct Plot: Decodable { let w: CGFloat; let h: CGFloat; let L: CGFloat; let R: CGFloat; let T: CGFloat; let B: CGFloat }
        /// The title line on the paper (paper cm from its left; y the capitals' middle).
        struct Title: Decodable { let y: CGFloat; let capture: CGFloat; let pens: CGFloat; let end: CGFloat }
        let paper: [CGFloat]        // the paper in the base picture (pt)
        let grid: [CGFloat]         // the plot's frame: 20 Hz to 20 kHz across, 0 to -60 dB down (pt)
        let plot: Plot
        let title: Title
        let keys: [KeyRect]
        let park: CGFloat           // the arm's x where it parks (pt)
        let travel: [CGFloat]
        let penPark: CGFloat
        let penAt: [CGFloat]        // the pen's tip, parked (pt)
        let inks: [String]          // the felt pens, one for each of micColors
        let parts: [String: Layer]  // arm, armshadow, carriage, penshadow, pen-<i>: each alone where it parks
    }
}

/// The felt-pen inks as colours.
func penInk(_ hex: String) -> CGColor {
    let v = UInt32(hex.dropFirst(), radix: 16) ?? 0
    return CGColor(srgbRed: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 0.9)
}

struct RackPlotterUnit: View {
    @EnvironmentObject var m: AppModel
    let r: ResultSummary
    static var available: Bool { RackKit.ready("plotter")?.1.plotter != nil }
    @State private var start: Date?
    @State private var shownFor: URL?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let draw = 1.6, ret = 0.45, park = 0.8

    var curves: [[Double]] { r.names.map { r.curves.curves[$0] ?? [] } }
    var total: Double { Double(r.names.count) * (Self.draw + Self.ret) + Self.park }

    var body: some View {
        if let rk = RackKit.ready("plotter"), let P = rk.1.plotter {
            let kit = rk.0, u = rk.1
            TimelineView(.animation(paused: start == nil)) { tl in
                let t = start.map { tl.date.timeIntervalSince($0) } ?? total + 1
                let st = state(t, P)
                RackSetupFrame(kit: kit, unit: u, on: []) {
                    PlotterInk(P: P, fc: r.curves.fc, curves: curves, top: Self.top(curves, r.curves.fc), names: r.names,
                               capture: r.title, upTo: st.upTo, frac: st.frac)
                    parts(kit: kit, P: P, st: st)
                } controls: {
                    let g = P.paper
                    Color.clear.contentShape(Rectangle()).frame(width: g[2], height: g[3]).offset(x: g[0], y: g[1])
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Frequency response, 1/6 octave")
                        .accessibilityValue(r.names.joined(separator: ", "))
                    if let k = P.keys.first {
                        RackPressButton(kit: kit, unit: u, rect: k.rect, downLayer: "k0-down", label: "Print",
                                        help: "Print the response chart or save it as a PDF") { ResponsePrint.menu(r) }
                    }
                }
            }
            // the arm starts when the plotter first comes into view for this take (it may be below the window when the
            // results arrive); with Reduce Motion the curves are simply there
            .background(GeometryReader { g in
                Color.clear
                    .onAppear { seen(g.frame(in: .global)) }
                    .onChange(of: g.frame(in: .global).minY) { _ in seen(g.frame(in: .global)) }
            })
        }
    }

    func seen(_ f: CGRect) {
        guard shownFor != r.folder else { return }
        let h = NSApp.keyWindow?.contentLayoutRect.height ?? NSApp.windows.first?.contentLayoutRect.height ?? 900
        guard f.minY < h - 120 && f.maxY > 120 else { return }
        shownFor = r.folder
        begin()
    }

    func begin() {
        if reduceMotion { start = nil; return }
        let t = Date()
        start = t
        DispatchQueue.main.asyncAfter(deadline: .now() + total + 0.1) { if start == t { start = nil } }
    }

    /// The top line of the paper (0 on its scale): 5 dB over the loudest curve between 40 Hz and 12 kHz, rounded up
    /// to 10 (the old scope's).
    static func top(_ curves: [[Double]], _ fc: [Double]) -> Double {
        var mx = -Double.infinity
        for c in curves { for (i, v) in c.enumerated() where i < fc.count && fc[i] >= 40 && fc[i] <= 12000 { mx = max(mx, v) } }
        if !mx.isFinite { mx = 0 }
        return (mx / 10).rounded(.up) * 10 + 5
    }

    struct State { var upTo: Int; var frac: Double; var armX: CGFloat; var penY: CGFloat; var pen: Int }

    /// Where the arm and the pen are at t seconds, and how much is inked: each mic a return (pen up) to the left
    /// edge at its curve's first point, then 1.6 s drawing; at the end the arm parks.
    func state(_ t: Double, _ P: RackKit.Plotter) -> State {
        let n = r.names.count
        let parkX = P.park, parkY = P.penAt[1]
        // not come into view yet for this take: the paper blank, the arm parked
        if shownFor != r.folder && !reduceMotion { return State(upTo: 0, frac: 0, armX: parkX, penY: parkY, pen: 0) }
        guard n > 0, t < total, start != nil else { return State(upTo: n, frac: 0, armX: parkX, penY: parkY, pen: max(0, n - 1)) }
        func ease(_ x: Double) -> Double { let c = max(0, min(1, x)); return c * c * (3 - 2 * c) }
        var fromX = parkX, fromY = parkY
        for k in 0..<n {
            let t0 = Double(k) * (Self.draw + Self.ret)
            let startPt = penPoint(P, k, 0)
            if t < t0 + Self.ret {
                let e = CGFloat(ease((t - t0) / Self.ret))
                return State(upTo: k, frac: 0, armX: fromX + (startPt.x - fromX) * e, penY: fromY + (startPt.y - fromY) * e, pen: k)
            }
            if t < t0 + Self.ret + Self.draw {
                let u = 0.5 - 0.5 * cos(.pi * (t - t0 - Self.ret) / Self.draw)
                let p = penPoint(P, k, u)
                return State(upTo: k, frac: u, armX: p.x, penY: p.y, pen: k)
            }
            let e = penPoint(P, k, 1); fromX = e.x; fromY = e.y
        }
        let e = CGFloat(ease((t - Double(n) * (Self.draw + Self.ret)) / Self.park))
        return State(upTo: n, frac: 0, armX: fromX + (parkX - fromX) * e, penY: fromY + (parkY - fromY) * e, pen: n - 1)
    }

    /// The pen's tip on curve k at u (0 to 1 across the paper's frequency scale), picture points.
    func penPoint(_ P: RackKit.Plotter, _ k: Int, _ u: Double) -> CGPoint {
        let g = P.grid, c = curves[k], fc = r.curves.fc
        let top = Self.top(curves, fc)
        guard c.count == fc.count, !fc.isEmpty else { return CGPoint(x: g[0] + CGFloat(u) * g[2], y: g[1] + g[3]) }
        let lf = log10(20.0) + u * 3
        var v = c.last ?? 0
        if let j = fc.firstIndex(where: { log10($0) >= lf }) {
            if j == 0 { v = c[0] } else {
                let a = log10(fc[j - 1]), b = log10(fc[j]); let w = (lf - a) / max(1e-9, b - a)
                v = c[j - 1] + (c[j] - c[j - 1]) * w
            }
        }
        let db = max(-60, min(0, v - top))
        return CGPoint(x: g[0] + CGFloat(u) * g[2], y: g[1] + CGFloat(-db / 60) * g[3])
    }

    @ViewBuilder func parts(kit: RackKit, P: RackKit.Plotter, st: State) -> some View {
        let dx = st.armX - P.park, dy = st.penY - P.penAt[1]
        let pen = "pen-\(st.pen % max(1, P.inks.count))"
        // the shadows fall on the bed: kept inside its opening (the paper with the bed's margins)
        let cm = kit.ptPerCm, pp = P.paper
        let bed = CGRect(x: pp[0] - 0.6 * cm, y: pp[1] - 1.3 * cm, width: pp[2] + 4.6 * cm, height: pp[3] + 2.6 * cm)
        ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                part(kit, P.parts["armshadow"], dx, 0)
                part(kit, P.parts["penshadow"], dx, dy)
            }
            .frame(width: bed.maxX, height: bed.maxY, alignment: .topLeading)
            .mask(alignment: .topLeading) { Rectangle().frame(width: bed.width, height: bed.height).offset(x: bed.minX, y: bed.minY) }
            part(kit, P.parts["arm"], dx, 0)
            part(kit, P.parts["carriage"], dx, dy)
            part(kit, P.parts[pen], dx, dy)
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder func part(_ kit: RackKit, _ l: RackKit.Layer?, _ dx: CGFloat, _ dy: CGFloat) -> some View {
        if let l, let img = SwellPictures.shared.image(l.picture, pxPerPoint: kit.pxPerPoint) {
            Image(nsImage: img).resizable().interpolation(.high)
                .frame(width: l.rect[2], height: l.rect[3]).offset(x: l.rect[0] + dx, y: l.rect[1] + dy)
        }
    }
}

/// The plotter's ink on the paper (picture points): the curves drawn so far, the capture's name and the pens' key
/// typed on the title line. Multiplied over the paper.
struct PlotterInk: View {
    let P: RackKit.Plotter
    let fc: [Double]
    let curves: [[Double]]
    let top: Double
    let names: [String]
    let capture: String
    let upTo: Int
    let frac: Double
    var body: some View {
        Canvas { ctx, _ in ctx.withCGContext { cg in draw(cg) } }
            .frame(width: P.paper[0] + P.paper[2], height: P.paper[1] + P.paper[3])
            .blendMode(.multiply)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
    func draw(_ cg: CGContext) {
        let g = P.grid
        cg.saveGState()
        cg.clip(to: CGRect(x: g[0] - 1, y: g[1] - 1, width: g[2] + 2, height: g[3] + 2))
        for (k, c) in curves.enumerated() where k <= upTo && c.count == fc.count {
            let reach = k < upTo ? 1.0 : frac
            if reach <= 0 { continue }
            var pts: [CGPoint] = []
            for (i, f) in fc.enumerated() {
                let u = log10(f / 20) / 3
                if u > reach { break }
                let db = max(-60, min(0, c[i] - top))
                pts.append(CGPoint(x: g[0] + CGFloat(u) * g[2], y: g[1] + CGFloat(-db / 60) * g[3]))
            }
            let ink = penInk(P.inks[k % max(1, P.inks.count)])
            var rng = InkRandom(s: TakeSheet.hash(names[k] + capture))
            cg.setLineCap(.round); cg.setLineJoin(.round)
            for pass in 0..<2 {
                cg.setStrokeColor(ink.copy(alpha: pass == 0 ? 0.85 : 0.35) ?? ink)
                cg.setLineWidth(pass == 0 ? 1.0 : 1.5)
                for (i, p) in pts.enumerated() {
                    let q = CGPoint(x: p.x, y: p.y + CGFloat(rng.normal()) * 0.06)
                    if i == 0 { cg.move(to: q) } else { cg.addLine(to: q) }
                }
                cg.strokePath()
            }
        }
        cg.restoreGState()
        // the title line: typed by the plotter's own carriage as the results arrive (all at once)
        let pp = P.paper, k = pp[2] / P.plot.w
        let pt = 0.74 * k, adv = 0.6 * pt
        let font = CTFontCreateWithName("CourierPrime-Regular" as CFString, pt, nil)
        cg.textMatrix = .identity
        let base = pp[1] + (P.title.y + 0.21) * k
        var rng = InkRandom(s: TakeSheet.hash(capture + "|plot"))
        let capChars = max(1, Int((P.title.pens - P.title.capture - 0.6) * k / adv))
        PaperInk.type(cg, font, TakeSheetInk.fit(capture, capChars), x: pp[0] + P.title.capture * k, baseline: base, adv: adv, k: k, rng: &rng)
        var x = P.title.pens
        for (i, n) in names.enumerated() {
            let w = 1.15 + CGFloat(n.count) * 0.6 * 0.74 + 0.8
            if x + w > P.title.end {
                PaperInk.type(cg, font, "+\(names.count - i)", x: pp[0] + x * k, baseline: base, adv: adv, k: k, rng: &rng)
                break
            }
            let ink = penInk(P.inks[i % max(1, P.inks.count)])
            cg.setStrokeColor(ink); cg.setLineWidth(max(1, 0.07 * k)); cg.setLineCap(.round)
            cg.move(to: CGPoint(x: pp[0] + x * k, y: base - 0.26 * k)); cg.addLine(to: CGPoint(x: pp[0] + (x + 0.9) * k, y: base - 0.26 * k))
            cg.strokePath()
            PaperInk.type(cg, font, n, x: pp[0] + (x + 1.15) * k, baseline: base, adv: adv, k: k, rng: &rng)
            x += w
        }
    }
}

// ------------------------------------------------------------------ PRINT
enum ResponsePrint {
    enum Style: String { case plotter, bw }
    enum Curves: String { case all, each, mixes, both }
    static var style: Style {
        get { Style(rawValue: UserDefaults.standard.string(forKey: "print.style") ?? "") ?? .plotter }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "print.style") }
    }
    static var curves: Curves {
        get { Curves(rawValue: UserDefaults.standard.string(forKey: "print.curves") ?? "") ?? .all }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "print.curves") }
    }

    /// PRINT's menu: the style and the curves (each choice kept for next time), then print or save.
    static func menu(_ r: ResultSummary) {
        let mixes = !r.mixCurves.isEmpty
        var items: [PopUpMenu.Item] = [
            .header("Style"),
            .choice("Plotter (chart paper, pen colours)", checked: style == .plotter, enabled: true) { style = .plotter },
            .choice("Black and white", checked: style == .bw, enabled: true) { style = .bw },
            .separator, .header("Curves"),
            .choice("All mics on one chart", checked: curves == .all, enabled: true) { curves = .all },
            .choice("Each mic on its own page", checked: curves == .each, enabled: true) { curves = .each },
            .choice("Mixes", checked: curves == .mixes && mixes, enabled: mixes) { curves = .mixes },
            .choice("Mics and mixes", checked: curves == .both && mixes, enabled: mixes) { curves = .both },
            .separator,
        ]
        items.append(.choice("Print…", checked: false, enabled: true) { ResponsePrint.print(r) })
        items.append(.choice("Save PDF to the capture folder", checked: false, enabled: true) { ResponsePrint.save(r) })
        PopUpMenu.show(items)
    }

    /// The pages: (title, [(name, curve)]) each.
    static func pages(_ r: ResultSummary) -> [(String, [(String, [Double])])] {
        let mics = r.names.map { ($0, r.curves.curves[$0] ?? []) }
        let mixes = r.mixCurves.map { ($0.label, $0.curve) }
        let c: Curves = mixes.isEmpty && (curves == .mixes || curves == .both) ? .all : curves
        switch c {
        case .all: return [("Mics", mics)]
        case .each: return mics.map { ($0.0, [$0]) }
        case .mixes: return [("Mixes", mixes)]
        case .both: return [("Mics", mics), ("Mixes", mixes)]
        }
    }

    static func pdf(_ r: ResultSummary) -> Data {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 792, height: 612)                    // US Letter, landscape
        if NSPrintInfo.shared.paperSize.width > 0 {
            let s = NSPrintInfo.shared.paperSize
            box = CGRect(x: 0, y: 0, width: max(s.width, s.height), height: min(s.width, s.height))
        }
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let cg = CGContext(consumer: consumer, mediaBox: &box, [kCGPDFContextTitle as String: "\(r.title) response"] as CFDictionary)
        else { return Data() }
        let top = RackPlotterUnit.top(r.names.map { r.curves.curves[$0] ?? [] } + r.mixCurves.map(\.curve), r.curves.fc)
        let ps = pages(r)
        for (i, (sub, cs)) in ps.enumerated() {
            cg.beginPDFPage(nil)
            // drawn y down, as on screen
            cg.translateBy(x: 0, y: box.height); cg.scaleBy(x: 1, y: -1)
            page(cg, box.size, r: r, subtitle: sub, curves: cs, top: top, number: (i + 1, ps.count))
            cg.endPDFPage()
        }
        cg.closePDF()
        return data as Data
    }

    static func page(_ cg: CGContext, _ size: CGSize, r: ResultSummary, subtitle: String, curves: [(String, [Double])], top: Double,
                     number: (Int, Int)) {
        let bw = style == .bw
        let paper = bw ? CGColor(gray: 1, alpha: 1) : CGColor(srgbRed: 247 / 255, green: 238 / 255, blue: 214 / 255, alpha: 1)
        let ink = bw ? CGColor(gray: 0.1, alpha: 1) : CGColor(srgbRed: 120 / 255, green: 44 / 255, blue: 34 / 255, alpha: 1)
        let major = bw ? CGColor(gray: 0.62, alpha: 1) : CGColor(srgbRed: 196 / 255, green: 140 / 255, blue: 124 / 255, alpha: 1)
        let minor = bw ? CGColor(gray: 0.85, alpha: 1) : CGColor(srgbRed: 226 / 255, green: 196 / 255, blue: 182 / 255, alpha: 1)
        let inks = (RackKit.ready("plotter")?.1.plotter?.inks ?? ["#c4541e", "#264ca0", "#347838", "#963c78", "#1c7676", "#aa821e"]).map(penInk)
        cg.setFillColor(paper); cg.fill(CGRect(origin: .zero, size: size))
        let M: CGFloat = 40
        func text(_ s: String, _ x: CGFloat, _ y: CGFloat, size: CGFloat, bold: Bool = false, color: CGColor, align: CGFloat = 0) {
            let f = CTFontCreateWithName((bold ? "BarlowSemiCondensed-Bold" : "BarlowSemiCondensed-SemiBold") as CFString, size, nil)
            let a = NSAttributedString(string: s, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): f,
                                                               NSAttributedString.Key(kCTForegroundColorAttributeName as String): color])
            let line = CTLineCreateWithAttributedString(a)
            let w = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
            cg.saveGState(); cg.translateBy(x: x - w * align, y: y); cg.scaleBy(x: 1, y: -1)
            cg.textPosition = .zero; CTLineDraw(line, cg); cg.restoreGState()
            cg.textMatrix = .identity
        }
        // the heading
        text("RESPONSE  1/6 OCTAVE", M, M + 14, size: 15, bold: true, color: ink)
        text(r.title, M, M + 34, size: 13, color: CGColor(gray: 0.12, alpha: 1))
        let df = DateFormatter(); df.dateStyle = .medium
        text("\(subtitle)  ·  \(df.string(from: r.date))\(number.1 > 1 ? "  ·  page \(number.0) of \(number.1)" : "")",
             size.width - M, M + 14, size: 10, color: ink, align: 1)
        // the chart
        let keyRows = Int((Double(curves.count) / 3).rounded(.up))
        let L: CGFloat = M + 34, R = size.width - M - 8, T: CGFloat = M + 58
        let B = size.height - M - 34 - CGFloat(keyRows) * 16
        let X = { (f: Double) -> CGFloat in L + CGFloat(log10(f / 20) / 3) * (R - L) }
        let Y = { (db: Double) -> CGFloat in T + CGFloat(-max(-60, min(0, db)) / 60) * (B - T) }
        for dec in [20.0, 200, 2000] {
            for k in 1...9 {
                let f = dec * Double(k); if f > 20000 { break }
                cg.setStrokeColor(k == 1 || k == 5 ? major : minor); cg.setLineWidth(k == 1 || k == 5 ? 0.6 : 0.35)
                cg.move(to: CGPoint(x: X(f), y: T)); cg.addLine(to: CGPoint(x: X(f), y: B)); cg.strokePath()
            }
        }
        for db in stride(from: 0, through: -60, by: -2) {
            let maj = db % 10 == 0
            cg.setStrokeColor(maj ? major : minor); cg.setLineWidth(maj ? 0.6 : 0.35)
            cg.move(to: CGPoint(x: L, y: Y(Double(db)))); cg.addLine(to: CGPoint(x: R, y: Y(Double(db)))); cg.strokePath()
            if maj { text(db == 0 ? "0" : "\(db)", L - 6, Y(Double(db)) + 3.5, size: 9, color: ink, align: 1) }
        }
        cg.setStrokeColor(ink); cg.setLineWidth(0.9); cg.stroke(CGRect(x: L, y: T, width: R - L, height: B - T))
        for (f, t) in [(20.0, "20"), (50, "50"), (100, "100"), (200, "200"), (500, "500"), (1000, "1k"), (2000, "2k"), (5000, "5k"), (10000, "10k"), (20000, "20k")] {
            text(t, X(f), B + 14, size: 9, color: ink, align: 0.5)
        }
        text("Hz", (L + R) / 2, B + 27, size: 9, color: ink, align: 0.5)
        text("dB", L - 6, T - 8, size: 9, color: ink, align: 1)
        // the curves
        let dashes: [[CGFloat]] = [[], [7, 3.5], [1.2, 3], [8, 3, 1.5, 3]]
        let fc = r.curves.fc
        cg.saveGState(); cg.clip(to: CGRect(x: L, y: T - 1, width: R - L, height: B - T + 2))
        for (i, (_, c)) in curves.enumerated() where c.count == fc.count {
            cg.setStrokeColor(bw ? CGColor(gray: 0, alpha: 1) : inks[i % inks.count])
            cg.setLineWidth(bw ? (i / dashes.count % 2 == 0 ? 1.3 : 0.8) : 1.25)
            cg.setLineDash(phase: 0, lengths: bw ? dashes[i % dashes.count] : (i >= inks.count ? [6, 3] : []))
            cg.setLineCap(.round); cg.setLineJoin(.round)
            for (j, f) in fc.enumerated() {
                let p = CGPoint(x: X(f), y: Y(c[j] - top))
                if j == 0 { cg.move(to: p) } else { cg.addLine(to: p) }
            }
            cg.strokePath()
        }
        cg.restoreGState()
        cg.setLineDash(phase: 0, lengths: [])
        // the key, under the chart: three to a row
        let colW = (R - L) / 3
        for (i, (n, _)) in curves.enumerated() {
            let x = L + CGFloat(i % 3) * colW, y = B + 46 + CGFloat(i / 3) * 16
            cg.setStrokeColor(bw ? CGColor(gray: 0, alpha: 1) : inks[i % inks.count])
            cg.setLineWidth(bw ? (i / dashes.count % 2 == 0 ? 1.3 : 0.8) : 1.6)
            cg.setLineDash(phase: 0, lengths: bw ? dashes[i % dashes.count] : (i >= inks.count ? [6, 3] : []))
            cg.move(to: CGPoint(x: x, y: y - 3.5)); cg.addLine(to: CGPoint(x: x + 28, y: y - 3.5)); cg.strokePath()
            cg.setLineDash(phase: 0, lengths: [])
            text(n, x + 36, y, size: 10, color: CGColor(gray: 0.12, alpha: 1))
        }
        text("IR Capture", size.width - M, size.height - M + 6, size: 8, color: ink, align: 1)
    }

    static func print(_ r: ResultSummary) {
        guard let doc = PDFDocument(data: pdf(r)) else { NSSound.beep(); return }
        let info = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo.shared
        info.orientation = .landscape
        info.jobDisposition = .spool
        guard let op = doc.printOperation(for: info, scalingMode: .pageScaleToFit, autoRotate: true) else { NSSound.beep(); return }
        op.jobTitle = "\(r.title) response"
        op.showsPrintPanel = true
        _ = op.run()
    }

    static func save(_ r: ResultSummary) {
        let url = r.folder.appendingPathComponent("\(r.title)_response.pdf")
        do {
            try pdf(r).write(to: url)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            let a = NSAlert(); a.messageText = "The PDF could not be saved."; a.informativeText = error.localizedDescription; a.runModal()
        }
    }
}
#endif
