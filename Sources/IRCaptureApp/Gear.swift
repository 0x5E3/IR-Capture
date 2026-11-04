#if os(macOS)
// The workshop look for IR Capture, built on SwellKit.swift (the desktop bench's rendered pieces).
// Spec: docs/design/HANDOFF-desktop-to-ircapture.md. The window is a pegboard wall with an oak shelf across the top;
// each step is a hammertone panel; printed instructions are paper cards; values sit in smoked-glass windows; status is
// a jewel lamp with its words beside it (colour is never the only signal).
import SwiftUI
import AppKit

// ------------------------------------------------------------------ what a view is drawn on
/// The surface under a view, so text, notes and lamps pick colours that read on it.
/// `.print` is the plain system look, kept for the exported wiring PNGs (white background, Quick start PDF).
enum SwellSurface { case print, stage, panel, paper }

private struct SwellSurfaceKey: EnvironmentKey { static let defaultValue = SwellSurface.print }
extension EnvironmentValues {
    var swellSurface: SwellSurface {
        get { self[SwellSurfaceKey.self] }
        set { self[SwellSurfaceKey.self] = newValue }
    }
}

extension SwellSurface {
    var primary: Color {
        switch self {
        case .print: return .primary
        case .stage: return Swell.crinkleLegend
        case .panel: return Swell.panelLabel
        case .paper: return Swell.tagInk
        }
    }
    var secondary: Color {
        switch self {
        case .print: return .secondary
        case .stage, .panel: return Swell.crinkleSub
        case .paper: return Swell.tagInk.opacity(0.74)
        }
    }
    var legend: Color {
        switch self {
        case .print: return .primary
        case .stage: return Swell.crinkleLegend
        case .panel: return Swell.panelLegend
        case .paper: return Swell.tagInk
        }
    }
    /// The app's status colours, tuned for this surface (measured contrast in the handoff, section A).
    func tone(_ c: Color) -> Color {
        if self == .print { return c }
        if c == .secondary { return secondary }
        if c == .primary { return primary }
        if c == badColor { return self == .paper ? Swell.tagError : Swell.warn }
        if c == warnColor { return self == .paper ? Color(swellHex: 0x6A4300) : Swell.amber }
        if c == goodColor { return self == .paper ? Color(swellHex: 0x1F4D2B) : Color(swellHex: 0x9ED3A8) }
        return c
    }
}

// ------------------------------------------------------------------ the two jobs' gear
/// Cab IR is 1950s workshop gear (bronze hammertone, jewel lamps, VU meters). Amp (NAM) is the same wall and shelf with
/// gear a little more modern (graphite anodised panels, LED lamps, LED-ladder meters). Set once, on the job's views.
enum SwellTheme { case cab, nam }

private struct SwellThemeKey: EnvironmentKey { static let defaultValue = SwellTheme.cab }
extension EnvironmentValues {
    var swellTheme: SwellTheme {
        get { self[SwellThemeKey.self] }
        set { self[SwellThemeKey.self] = newValue }
    }
}

/// The jewel that goes with a status colour.
func jewel(for c: Color) -> String {
    if c == goodColor { return "green" }
    if c == badColor { return "red" }
    if c == warnColor || c == lamp { return "amber" }
    return "clear"
}

// ------------------------------------------------------------------ surfaces
/// The paper a card is printed on. The bench mixes its stocks the same way: manila tags for notes, white drafting
/// bond for drawings, a ruled index card for a list to tick off.
enum PaperStock {
    case manila      // paper.webp over #D9C69A, the bench's tag
    case bond        // the bench's white drafting bond (paper.webp as rendered), a faint drafting grid on it
    case index       // a cream index card, blue rules and a red head rule
}

/// How a card sits on the panel: its stock, masking tape on its top corners (the bench's tape-1..3 renders), a tilt of
/// a fraction of a degree (cards are stuck on by hand), and an optional coffee ring (the bench's paper-ring).
struct PaperStyle {
    var stock: PaperStock = .manila
    var tape = false
    var tilt: Double = 0
    var ring = false
    static let tag = PaperStyle()
    static let card = PaperStyle(stock: .manila, tape: true, tilt: -0.3)
    static let drawing = PaperStyle(stock: .bond, tape: true, tilt: 0.2)
    static let index = PaperStyle(stock: .index, tape: false, tilt: 0.35)
}

/// Card stock: the paper picture over its tint, the bench's faint stains on manila, rules or a grid where the stock has them.
struct PaperBackground: View {
    var style = PaperStyle.tag
    var body: some View {
        ZStack(alignment: .topLeading) {
            switch style.stock {
            case .manila: Swell.tagPaper
            case .bond: Color(swellHex: 0xF4EFE4)
            case .index: Color(swellHex: 0xF2EAD6)
            }
            if let p = SwellPictures.shared.tileImage("paper", pxPerPoint: 512.0 / 220.0) {
                p.resizable(resizingMode: .tile).blendMode(.multiply).opacity(style.stock == .manila ? 0.85 : 0.7)
            }
            if style.stock == .manila, let w = SwellPictures.shared.tileImage("paper-wash", pxPerPoint: 512.0 / 300.0) {
                w.resizable(resizingMode: .tile).blendMode(.multiply).opacity(0.5)
            }
            if style.stock == .bond { DraftingGrid() }
            if style.stock == .index { IndexRules() }
            if style.ring, let r = SwellPictures.shared.image("paper-ring", pxPerPoint: 384.0 / 92.0) {
                Image(nsImage: r).resizable().frame(width: 92, height: 92).blendMode(.multiply).opacity(0.55)
                    .rotationEffect(.degrees(24)).offset(x: -26, y: -30)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: style.stock == .index ? 3 : 1.5))
        .shadow(color: .black.opacity(0.55), radius: 3, x: 1, y: 2)
        .overlay(alignment: .topLeading) { if style.tape { TapePiece(n: 1, angle: -36).offset(x: -13, y: -6) } }
        .overlay(alignment: .topTrailing) { if style.tape { TapePiece(n: 2, angle: 39).offset(x: 13, y: -6) } }
        .accessibilityHidden(true)
    }
}

/// One piece of the bench's masking tape (tape-1..3.webp, 32 px a cm), drawn at 40 x 16 pt: a short tab across the
/// corner, small beside the card, as the bench lays it at half its picture on the sheet.
struct TapePiece: View {
    let n: Int
    let angle: Double
    var body: some View {
        if let t = SwellPictures.shared.image("tape-\(n)", pxPerPoint: 5.0) {
            Image(nsImage: t).resizable().interpolation(.high)
                .frame(width: t.size.width, height: t.size.height)
                .rotationEffect(.degrees(angle))
                .shadow(color: .black.opacity(0.25), radius: 0.8, x: 0.5, y: 0.8)
                .allowsHitTesting(false)
        }
    }
}

/// A drafting sheet's faint printed grid (5 mm and 25 mm at 10 pt a cm), non-photo blue, as on engineering paper.
struct DraftingGrid: View {
    var body: some View {
        Canvas { ctx, size in
            let fine = GraphicsContext.Shading.color(Color(swellHex: 0x6F9DBA, opacity: 0.16))
            let bold = GraphicsContext.Shading.color(Color(swellHex: 0x6F9DBA, opacity: 0.30))
            var x: CGFloat = 0, k = 0
            while x <= size.width {
                var p = Path(); p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height))
                ctx.stroke(p, with: k % 5 == 0 ? bold : fine, lineWidth: 0.5); x += 5; k += 1
            }
            var y: CGFloat = 0; k = 0
            while y <= size.height {
                var p = Path(); p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(p, with: k % 5 == 0 ? bold : fine, lineWidth: 0.5); y += 5; k += 1
            }
        }
        .accessibilityHidden(true)
    }
}

/// An index card's printed rules: a red head rule, then blue rules every 20 pt.
struct IndexRules: View {
    var body: some View {
        Canvas { ctx, size in
            var y: CGFloat = 37
            var red = Path(); red.move(to: CGPoint(x: 0, y: y)); red.addLine(to: CGPoint(x: size.width, y: y))
            ctx.stroke(red, with: .color(Color(swellHex: 0xC4524A, opacity: 0.55)), lineWidth: 0.9)
            y += 20
            while y < size.height {
                var p = Path(); p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(p, with: .color(Color(swellHex: 0x6F9DBA, opacity: 0.32)), lineWidth: 0.6); y += 20
            }
        }
        .accessibilityHidden(true)
    }
}

/// The panel stock under a step: bronze hammertone (a finer grain when that render is in the kit) for Cab IR,
/// graphite anodised aluminium for Amp (NAM). Falls back to the kit's own panel if a picture is missing.
struct PanelStock: View {
    /// Panels made at different times never match exactly: each seed shifts the stock's tone a hair (under 3 %).
    var seed = 0
    @Environment(\.swellTheme) private var theme
    var body: some View {
        let b = Double((seed * 37) % 7 - 3) * 0.007, sat = 1 + Double((seed * 53) % 5 - 2) * 0.025
        Panel9Slice(piece: SwellNine.stepPanel(for: theme, alternate: seed > 0 && seed % 2 == 0)).brightness(b).saturation(sat)
    }
}

extension View {
    /// Printed matter: instructions, checklists, notes, warnings.
    func onPaper(padding: CGFloat = 12, fill: Bool = true, style: PaperStyle = .tag) -> some View {
        self.environment(\.swellSurface, .paper)
            .foregroundStyle(Swell.tagInk)
            .tint(Swell.tagError)
            .padding(padding)
            .padding(.top, style.stock == .index ? 8 : 0)
            .frame(maxWidth: fill ? .infinity : nil, alignment: .leading)
            .background(PaperBackground(style: style))
            .rotationEffect(.degrees(style.tilt))
            .zIndex(style.tape ? 1 : 0)
    }

    /// A step's panel with screws in the corners (a step, the results), in the job's stock.
    func onPanel(padding: CGFloat = 20, seed: Int = 0) -> some View {
        self.environment(\.swellSurface, .panel)
            .foregroundStyle(Swell.panelLabel)
            .padding(.horizontal, padding + 2).padding(.vertical, padding)
            .background(PanelStock(seed: seed))
    }

    /// A black crinkle rack face (meters, the Welcome and Help sheets).
    func onCrinkle(padding: CGFloat = 14) -> some View {
        self.environment(\.swellSurface, .panel)
            .foregroundStyle(Swell.crinkleLegend)
            .padding(padding)
            .background(Panel9Slice(piece: SwellNine.crinkle))
    }

    /// The whole look's defaults: dark system controls, Barlow, amber accents, keys for every plain button.
    func workshopDefaults(_ surface: SwellSurface = .stage) -> some View {
        self.environment(\.swellSurface, surface)
            .font(.swellBody(13))
            .foregroundStyle(surface.primary)
            .tint(Swell.amber)
            .buttonStyle(KeyButtonStyle())
            .preferredColorScheme(.dark)
    }
}

// ------------------------------------------------------------------ lettering
/// An engraved legend: Barlow Semi Condensed capitals, tracked, light on metal (ink on paper).
struct Engraved: View {
    let text: String
    var size: CGFloat
    var dim: Bool
    @Environment(\.swellSurface) private var surface
    init(_ t: String, size: CGFloat = 11, dim: Bool = false) { text = t; self.size = size; self.dim = dim }
    var body: some View {
        Text(text)
            .font(.swellLegend(size))
            .textCase(.uppercase)
            .tracking(size * 0.16)
            .foregroundColor(dim ? surface.secondary : surface.legend)
            .shadow(color: surface == .paper || surface == .print ? .clear : .black.opacity(0.85), radius: 0, x: 0, y: 1)
    }
}

// ------------------------------------------------------------------ status
/// A jewel lamp with its words beside it, in the surface's colours.
struct StatusLine: View {
    let text: String
    let color: Color
    var diameter: CGFloat = 15
    @Environment(\.swellSurface) private var surface
    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            JewelLamp(colour: jewel(for: color), on: true, diameter: diameter)
            Text(text).foregroundColor(surface.tone(color)).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A value in a small glass window, its status as a jewel beside it (was a coloured pill).
struct StatusWindow: View {
    let text: String
    let color: Color
    var body: some View {
        HStack(spacing: 5) {
            JewelLamp(colour: jewel(for: color), on: true, diameter: 14)
            GlassWindow(size: 12) { Text(text) }
        }
        .accessibilityElement(children: .combine)
    }
}

// ------------------------------------------------------------------ glass controls
/// Keeps the target of a pop-up menu alive while macOS tracks it.
final class PopUpMenu: NSObject {
    private static var current: PopUpMenu?
    private var actions: [() -> Void] = []
    @objc private func fire(_ sender: NSMenuItem) { actions[sender.tag]() }

    /// Shows a native menu at the pointer; `checked` marks the current choice.
    static func show(_ items: [(title: String, checked: Bool, action: () -> Void)]) {
        let t = PopUpMenu()
        current = t
        let menu = NSMenu()
        menu.autoenablesItems = false
        for (i, it) in items.enumerated() {
            let mi = NSMenuItem(title: it.title, action: #selector(PopUpMenu.fire(_:)), keyEquivalent: "")
            mi.target = t
            mi.tag = i
            mi.state = it.checked ? .on : .off
            t.actions.append(it.action)
            menu.addItem(mi)
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}

/// The small downward chevron drawn on glass (no symbol fonts in the gear).
struct GlassChevron: View {
    var body: some View {
        Path { p in
            p.move(to: CGPoint(x: 0, y: 0)); p.addLine(to: CGPoint(x: 8, y: 0)); p.addLine(to: CGPoint(x: 4, y: 5)); p.closeSubpath()
        }
        .fill(Swell.amber.opacity(0.9))
        .frame(width: 8, height: 5)
        .accessibilityHidden(true)
    }
}

/// A choice shown in a glass window; a click opens the native menu (replaces a stock Picker, which can't be dressed).
struct GlassMenu<T: Hashable>: View {
    var title: String? = nil
    @Binding var selection: T
    let options: [(T, String)]
    var minWidth: CGFloat = 110
    @Environment(\.isEnabled) private var isEnabled
    var current: String { options.first(where: { $0.0 == selection })?.1 ?? "Choose…" }
    var body: some View {
        HStack(spacing: 8) {
            if let t = title { Engraved(t) }
            Button {
                let items: [(title: String, checked: Bool, action: () -> Void)] = options.map { o in
                    (title: o.1, checked: o.0 == selection, action: { selection = o.0 })
                }
                PopUpMenu.show(items)
            } label: {
                GlassWindow(size: 13) {
                    HStack(spacing: 10) {
                        Text(current).truncationMode(.middle)
                        Spacer(minLength: 0)
                        GlassChevron()
                    }
                }
                .frame(minWidth: minWidth)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title ?? "Choice")
            .accessibilityValue(current)
        }
        .opacity(isEnabled ? 1 : 0.5)
    }
}

/// A text field in a glass window, amber lettering.
struct GlassField: View {
    let placeholder: String
    @Binding var text: String
    var vertical = false
    var body: some View {
        GlassWindow(size: 13) {
            Group {
                if vertical {
                    TextField(placeholder, text: $text, axis: .vertical).lineLimit(1...3)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .textFieldStyle(.plain)
            .font(.swellLegend(13))
            .foregroundColor(Swell.amber)
        }
    }
}

/// A label engraved on the panel with its glass window beside it.
struct LabeledGlass<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content
    var body: some View {
        HStack(spacing: 10) {
            Engraved(label)
            content
        }
    }
}

/// Two or more keys of which one is lit: the chosen one (a role, a capture type, a page).
struct KeyChoice<T: Hashable>: View {
    @Binding var selection: T
    let options: [(T, String)]
    var size: CGFloat = 11
    var body: some View {
        HStack(spacing: 6) {
            ForEach(options.indices, id: \.self) { i in
                Button(options[i].1) { selection = options[i].0 }
                    .buttonStyle(KeyButtonStyle(key: options[i].1, lit: options[i].0 == selection, size: size))
            }
        }
    }
}

// ------------------------------------------------------------------ the VU meter
/// One analogue VU meter (the rack's level unit, rack-vu.webp, its face cropped). Honest mapping (handoff, B):
/// 0 VU is the target level, so the red arc above 0 means "turn down"; the face reads −20 to +3 VU and the needle
/// rests at the left end below that. It is driven by IR Capture's peak reading, not VU ballistics, so the needle is
/// smoothed (about 300 ms) and the dBFS figure stays in a glass window beside it.
struct VUMeter: View {
    /// Peak minus target, in dB. nil (no signal) rests the needle at −20.
    let vu: Double?
    var width: CGFloat = 150
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // rack-vu.webp, the left meter: its bezel box, the face inside it, the needle pivot (all in the picture's px)
    static let box = CGRect(x: 258, y: 60, width: 306, height: 186)
    static let face = CGRect(x: 266.02, y: 69.84, width: 553.31 - 266.02, height: 237.42 - 69.84)
    static let pivot = CGPoint(x: 409.67, y: 276.32)
    static let length = 172.5
    // layout.json's angle table: degrees from vertical, VU −20 … +3
    static let table: [(Double, Double)] = [(-20, -47.0), (-10, -31.514), (-7, -22.172), (-5, -13.889), (-3, -3.461), (-2, 2.726),
                                            (-1, 9.667), (0, 17.455), (1, 26.194), (2, 35.999), (3, 47.0)]
    static func angle(_ vu: Double?) -> Double {
        guard let v = vu else { return table[0].1 }
        let x = max(-20, min(3, v))
        for k in 1..<table.count where x <= table[k].0 {
            let (a, b) = (table[k - 1], table[k])
            return a.1 + (x - a.0) / (b.0 - a.0) * (b.1 - a.1)
        }
        return table.last!.1
    }
    var scale: CGFloat { width / VUMeter.box.width }
    var body: some View {
        let h = VUMeter.box.height * scale
        ZStack(alignment: .topLeading) {
            if let img = SwellPictures.shared.sprite("rack-vu.webp", rect: VUMeter.box, pxPerPoint: 1 / scale) {
                Image(nsImage: img).resizable().interpolation(.high).frame(width: width, height: h)
            } else {
                Color(swellHex: 0xC9A66B).frame(width: width, height: h)
            }
            NeedleShape(angle: VUMeter.angle(vu), scale: scale)
                .stroke(Color(swellHex: 0x16110B, opacity: 0.92), style: StrokeStyle(lineWidth: max(1.1, 1.6 * scale * 2), lineCap: .round))
                .shadow(color: .black.opacity(0.35), radius: 0.6, x: 0.8, y: 0.8)
                .frame(width: width, height: h)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: vu)
        }
        .frame(width: width, height: h)
        .accessibilityElement()
        .accessibilityLabel("Level meter")
        .accessibilityValue(vu.map { String(format: "%+.0f dB from the target", $0) } ?? "no signal")
    }

    /// The needle from where it enters the face (the pivot is below it, behind the panel) to its tip.
    struct NeedleShape: Shape {
        var angle: Double
        let scale: CGFloat
        var animatableData: Double { get { angle } set { angle = newValue } }
        func path(in rect: CGRect) -> Path {
            let b = VUMeter.box, f = VUMeter.face
            let px = Double(VUMeter.pivot.x - b.minX), py = Double(VUMeter.pivot.y - b.minY)
            let faceBottom = Double(f.maxY - b.minY), k = Double(scale)
            let th = angle * Double.pi / 180, s = sin(th), c = cos(th)
            let t0 = (py - faceBottom) / max(c, 0.2)
            let start = CGPoint(x: (px + t0 * s) * k, y: (py - t0 * c) * k)
            let tip = CGPoint(x: (px + VUMeter.length * s) * k, y: (py - VUMeter.length * c) * k)
            var p = Path()
            p.move(to: start); p.addLine(to: tip)
            return p
        }
    }
}

/// One input's meter module: the VU face, its name engraved, the dBFS figure on glass, the CLIP jewel, the magic eye
/// for how far the input stands above the room noise, the advice. `compact` (five or more inputs) narrows the face so
/// five or six fit across the bridge at the default window size.
struct MeterModule<Extra: View>: View {
    let label: String
    let vu: Double?
    let dbfs: String
    let clipped: Bool
    let advice: (String, Color)
    /// The magic eye: nil hides it; otherwise its closure (0 open … 1 closed) and whether its tube is lit.
    var eye: (closure: Double?, lit: Bool)? = nil
    var compact = false
    @ViewBuilder var extra: Extra
    /// (11-03, round 3b: Lowell wanted the meters bigger) Four full-size modules fill the 828 pt stage: 174 pt faces.
    var width: CGFloat { compact ? 100 : 174 }
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            HStack(spacing: 4) {
                Engraved(label, size: compact ? 11 : 12).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 2)
                HStack(spacing: 4) {
                    JewelLamp(colour: "red", on: clipped, diameter: compact ? 12 : 14)
                    if !compact { Engraved("Clip", size: 9, dim: !clipped) }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(clipped ? "Clipping" : "Not clipping")
            }
            VUMeter(vu: vu, width: width)
            HStack(alignment: .center, spacing: 6) {
                GlassWindow(size: compact ? 10 : 12) { Text(dbfs).monospacedDigit() }
                Spacer(minLength: 0)
                if let e = eye {
                    VStack(spacing: 1) {
                        MagicEye(closure: e.closure, lit: e.lit, diameter: compact ? 24 : 30)
                        Engraved("Noise", size: 7, dim: true)
                    }
                    .help("The green closes as the input stands clear of the room noise: open at 20 dB, closed at 60 dB or more.")
                }
            }
            StatusLine(text: advice.0, color: advice.1, diameter: compact ? 12 : 13).font(.swellBody(compact ? 11 : 12, semibold: true))
            if compact { VStack(alignment: .leading, spacing: 5) { extra } } else { extra }
        }
        .frame(width: width)
        .onCrinkle(padding: compact ? 10 : 12)
    }
}

/// Meter modules side by side, four to a row at full size (the layout is made for four inputs or fewer: Lowell,
/// 11-03); more inputs stack in rows below and the page scrolls. The compact face is kept for the gear preview only.
struct MeterBridge<Content: View>: View {
    var count = 0
    @ViewBuilder let content: Content
    static func compact(_ n: Int) -> Bool { false }
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 198), spacing: 12, alignment: .topLeading), count: 4),
                  alignment: .leading, spacing: 12) {
            content
        }
    }
}

// ------------------------------------------------------------------ the magic eye
/// A tuning eye from the rack's Monitor unit (rack-monitor.webp's unlit eye, rack-monitor-ineye.webp's 59 frames:
/// warm0..2 as the tube heats, then x00 wide open … x55 closed), cropped round its bezel. As a radio's eye closes
/// on a station, it closes here as the input stands clear of the room noise. Lit, it warms up for about a second.
struct MagicEye: View {
    /// 0 wide open … 1 closed; nil while lit with nothing measured yet (open).
    let closure: Double?
    let lit: Bool
    var diameter: CGFloat = 30
    @State private var warm = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The eye's centre in rack-monitor.webp (layout.json: ineye c = 424.78, 255.86); the crop is 200 px round it.
    static let base = CGRect(x: 325, y: 156, width: 200, height: 200)
    /// The same square in a frame of the sheet: frames are 216 x 210, 12 a row, their origin at the base box (312, 156).
    static func cell(_ i: Int) -> CGRect {
        CGRect(x: CGFloat(i % 12) * 216 + 13, y: CGFloat(i / 12) * 210, width: 200, height: 200)
    }
    var frameIndex: Int? {
        guard lit else { return nil }
        if warm >= 0 { return warm }                       // warm0, warm1, warm2
        let x = Int(((closure ?? 0) * 55).rounded())
        return 3 + max(0, min(55, x))
    }
    var body: some View {
        let k = diameter / 200
        ZStack {
            if let b = SwellPictures.shared.sprite("rack-monitor.webp", rect: MagicEye.base, pxPerPoint: 1 / k) {
                Image(nsImage: b).resizable().interpolation(.high)
            } else { Color.black }
            if let i = frameIndex, let f = SwellPictures.shared.sprite("rack-monitor-ineye.webp", rect: MagicEye.cell(i), pxPerPoint: 1 / k) {
                Image(nsImage: f).resizable().interpolation(.high)
            }
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .shadow(color: frameIndex.map { $0 >= 3 } == true ? Color(red: 0.4, green: 1, blue: 0.5, opacity: 0.25) : .clear, radius: 3)
        .task(id: lit) {
            guard lit, !reduceMotion else { warm = -1; return }
            for k in 0..<3 {
                warm = k
                try? await Task.sleep(nanoseconds: 370_000_000)
            }
            warm = -1
        }
        .accessibilityElement()
        .accessibilityLabel("Noise eye")
        .accessibilityValue(!lit ? "off" : closure.map { String(format: "%.0f percent closed", $0 * 100) } ?? "open")
    }
}

// ------------------------------------------------------------------ the LED ladder (Amp NAM)
/// The rack's LED peak meter (rack-led.webp: 16 segments, −42 to 0 dB; rack-led-ledin.webp: all of them lit), one
/// row cropped. It reads dBFS directly: TONE3000's target, −8 dBFS, is the last green segment, so no remapping. The
/// scale is engraved by the app under the row, the target figure in amber.
struct LEDLadder: View {
    /// Peak in dBFS; nil lights nothing.
    let dbfs: Double?
    var width: CGFloat = 420
    static let db: [Double] = [-42, -36, -30, -24, -20, -16, -12, -10, -8, -6, -5, -4, -3, -2, -1, 0]
    /// The row cropped from rack-led.webp (its px) and the same row's origin in the lit sheet (which starts at 330, 84).
    static let row = CGRect(x: 343, y: 99, width: 792, height: 44)
    static let sheetOrigin = CGPoint(x: 330, y: 84)
    static let segX: [CGFloat] = [355.69, 404.32, 452.96, 501.59, 550.22, 598.86, 647.49, 696.13, 744.76, 793.39, 842.03, 890.66, 939.29, 987.93, 1036.56, 1085.2]
    static let segW: CGFloat = 37.22
    var k: CGFloat { width / LEDLadder.row.width }
    func lit(_ i: Int) -> Bool { guard let d = dbfs else { return false }; return d >= LEDLadder.db[i] - 0.5 }
    var body: some View {
        let r = LEDLadder.row, h = r.height * k
        VStack(spacing: 2) {
            ZStack(alignment: .topLeading) {
                if let b = SwellPictures.shared.sprite("rack-led.webp", rect: r, pxPerPoint: 1 / k) {
                    Image(nsImage: b).resizable().interpolation(.high).frame(width: width, height: h)
                } else { Color.black.frame(width: width, height: h) }
                ForEach(0..<16, id: \.self) { i in
                    if lit(i) {
                        let x0 = LEDLadder.segX[i] - 6, y0 = r.minY
                        let cell = CGRect(x: x0 - LEDLadder.sheetOrigin.x, y: y0 - LEDLadder.sheetOrigin.y, width: LEDLadder.segW + 12, height: r.height)
                        if let s = SwellPictures.shared.sprite("rack-led-ledin.webp", rect: cell, pxPerPoint: 1 / k) {
                            Image(nsImage: s).resizable().interpolation(.high)
                                .frame(width: cell.width * k, height: h)
                                .offset(x: (x0 - r.minX) * k)
                        }
                    }
                }
            }
            .frame(width: width, height: h, alignment: .topLeading)
            ZStack(alignment: .topLeading) {
                ForEach(0..<16, id: \.self) { i in
                    let cx = (LEDLadder.segX[i] + LEDLadder.segW / 2 - r.minX) * k
                    let target = LEDLadder.db[i] == -8
                    Text(LEDLadder.db[i] == 0 ? "0" : "\(Int(LEDLadder.db[i]))".replacingOccurrences(of: "-", with: "−"))
                        .font(.swellLegend(8.5, bold: target))
                        .foregroundColor(target ? Swell.amber : Swell.crinkleSub)
                        .fixedSize()
                        .frame(width: 30)
                        .offset(x: cx - 15)
                }
            }
            .frame(width: width, height: 11, alignment: .topLeading)
        }
        .accessibilityElement()
        .accessibilityLabel("Peak meter")
        .accessibilityValue(dbfs.map { String(format: "%.0f dBFS", $0) } ?? "no signal")
    }
}

/// One input on the Amp (NAM) job's LED meter unit: name, CLIP LED, the ladder, the dBFS figure, the advice.
struct LEDMeterRow: View {
    let label: String
    let dbfs: Double?
    let figure: String
    let clipped: Bool
    let advice: (String, Color)
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Engraved(label, size: 12).lineLimit(1).truncationMode(.tail)
                HStack(spacing: 5) {
                    LEDLamp(colour: "red", on: clipped, diameter: 11)
                    Engraved("Clip", size: 8, dim: !clipped)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(clipped ? "Clipping" : "Not clipping")
            }
            .frame(width: 92, alignment: .leading)
            LEDLadder(dbfs: dbfs, width: 340)
            VStack(alignment: .leading, spacing: 5) {
                GlassWindow(size: 12) { Text(figure).monospacedDigit() }
                StatusLine(text: advice.0, color: advice.1, diameter: 12).font(.swellBody(12, semibold: true))
            }
            .frame(minWidth: 150, alignment: .leading)
        }
    }
}

// ------------------------------------------------------------------ nixie readout
/// Seconds left on four nixie tubes (the rack Counter's window; the frames are only the glow, laid over its unlit tubes).
/// Leading zeros stay unlit.
struct NixieReadout: View {
    let value: Int
    var height: CGFloat = 52
    static let window = CGRect(x: 80, y: 80, width: 488, height: 177)
    static let tubes: [(x: CGFloat, w: CGFloat)] = [(42, 186), (162, 192), (276, 198), (396, 198)]
    var scale: CGFloat { height / NixieReadout.window.height }
    var body: some View {
        let shown = String(max(0, min(9999, value)))
        let digits = Array(String(repeating: "0", count: 4 - shown.count) + shown)
        let firstLit = digits.firstIndex(where: { $0 != "0" }) ?? 3
        ZStack(alignment: .topLeading) {
            if let bg = SwellPictures.shared.sprite("rack-counter.webp", rect: NixieReadout.window, pxPerPoint: 1 / scale) {
                Image(nsImage: bg).resizable().frame(width: NixieReadout.window.width * scale, height: height)
            } else { Color.black }
            ForEach(0..<4, id: \.self) { k in
                if k >= firstLit, let d = Int(String(digits[k])),
                   let glow = SwellPictures.shared.sprite("rack-counter-delay\(k).webp",
                                                          rect: CGRect(x: CGFloat(d) * NixieReadout.tubes[k].w, y: 0, width: NixieReadout.tubes[k].w, height: 300),
                                                          pxPerPoint: 1 / scale) {
                    Image(nsImage: glow).resizable()
                        .frame(width: NixieReadout.tubes[k].w * scale, height: 300 * scale)
                        .offset(x: (NixieReadout.tubes[k].x - NixieReadout.window.minX) * scale, y: (0 - NixieReadout.window.minY) * scale)
                }
            }
        }
        .frame(width: NixieReadout.window.width * scale, height: height, alignment: .topLeading)
        .clipped()
        .accessibilityElement()
        .accessibilityLabel("\(value) seconds left")
    }
}

// ------------------------------------------------------------------ the instrument screen
/// The satin faceplate round a dark screen, for the response plot.
struct FaceplateScreen<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content
            .padding(10)
            .background(RadialGradient(colors: [Color(swellHex: 0x17241F), Color(swellHex: 0x090F0C)], center: .center, startRadius: 10, endRadius: 520))
            .padding(26)
            .background(Panel9Slice(piece: SwellNine.faceplate))
    }
}

// ------------------------------------------------------------------ the workshop wall and its shelf
struct WorkshopWall: View {
    var body: some View {
        ZStack {
            Swell.wall
            if let peg = SwellPictures.shared.tileImage("frame-peg", pxPerPoint: 1.6) {
                peg.resizable(resizingMode: .tile)
            }
        }
        .accessibilityHidden(true)
    }
}

/// A strip from the frame (plank, trim) at its rendered height, cropped to length, never stretched.
struct FrameStrip: View {
    let name: String
    let height: CGFloat
    var vertical = false
    var pxPerPoint: CGFloat = 1.6
    var body: some View {
        if let img = SwellPictures.shared.tileImage(name, pxPerPoint: pxPerPoint) {
            img.resizable(resizingMode: .tile)
                .frame(width: vertical ? height : nil, height: vertical ? nil : height)
                .frame(maxWidth: vertical ? nil : .infinity, maxHeight: vertical ? .infinity : nil, alignment: .topLeading)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// A homemade steel box standing on the shelf, holding keys or a lamp: bronze hammertone, or oxblood crackle (the
/// bench's shelf mixes the two). With IR Capture's own shelf pieces the content sits on the box's rendered front face.
struct ShelfBox<Content: View>: View {
    var finish = "bronze"
    @ViewBuilder let content: Content
    var body: some View {
        if let g = ShelfGeometry.own {
            HStack(spacing: 10) { content }
                .padding(.horizontal, 12)
                .frame(height: g.boxHeight - g.boxFace[0] - g.boxFace[2])
                .padding(.top, g.boxFace[0]).padding(.leading, g.boxFace[1])
                .padding(.bottom, g.boxFace[2]).padding(.trailing, g.boxFace[3])
                .background(Panel9Slice(piece: g.boxPiece(finish)))
        } else {
            HStack(spacing: 10) { content }
                .padding(.leading, 22).padding(.trailing, 50).padding(.top, 9).padding(.bottom, 14)
                .frame(height: 68)
                .background(Panel9Slice(piece: SwellNine.shelfBox))
        }
    }
}

/// The opening in the wall the steps sit in: the stage cloth behind, a moulding round it.
struct StageOpening<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        let g = ShelfGeometry.own
        content
            .background(
                Group {
                    if let bd = SwellPictures.shared.image("frame-backdrop", pxPerPoint: 1.6) {
                        Image(nsImage: bd).resizable().scaledToFill()
                    } else { Swell.stage }
                }
                .clipped()
                .accessibilityHidden(true))
            .overlay { StageLight().allowsHitTesting(false) }
            .overlay(alignment: .leading) {
                if let g { FrameStrip(name: g.trimV, height: g.trimWidth, vertical: true, pxPerPoint: g.pxPerPoint).offset(x: -0.755 * g.trimWidth) }
                else { FrameStrip(name: "frame-trim-left", height: 22, vertical: true).offset(x: -16) }
            }
            .overlay(alignment: .trailing) {
                if let g { FrameStrip(name: g.trimV, height: g.trimWidth, vertical: true, pxPerPoint: g.pxPerPoint).offset(x: 0.67 * g.trimWidth) }
                else { FrameStrip(name: "frame-trim-right", height: 22, vertical: true).offset(x: 16) }
            }
            .overlay(alignment: .bottom) {
                if let g { FrameStrip(name: g.trimH, height: g.trimWidth, pxPerPoint: g.pxPerPoint).offset(y: 0.67 * g.trimWidth) }
                else { FrameStrip(name: "frame-trim-bot", height: 22).offset(y: 14) }
            }
            .overlay(alignment: .top) {
                if let g { FrameStrip(name: g.trimH, height: g.trimWidth, pxPerPoint: g.pxPerPoint).offset(y: -0.755 * g.trimWidth) }
            }
    }
}

/// The one light falling on the stage: the shelf's shadow along the top of the opening, and a gentle falloff away
/// from the key light (up and to the left), so the panels at the edges sit a little darker, as in a real room.
struct StageLight: View {
    var body: some View {
        ZStack(alignment: .top) {
            RadialGradient(colors: [.clear, .clear, Color.black.opacity(0.32)], center: UnitPoint(x: 0.38, y: 0.12),
                           startRadius: 0, endRadius: 980)
            LinearGradient(colors: [Color.black.opacity(0.55), Color.black.opacity(0.18), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 34)
        }
        .accessibilityHidden(true)
    }
}
#endif
