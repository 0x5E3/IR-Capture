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

/// The jewel that goes with a status colour.
func jewel(for c: Color) -> String {
    if c == goodColor { return "green" }
    if c == badColor { return "red" }
    if c == warnColor || c == lamp { return "amber" }
    return "clear"
}

// ------------------------------------------------------------------ surfaces
/// Manila card stock (paper.webp tiled at 220 pt over #D9C69A).
struct PaperBackground: View {
    var body: some View {
        ZStack {
            Swell.tagPaper
            if let p = SwellPictures.shared.image("paper", pxPerPoint: 512.0 / 220.0) {
                Image(nsImage: p).resizable(resizingMode: .tile).blendMode(.multiply).opacity(0.85)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .shadow(color: .black.opacity(0.55), radius: 3, x: 0, y: 2)
        .accessibilityHidden(true)
    }
}

extension View {
    /// Printed matter: instructions, checklists, notes, warnings.
    func onPaper(padding: CGFloat = 12, fill: Bool = true) -> some View {
        self.environment(\.swellSurface, .paper)
            .foregroundStyle(Swell.tagInk)
            .tint(Swell.tagError)
            .padding(padding)
            .frame(maxWidth: fill ? .infinity : nil, alignment: .leading)
            .background(PaperBackground())
    }

    /// A hammertone panel with screws in the corners (a step, the results).
    func onPanel(padding: CGFloat = 20) -> some View {
        self.environment(\.swellSurface, .panel)
            .foregroundStyle(Swell.panelLabel)
            .padding(.horizontal, padding + 2).padding(.vertical, padding)
            .background(Panel9Slice(piece: SwellNine.panel))
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
                    .buttonStyle(KeyButtonStyle(lit: options[i].0 == selection, size: size))
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

/// One input's meter module: the VU face, its name engraved, the dBFS figure on glass, the CLIP jewel, the advice.
struct MeterModule<Extra: View>: View {
    let label: String
    let vu: Double?
    let dbfs: String
    let clipped: Bool
    let advice: (String, Color)
    @ViewBuilder var extra: Extra
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Engraved(label, size: 12).lineLimit(1)
                Spacer(minLength: 4)
                HStack(spacing: 4) {
                    JewelLamp(colour: "red", on: clipped, diameter: 14)
                    Engraved("Clip", size: 9, dim: !clipped)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(clipped ? "Clipping" : "Not clipping")
            }
            VUMeter(vu: vu)
            HStack(spacing: 6) {
                GlassWindow(size: 12) { Text(dbfs).monospacedDigit() }
                Spacer(minLength: 0)
            }
            StatusLine(text: advice.0, color: advice.1, diameter: 13).font(.swellBody(12, semibold: true))
            extra
        }
        .frame(width: 150)
        .onCrinkle(padding: 12)
    }
}

/// Meter modules side by side, wrapping onto more rows for more inputs.
struct MeterBridge<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 174, maximum: 190), spacing: 12, alignment: .top)], alignment: .leading, spacing: 12) {
            content
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
            if let peg = SwellPictures.shared.image("frame-peg", pxPerPoint: 1.6) {
                Image(nsImage: peg).resizable(resizingMode: .tile)
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
    var body: some View {
        if let img = SwellPictures.shared.image(name, pxPerPoint: 1.6) {
            Image(nsImage: img).resizable(resizingMode: .tile)
                .frame(width: vertical ? height : nil, height: vertical ? nil : height)
                .frame(maxWidth: vertical ? nil : .infinity, maxHeight: vertical ? .infinity : nil, alignment: .topLeading)
                .accessibilityHidden(true)
        }
    }
}

/// A homemade hammertone box standing on the shelf, holding keys or a lamp.
struct ShelfBox<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        HStack(spacing: 10) { content }
            .padding(.leading, 22).padding(.trailing, 50).padding(.top, 9).padding(.bottom, 14)
            .frame(height: 68)
            .background(Panel9Slice(piece: SwellNine.shelfBox))
    }
}

/// The opening in the wall the steps sit in: the stage cloth behind, a moulding round it.
struct StageOpening<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content
            .background(
                Group {
                    if let bd = SwellPictures.shared.image("frame-backdrop", pxPerPoint: 1.6) {
                        Image(nsImage: bd).resizable().scaledToFill()
                    } else { Swell.stage }
                }
                .clipped()
                .accessibilityHidden(true))
            .overlay(alignment: .leading) { FrameStrip(name: "frame-trim-left", height: 22, vertical: true).offset(x: -16) }
            .overlay(alignment: .trailing) { FrameStrip(name: "frame-trim-right", height: 22, vertical: true).offset(x: 16) }
            .overlay(alignment: .bottom) { FrameStrip(name: "frame-trim-bot", height: 22).offset(y: 14) }
    }
}
#endif
