#if os(macOS)
import SwiftUI
import AppKit
import CoreText
import IRCaptureCore

// RackSetup.swift: the Cab IR rack's set-up units (Phase 7a; the fourth proof, approved 11-12: "love your ideas, looks
// excellent overall"). Every control of the old Connect pickers, the capture name and files step and the two Advanced
// disclosures, as rack gear (design/render/ircapture_rack_layers.py `connect`, `files`, `sweep`, `formats`):
//
//   connect   2U  INTERFACE on a VFD with a SELECT knob (a click lists the interfaces, the scroll wheel steps them),
//                 OUT TO AMP on a thumbwheel, REFERENCE on a three-way rotary, AUDIO SETUP, IMPORT DAW
//   files     4U  the capture card, typed by the app (a click on a line types there), the files as latching keys
//                 (UNIVERSAL, ALL RATES, IRIDIUM; ALSO MAKE: MIN PHASE, MIXES), SAVE TO CHANGE, RE-EXPORT OLD
//   sweep     2U  the old Advanced: RATE and LEVEL rotaries, SWEEPS, LENGTH, GAP and WARM-UP thumbwheels
//   formats   3U  the old Advanced file options: POLARITY and CUSTOM toggles, the custom files' latching keys, FULL ms
// sweep and formats stand under hinged smoked covers, shut by default: the settings show through, dimmed (the pane's
// tint multiplied over them, its sheen added); a click on the cover lifts it, a click on its hinges shuts it.
// Thumbwheels: each figure is the unit's own figure sheet, cut to its window (the deck counter's way); the buttons step
// the figure's place (tens, units, the half second), clamped to the setting's range. The old panels' explanations are
// in Help and on the printed forms.

extension RackKit {
    struct KeyRect: Decodable { let id: String; let rect: [CGFloat] }
    /// A rotary selector: its centre and knob radius, the position the base picture shows, each legend's rect (pt).
    /// Layer "sel<i>-p<j>" shows selector i turned to j.
    struct Selector: Decodable { let c: [CGFloat]; let r: CGFloat; let base: Int; let labels: [[CGFloat]] }
    /// Thumbwheel modules: each window, its + and - buttons (layers "tw<m>-plus", "tw<m>-minus" pressed), its kind
    /// ("d" 0-9, "h" 0/5, "b" 0/1) and group. `picture`: the ten figures, each a window wide.
    struct Wheels: Decodable {
        let picture: String
        let windows: [[CGFloat]]
        let plus: [[CGFloat]]
        let minus: [[CGFloat]]
        let kinds: [String]
        let groups: [String]
        func modules(_ g: String) -> [Int] { groups.indices.filter { groups[$0] == g } }
    }
    /// A smoked cover: the pane, the tint (multiplied) and sheen (added) pictures over `rect`, the latch and hinges.
    /// Layers "cover-hw" (shut: brackets, hinge rods, latch) and "cover-hw-open" (lifted: brackets and hinge rods).
    struct Cover: Decodable {
        let pane: [CGFloat]; let radius: CGFloat; let rect: [CGFloat]
        let tint: String; let tintScale: CGFloat; let sheen: String
        let latch: [CGFloat]; let hinges: [[CGFloat]]
    }
    struct Connect: Decodable {
        struct Select: Decodable { let c: [CGFloat]; let r: CGFloat }
        let keys: [KeyRect]
        let selectors: [Selector]
        let vfd: Shelf.Box.VFD
        let select: Select
        let wheels: Wheels
    }
    /// The capture card: a printed form (sheet cm, entries by their baselines) the app types into.
    struct Files: Decodable {
        struct Field: Decodable {
            let key: String; let label: String; let labelY: CGFloat; let note: String?
            let rules: [CGFloat]; let baselines: [CGFloat]; let x0: CGFloat; let x1: CGFloat
        }
        struct Form: Decodable { let w: CGFloat; let h: CGFloat; let margin: CGFloat; let typedCm: CGFloat; let advance: CGFloat; let fields: [Field] }
        let sheet: [CGFloat]
        let form: Form
        let keys: [KeyRect]
    }
    /// sweep and formats.
    struct Setup: Decodable {
        struct Toggle: Decodable { let c: [CGFloat]; let up: [CGFloat]; let down: [CGFloat] }
        let wheels: Wheels
        let selectors: [Selector]?
        let keys: [KeyRect]?
        let toggles: [Toggle]?
        let cover: Cover
    }
}

// ------------------------------------------------------------------ shared parts
/// A layer's picture placed at its rect (picture points).
struct RackLayerImage: View {
    let kit: RackKit
    let layer: RackKit.Layer?
    var body: some View {
        if let l = layer, let img = SwellPictures.shared.image(l.picture, pxPerPoint: kit.pxPerPoint) {
            Image(nsImage: img).resizable().interpolation(.high)
                .frame(width: l.rect[2], height: l.rect[3])
                .offset(x: l.rect[0], y: l.rect[1])
        }
    }
}

/// A clear button over a rendered key or button: its pressed layer shown while held.
struct RackPressButton: View {
    let kit: RackKit
    let unit: RackKit.Unit
    let rect: [CGFloat]
    let downLayer: String
    let label: String
    var help: String = ""
    let action: () -> Void
    var body: some View {
        let down = unit.layers[downLayer]
        let img = down.flatMap { SwellPictures.shared.image($0.picture, pxPerPoint: kit.pxPerPoint) }
        let off = down.map { CGPoint(x: $0.rect[0] - rect[0], y: $0.rect[1] - rect[1]) } ?? .zero
        let size = down.map { CGSize(width: $0.rect[2], height: $0.rect[3]) } ?? .zero
        Button(action: action) { Color.clear.frame(width: rect[2], height: rect[3]) }
            .buttonStyle(RackKeyStyle(down: img, offset: off, size: size))
            .accessibilityLabel(label)
            .help(help)
            .offset(x: rect[0], y: rect[1])
    }
}

/// The thumbwheels' figures, each cut from the unit's sheet into its window (drawn under a cover's tint).
struct RackWheelFigures: View {
    let kit: RackKit
    let wheels: RackKit.Wheels
    let figures: [Int?]
    var body: some View {
        if let sheet = SwellPictures.shared.cgImage(wheels.picture + ".webp") {
            let fw = sheet.width / 10
            ZStack(alignment: .topLeading) {
                ForEach(Array(figures.enumerated()), id: \.offset) { i, f in
                    if let f, i < wheels.windows.count, (0...9).contains(f),
                       let crop = sheet.cropping(to: CGRect(x: f * fw, y: 0, width: fw, height: sheet.height)) {
                        let r = wheels.windows[i]
                        Image(decorative: crop, scale: kit.pxPerPoint).resizable().interpolation(.high)
                            .frame(width: r[2], height: r[3]).offset(x: r[0], y: r[1])
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }
}

/// A thumbwheel setting: its modules (in the unit's wheels), the figure each shows for a value, each place's step.
struct WheelSetting {
    let modules: [Int]
    let figures: (Double) -> [Int]
    let steps: [Double]
    let range: ClosedRange<Double>
    let get: () -> Double
    let set: (Double) -> Void
    let name: String
    let spoken: (Double) -> String
    func step(_ place: Int, _ dir: Int) {
        let v = (get() + Double(dir) * steps[place]).clamped(to: range)
        if v != get() { set(v) } else { NSSound.beep() }
    }
}

extension Comparable {
    func clamped(to r: ClosedRange<Self>) -> Self { min(max(self, r.lowerBound), r.upperBound) }
}

/// The + and - buttons of the settings' modules, and each setting as one adjustable element for VoiceOver.
struct RackWheelButtons: View {
    let kit: RackKit
    let unit: RackKit.Unit
    let wheels: RackKit.Wheels
    let settings: [WheelSetting]
    var locked = false
    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(settings.enumerated()), id: \.offset) { _, s in
                ZStack(alignment: .topLeading) {
                    ForEach(Array(s.modules.enumerated()), id: \.offset) { place, m in
                        if m < wheels.plus.count {
                            RackPressButton(kit: kit, unit: unit, rect: wheels.plus[m], downLayer: "tw\(m)-plus", label: "\(s.name) up") { s.step(place, 1) }
                            RackPressButton(kit: kit, unit: unit, rect: wheels.minus[m], downLayer: "tw\(m)-minus", label: "\(s.name) down") { s.step(place, -1) }
                        }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(s.name)
                .accessibilityValue(s.spoken(s.get()))
                .accessibilityAdjustableAction { d in
                    switch d {
                    case .increment: s.step(s.modules.count - 1, 1)
                    case .decrement: s.step(s.modules.count - 1, -1)
                    @unknown default: break
                    }
                }
            }
        }
        .disabled(locked)
    }
    /// Every module's figure, in the wheels' order.
    static func figures(_ wheels: RackKit.Wheels, _ settings: [WheelSetting]) -> [Int?] {
        var f = [Int?](repeating: nil, count: wheels.windows.count)
        for s in settings {
            let v = s.figures(s.get())
            for (k, m) in s.modules.enumerated() where m < f.count && k < v.count { f[m] = v[k] }
        }
        return f
    }
}

/// A rotary selector's hit areas: each legend turns it there; a click on the knob turns it one place on (round).
struct RackSelectorControl: View {
    let sel: RackKit.Selector
    let names: [String]
    let pos: Int
    var available: (Int) -> Bool = { _ in true }
    let set: (Int) -> Void
    let label: String
    var locked = false
    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(sel.labels.enumerated()), id: \.offset) { j, r in
                Button { if available(j) { set(j) } else { NSSound.beep() } } label: {
                    Color.clear.frame(width: r[2], height: r[3])
                }
                .buttonStyle(.plain).contentShape(Rectangle())
                .help(j < names.count ? "\(label): \(names[j])\(available(j) ? "" : " (not offered by this interface)")" : "")
                .offset(x: r[0], y: r[1])
            }
            Button { next() } label: { Circle().fill(Color.clear).frame(width: 2 * sel.r, height: 2 * sel.r) }
                .buttonStyle(.plain).contentShape(Circle())
                .help("\(label): \(pos < names.count ? names[pos] : "")")
                .offset(x: sel.c[0] - sel.r, y: sel.c[1] - sel.r)
        }
        .disabled(locked)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(pos < names.count ? names[pos] : "")
        .accessibilityAdjustableAction { d in
            guard !locked else { return }
            let n = sel.labels.count
            var j = pos
            for _ in 0..<n {
                j = d == .increment ? min(n - 1, j + 1) : max(0, j - 1)
                if available(j) { set(j); return }
            }
        }
    }
    func next() {
        let n = sel.labels.count
        for k in 1...n { let j = (pos + k) % n; if available(j) { set(j); return } }
    }
    /// The layer showing the selector turned to `pos` (the base shows its own position).
    static func layer(_ i: Int, _ sel: RackKit.Selector, _ pos: Int) -> String? { pos == sel.base ? nil : "sel\(i)-p\(pos)" }
}

/// The smoked cover as drawn over the controls (under the tint: whatever the controls show). Shut: the pane's tint
/// multiplied, its sheen added, the brackets, hinges and latch; lifted: the brackets and hinge rods.
struct RackCoverPicture: View {
    let kit: RackKit
    let unit: RackKit.Unit
    let cover: RackKit.Cover
    let shut: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let r = cover.rect
        ZStack(alignment: .topLeading) {
            Group {
                if let t = SwellPictures.shared.image(cover.tint, pxPerPoint: kit.pxPerPoint) {
                    Image(nsImage: t).resizable().interpolation(.high).frame(width: r[2], height: r[3])
                        .offset(x: r[0], y: r[1]).blendMode(.multiply)
                }
                if let s = SwellPictures.shared.image(cover.sheen, pxPerPoint: kit.pxPerPoint) {
                    Image(nsImage: s).resizable().interpolation(.high).frame(width: r[2], height: r[3])
                        .offset(x: r[0], y: r[1]).blendMode(.plusLighter)
                }
                RackLayerImage(kit: kit, layer: unit.layers["cover-hw"])
            }
            .opacity(shut ? 1 : 0)
            RackLayerImage(kit: kit, layer: unit.layers["cover-hw-open"]).opacity(shut ? 0 : 1)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: shut)
        .allowsHitTesting(false)
    }
    static func pictures(_ c: RackKit.Cover) -> [String] { [c.tint, c.sheen] }
}

/// The cover's hit areas: shut, the whole pane (a click lifts it; nothing under it can be reached); lifted, the hinges
/// (a click shuts it).
struct RackCoverControl: View {
    let cover: RackKit.Cover
    @Binding var shut: Bool
    let name: String
    let summary: String
    var body: some View {
        ZStack(alignment: .topLeading) {
            if shut {
                let p = cover.pane
                Button { shut = false } label: {
                    RoundedRectangle(cornerRadius: cover.radius).fill(Color.clear).frame(width: p[2], height: p[3])
                }
                .buttonStyle(.plain).contentShape(RoundedRectangle(cornerRadius: cover.radius))
                .help("Lift the cover to change these settings")
                .offset(x: p[0], y: p[1])
                .accessibilityLabel("\(name) cover, shut")
                .accessibilityValue(summary)
                .accessibilityHint("Lifts the cover")
            } else {
                ForEach(Array(cover.hinges.enumerated()), id: \.offset) { i, h in
                    Button { shut = true } label: { Color.clear.frame(width: h[2], height: h[3]) }
                        .buttonStyle(.plain).contentShape(Rectangle())
                        .help("Shut the cover")
                        .offset(x: h[0], y: h[1])
                        .accessibilityLabel("Shut the \(name.lowercased()) cover")
                        .accessibilityHidden(i > 0)
                }
            }
        }
    }
}

/// A knob that opens a list on a click and steps it with the scroll wheel (the SELECT encoder). A trackpad scroll that
/// started elsewhere passes on to the page, so scrolling down the bay does not turn it.
struct RackEncoder: NSViewRepresentable {
    let click: () -> Void
    let step: (Int) -> Void
    final class V: NSView {
        var click: () -> Void = {}
        var step: (Int) -> Void = { _ in }
        private var owning = false
        private var acc: CGFloat = 0
        override func mouseDown(with e: NSEvent) { click() }
        override func scrollWheel(with e: NSEvent) {
            if e.momentumPhase != [] { owning = false; super.scrollWheel(with: e); return }
            if e.phase.contains(.began) { owning = true; acc = 0 }
            let gesture = e.phase != []
            guard !gesture || owning else { super.scrollWheel(with: e); return }
            if e.phase.contains(.ended) || e.phase.contains(.cancelled) { owning = false }
            let d = e.hasPreciseScrollingDeltas ? e.scrollingDeltaY / 18 : e.scrollingDeltaY
            acc += d
            while acc >= 1 { acc -= 1; step(-1) }
            while acc <= -1 { acc += 1; step(1) }
        }
        override func acceptsFirstMouse(for e: NSEvent?) -> Bool { true }
    }
    func makeNSView(context: Context) -> V { let v = V(); v.click = click; v.step = step; return v }
    func updateNSView(_ v: V, context: Context) { v.click = click; v.step = step }
}

/// A unit's picture with the controls laid over it: `under` in the picture's points under any cover's tint (figures,
/// typing, the cover itself), `controls` in the picture's points over everything.
struct RackSetupFrame<Under: View, Controls: View>: View {
    let kit: RackKit
    let unit: RackKit.Unit
    let on: Set<String>
    @ViewBuilder let under: Under
    @ViewBuilder let controls: Controls
    var body: some View {
        ZStack(alignment: .topLeading) {
            RackUnitPicture(kit: kit, unit: unit, on: on, filament: true,
                            own: { ($0.hasPrefix("k") && $0.hasSuffix("down")) || $0.hasPrefix("tw") || $0.hasPrefix("cover") },
                            overlay: AnyView(ZStack(alignment: .topLeading) { under }
                                .frame(width: unit.size[0], height: unit.size[1], alignment: .topLeading)),
                            instant: { $0.hasPrefix("sel") || $0.hasPrefix("t") })
            ZStack(alignment: .topLeading) { controls }
                .frame(width: unit.size[0], height: unit.size[1], alignment: .topLeading)
                .offset(x: -unit.panel[0], y: -unit.panel[1])
        }
        .frame(width: kit.panelWidth, height: CGFloat(unit.u) * kit.uPt, alignment: .topLeading)
    }
}

extension RackKit {
    /// The setup units' extra pictures (figure sheets, a cover's tint and sheen), for `ready`.
    var setupPictures: (Unit) -> [String] {
        { u in
            var f: [String] = []
            if let c = u.connect { f.append(c.wheels.picture) }
            for s in [u.sweep, u.formats].compactMap({ $0 }) { f += [s.wheels.picture] + RackCoverPicture.pictures(s.cover) }
            if let p = u.plotter { f += p.parts.values.map(\.picture) }
            return f
        }
    }
}

// ------------------------------------------------------------------ connect (2U)
struct RackConnectUnit: View {
    @EnvironmentObject var m: AppModel
    static var available: Bool { RackKit.ready("connect")?.1.connect != nil }
    static let refNames = ["None", "Load box line out", "Reference tap or pad"]
    static let refs: [RefSource] = [.none, .loadBox, .tap]

    /// The interface's name for the 20-character VFD: capitals, whole words while they fit.
    static func vfdName(_ d: AudioDevice?, n: Int) -> String {
        guard let d else { return "NO INTERFACE" }
        let words = d.name.uppercased().split(separator: " ").map(String.init)
        var s = ""
        for w in words {
            let t = s.isEmpty ? w : s + " " + w
            if t.count > n { break }
            s = t
        }
        return s.isEmpty ? String(d.name.uppercased().prefix(n)) : s
    }

    var body: some View {
        if let r = RackKit.ready("connect"), let c = r.1.connect {
            let kit = r.0, u = r.1
            let refPos = Self.refs.firstIndex(of: m.refSource) ?? 0
            let sel = c.selectors.first
            let on = Set([sel.flatMap { RackSelectorControl.layer(0, $0, refPos) }].compactMap { $0 })
            let out = outSetting
            RackSetupFrame(kit: kit, unit: u, on: on) {
                VFDStatusLine(text: Self.vfdName(m.device, n: c.vfd.n), on: VFDGeometry(
                    cells: CGRect(x: c.vfd.cells[0], y: c.vfd.cells[1], width: c.vfd.cells[2], height: c.vfd.cells[3]),
                    mtx: c.vfd.mtx, n: c.vfd.n, size: CGSize(width: u.size[0], height: u.size[1])))
                    .allowsHitTesting(false)
                RackWheelFigures(kit: kit, wheels: c.wheels, figures: m.device == nil ? [nil, nil] : RackWheelButtons.figures(c.wheels, [out]))
            } controls: {
                // the VFD: the whole name and the device's channels as a tooltip
                let v = c.vfd.cells
                Color.clear.contentShape(Rectangle()).frame(width: v[2], height: v[3]).offset(x: v[0], y: v[1])
                    .help(m.device.map { "\($0.name): \($0.inputChannels) in, \($0.outputChannels) out" }
                          ?? "No audio interface with both inputs and outputs is connected. Connect the interface and switch it on. It is listed here automatically.")
                    .accessibilityElement().accessibilityLabel("Interface").accessibilityValue(m.device?.name ?? "None connected")
                RackEncoder(click: showInterfaces, step: stepInterface)
                    .frame(width: 2 * c.select.r, height: 2 * c.select.r)
                    .clipShape(Circle())
                    .offset(x: c.select.c[0] - c.select.r, y: c.select.c[1] - c.select.r)
                    .help(m.audioActive ? "Stop the level check or recording to change the interface" : "Choose the interface (click for the list, or turn with the scroll wheel)")
                    .accessibilityElement().accessibilityLabel("Select interface").accessibilityAddTraits(.isButton)
                    .accessibilityAction { showInterfaces() }
                ForEach(Array(c.keys.enumerated()), id: \.offset) { i, k in
                    if k.id == "midi-setup" {
                        RackPressButton(kit: kit, unit: u, rect: k.rect, downLayer: "k\(i)-down", label: "Open Audio MIDI Setup",
                                        help: "If inputs and outputs are on two devices, combine them into an aggregate device in Audio MIDI Setup") {
                            CoreAudioHelper.openAudioMIDISetup()
                        }
                    } else {
                        RackPressButton(kit: kit, unit: u, rect: k.rect, downLayer: "k\(i)-down", label: "Import DAW recordings",
                                        help: "Play the test signal from a DAW, record the mics there, and import the files here") {
                            m.cabImport = true
                        }
                        .disabled(m.busy != nil)
                    }
                }
                if m.device != nil {
                    RackWheelButtons(kit: kit, unit: u, wheels: c.wheels, settings: [out], locked: m.audioActive)
                }
                if let sel {
                    RackSelectorControl(sel: sel, names: Self.refNames, pos: refPos, set: { m.refSource = Self.refs[$0] },
                                        label: "Reference")
                }
            }
        }
    }

    var outSetting: WheelSetting {
        let n = Double(max(1, m.device?.outputChannels ?? 1))
        return WheelSetting(modules: RackKit.ready("connect")?.1.connect?.wheels.modules("out") ?? [0, 1],
                            figures: { v in [Int(v) / 10 % 10, Int(v) % 10] }, steps: [10, 1], range: 1...min(99, n),
                            get: { Double(m.outChannel + 1) }, set: { m.outChannel = Int($0) - 1 },
                            name: "Output to the amp", spoken: { "Output \(Int($0))" })
    }

    func showInterfaces() {
        guard !m.audioActive else { NSSound.beep(); return }
        let list = m.duplexDevices
        if list.isEmpty {
            PopUpMenu.show([(title: "No interface connected", checked: false, action: {})])
            return
        }
        PopUpMenu.show(list.map { d in
            (title: "\(d.name)  (\(d.inputChannels) in / \(d.outputChannels) out)", checked: d.uid == m.deviceUID, action: { m.deviceUID = d.uid })
        })
    }

    func stepInterface(_ dir: Int) {
        guard !m.audioActive else { return }
        let list = m.duplexDevices
        guard !list.isEmpty else { return }
        let i = list.firstIndex { $0.uid == m.deviceUID } ?? 0
        let j = max(0, min(list.count - 1, i + dir))
        if j != i { m.deviceUID = list[j].uid }
    }
}

// ------------------------------------------------------------------ files (4U)
struct RackFilesUnit: View {
    @EnvironmentObject var m: AppModel
    static var available: Bool { RackKit.ready("files")?.1.files != nil }
    /// The latching keys' targets (ExportTarget ids), by the key's id.
    static let targetOf = ["f-universal": "universal", "f-allrates": "everything", "f-iridium": "iridium",
                           "f-minphase": "minphase", "f-mixes": "mixes"]
    static let spokenOf = ["f-universal": "Universal", "f-allrates": "All sample rates", "f-iridium": "Strymon Iridium",
                           "f-minphase": "Minimum-phase versions", "f-mixes": "Mixes of two mics"]
    @State private var editing: String?

    var body: some View {
        if let r = RackKit.ready("files"), let f = r.1.files {
            let kit = r.0, u = r.1
            let on = Set(f.keys.indices.compactMap { i -> String? in
                guard let t = Self.targetOf[f.keys[i].id] else { return nil }
                return m.targets.contains(t) ? "k\(i)-lit" : nil
            })
            RackSetupFrame(kit: kit, unit: u, on: on) {
                CaptureCardInk(form: f.form, sheet: f.sheet, name: m.captureName, notes: m.notes,
                               folder: m.outputFolder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"), hide: editing)
            } controls: {
                CaptureCardFields(form: f.form, sheet: f.sheet, editing: $editing)
                ForEach(Array(f.keys.enumerated()), id: \.offset) { i, k in key(i, k, kit: kit, u: u) }
            }
        }
    }

    @ViewBuilder func key(_ i: Int, _ k: RackKit.KeyRect, kit: RackKit, u: RackKit.Unit) -> some View {
        if let t = Self.targetOf[k.id] {
            let lit = m.targets.contains(t)
            RackPressButton(kit: kit, unit: u, rect: k.rect, downLayer: "k\(i)-\(lit ? "litdown" : "down")", label: Self.spokenOf[k.id] ?? k.id,
                            help: (ExportTarget.destinations + ExportTarget.extras).first { $0.id == t }?.detail ?? "") {
                if lit { m.targets.remove(t) } else { m.targets.insert(t) }
            }
            .accessibilityAddTraits(lit ? .isSelected : [])
        } else if k.id == "change" {
            RackPressButton(kit: kit, unit: u, rect: k.rect, downLayer: "k\(i)-down", label: "Change the save folder",
                            help: "Choose the folder the captures are saved in") { m.chooseOutputFolder() }
        } else {
            RackPressButton(kit: kit, unit: u, rect: k.rect, downLayer: "k\(i)-down", label: "Re-export a past capture",
                            help: "Make other formats from the raw take of a past capture without a new recording") { m.chooseReexportFolder() }
                .disabled(m.busy != nil)
        }
    }
}

/// The capture card's typing (multiplied over the printed form): the name, the notes on three lines, the save folder.
/// A field being typed into is left to its text field.
struct CaptureCardInk: View {
    let form: RackKit.Files.Form
    let sheet: [CGFloat]
    let name: String
    let notes: String
    let folder: String
    let hide: String?
    var body: some View {
        Canvas { ctx, _ in ctx.withCGContext { cg in draw(cg) } }
            .frame(width: sheet[2], height: sheet[3])
            .offset(x: sheet[0], y: sheet[1])
            .blendMode(.multiply)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
    private var k: CGFloat { sheet[2] / form.w }
    func draw(_ cg: CGContext) {
        let pt = form.typedCm * k, adv = form.advance * pt
        let font = CTFontCreateWithName("CourierPrime-Regular" as CFString, pt, nil)
        cg.textMatrix = .identity
        for f in form.fields where f.key != hide {
            let n = max(1, Int((f.x1 - f.x0) * k / adv))
            let lines: [String]
            switch f.key {
            case "name": lines = [TakeSheetInk.fit(name, n)]
            case "notes": lines = CaptureCardInk.wrap(notes, n, f.baselines.count)
            default: lines = [TakeSheetInk.fitMiddle(folder, n)]
            }
            for (i, t) in lines.enumerated() where i < f.baselines.count && !t.isEmpty {
                var rng = InkRandom(s: TakeSheet.hash(f.key + "|\(i)|" + t))
                PaperInk.type(cg, font, t, x: f.x0 * k, baseline: f.baselines[i] * k, adv: adv, k: k, rng: &rng)
            }
        }
    }
    /// Words to lines of n characters; past the last line, the rest is cut with "…".
    static func wrap(_ s: String, _ n: Int, _ rows: Int) -> [String] {
        var out: [String] = []
        for para in s.split(separator: "\n", omittingEmptySubsequences: false) {
            var cur = ""
            for w in para.split(separator: " ").map(String.init) {
                var w = w
                while w.count > n { if !cur.isEmpty { out.append(cur); cur = "" }; out.append(String(w.prefix(n))); w = String(w.dropFirst(n)) }
                let t = cur.isEmpty ? w : cur + " " + w
                if t.count > n { out.append(cur); cur = w } else { cur = t }
            }
            out.append(cur)
        }
        while out.last == "" && out.count > 1 { out.removeLast() }
        if out.count > rows {
            var keep = Array(out.prefix(rows))
            keep[rows - 1] = TakeSheetInk.fit(keep[rows - 1] + " " + out[rows], n)
            if !keep[rows - 1].hasSuffix("…") { keep[rows - 1] = String(keep[rows - 1].prefix(n - 1)) + "…" }
            return keep
        }
        return out
    }
}

/// The card's lines as places to click: a click on the name or notes types there (a plain text field in the typewriter's
/// face, on the line), Return or a click elsewhere ends it; the save folder's line chooses the folder.
struct CaptureCardFields: View {
    @EnvironmentObject var m: AppModel
    let form: RackKit.Files.Form
    let sheet: [CGFloat]
    @Binding var editing: String?
    @FocusState private var focus: String?
    var body: some View {
        let k = sheet[2] / form.w, pt = form.typedCm * k
        ZStack(alignment: .topLeading) {
            ForEach(form.fields, id: \.key) { f in
                let top = (f.rules.first ?? f.labelY) - 0.95 + 0.15
                let bottom = (f.rules.last ?? f.labelY) + 0.12
                let x0 = sheet[0] + (f.x0 - 0.1) * k, y0 = sheet[1] + top * k
                let w = (f.x1 - f.x0 + 0.1) * k, h = (bottom - top) * k
                if editing == f.key {
                    field(f, pt: pt, k: k)
                        .frame(width: w, height: h, alignment: .topLeading)
                        .offset(x: x0 + 0.1 * k - 1, y: sheet[1] + (f.baselines[0] - 0.78 * form.typedCm) * k - 2)
                } else {
                    Button {
                        if f.key == "folder" { m.chooseOutputFolder() } else { editing = f.key; DispatchQueue.main.async { focus = f.key } }
                    } label: { Color.clear.frame(width: w, height: h) }
                    .buttonStyle(.plain).contentShape(Rectangle())
                    .help(help(f.key))
                    .offset(x: x0, y: y0)
                    .accessibilityLabel(label(f.key))
                    .accessibilityValue(value(f.key))
                    .accessibilityHint(f.key == "folder" ? "Chooses the folder" : "Types on the card")
                }
            }
        }
        .onChange(of: focus) { f in if f == nil { editing = nil } }
    }
    @ViewBuilder func field(_ f: RackKit.Files.Field, pt: CGFloat, k: CGFloat) -> some View {
        let ink = Color(.sRGB, red: 34 / 255, green: 32 / 255, blue: 44 / 255)
        let font = Font.custom("CourierPrime-Regular", size: pt)
        if f.key == "name" {
            TextField("", text: $m.captureName)
                .textFieldStyle(.plain).font(font).foregroundColor(ink)
                .focused($focus, equals: "name")
                .onSubmit { focus = nil }
                .accessibilityLabel("Capture name")
        } else {
            TextField("", text: $m.notes, axis: .vertical)
                .textFieldStyle(.plain).font(font).foregroundColor(ink)
                .lineLimit(f.baselines.count, reservesSpace: true)
                .lineSpacing(max(0, 0.95 * k - pt * 1.13))
                .focused($focus, equals: "notes")
                .onSubmit { focus = nil }
                .accessibilityLabel("Notes")
        }
    }
    func help(_ key: String) -> String {
        switch key {
        case "name": return "Cab and mic position, e.g. 412_V30_PosA. All file names start with this name. Click to type."
        case "notes": return "Mic positions, distances, amp settings. Saved in report.json. Click to type."
        default: return "The folder the captures are saved in: \(m.outputFolder.path). Click to change."
        }
    }
    func label(_ key: String) -> String { key == "name" ? "Capture name" : key == "notes" ? "Notes" : "Save to" }
    func value(_ key: String) -> String { key == "name" ? m.captureName : key == "notes" ? m.notes : m.outputFolder.path }
}

// ------------------------------------------------------------------ sweep (2U)
struct RackSweepUnit: View {
    @EnvironmentObject var m: AppModel
    @AppStorage("rack.cover.sweep") private var shut = true
    static var available: Bool { RackKit.ready("sweep")?.1.sweep != nil }
    static let rates = [0] + CoreAudioHelper.captureRates
    static let levels: [Double] = [0, -6, -12, -18, -24]

    var body: some View {
        if let r = RackKit.ready("sweep"), let s = r.1.sweep {
            let kit = r.0, u = r.1
            let settings = wheelSettings(s.wheels)
            let ratePos = Self.rates.firstIndex(of: m.rateChoice) ?? 0
            let levelPos = Self.levels.firstIndex(of: m.levelChoice) ?? 0
            let sels = s.selectors ?? []
            let on = Set([sels.count > 0 ? RackSelectorControl.layer(0, sels[0], ratePos) : nil,
                          sels.count > 1 ? RackSelectorControl.layer(1, sels[1], levelPos) : nil].compactMap { $0 })
            RackSetupFrame(kit: kit, unit: u, on: on) {
                RackWheelFigures(kit: kit, wheels: s.wheels, figures: RackWheelButtons.figures(s.wheels, settings))
                RackCoverPicture(kit: kit, unit: u, cover: s.cover, shut: shut)
            } controls: {
                if !shut {
                    if sels.count > 1 {
                        RackSelectorControl(sel: sels[0], names: Self.rates.map { $0 == 0 ? "Automatic (\(rateTag(m.device.map(CoreAudioHelper.bestRate) ?? 96000).dropLast()) kHz)" : "\(rateTag($0).dropLast()) kHz" },
                                            pos: ratePos, available: { j in j == 0 || m.deviceRates.contains(Self.rates[j]) },
                                            set: { m.rateChoice = Self.rates[$0] }, label: "Sample rate", locked: m.audioActive)
                        RackSelectorControl(sel: sels[1], names: Self.levels.map { $0 == 0 ? "Automatic" : "\(Int($0)) dBFS" },
                                            pos: levelPos, set: { m.levelChoice = Self.levels[$0] }, label: "Sweep level", locked: m.audioActive)
                    }
                    RackWheelButtons(kit: kit, unit: u, wheels: s.wheels, settings: settings, locked: m.audioActive)
                }
                RackCoverControl(cover: s.cover, shut: $shut, name: "Sweep set-up", summary: summary)
            }
            .help(m.audioActive && !shut ? "Stop the level check or recording to change these" : "")
        }
    }

    var summary: String {
        let rate = m.rateChoice == 0 ? "automatic rate" : "\(rateTag(m.rateChoice).dropLast()) kHz"
        let lvl = m.levelChoice == 0 ? "automatic sweep level" : "sweep level \(Int(m.levelChoice)) dBFS"
        return "\(rate), \(lvl), \(m.nSweeps) sweeps of \(String(format: "%g", m.duration)) s, gap \(String(format: "%g", m.gap)) s, \(m.discard) warm-up"
    }

    func wheelSettings(_ w: RackKit.Wheels) -> [WheelSetting] {
        let halves: (Double) -> [Int] = { v in [Int(v) / 10 % 10, Int(v) % 10, v - v.rounded(.down) >= 0.5 ? 5 : 0] }
        return [
            WheelSetting(modules: w.modules("sweeps"), figures: { v in [Int(v) / 10 % 10, Int(v) % 10] }, steps: [10, 1], range: 2...16,
                         get: { Double(m.nSweeps) }, set: { m.nSweeps = Int($0) }, name: "Sweeps", spoken: { "\(Int($0))" }),
            WheelSetting(modules: w.modules("length"), figures: halves, steps: [10, 1, 0.5], range: 2...20,
                         get: { m.duration }, set: { m.duration = $0 }, name: "Sweep length", spoken: { String(format: "%g seconds", $0) }),
            WheelSetting(modules: w.modules("gap"), figures: halves, steps: [10, 1, 0.5], range: 1...10,
                         get: { m.gap }, set: { m.gap = $0 }, name: "Gap", spoken: { String(format: "%g seconds", $0) }),
            WheelSetting(modules: w.modules("warm-up"), figures: { v in [Int(v) % 10] }, steps: [1], range: 0...4,
                         get: { Double(m.discard) }, set: { m.discard = Int($0) }, name: "Warm-up sweeps", spoken: { "\(Int($0))" }),
        ]
    }
}

// ------------------------------------------------------------------ formats (3U)
struct RackFormatsUnit: View {
    @EnvironmentObject var m: AppModel
    @AppStorage("rack.cover.formats") private var shut = true
    static var available: Bool { RackKit.ready("formats")?.1.formats != nil }
    /// The custom keys: which set each belongs to, and its value there.
    enum Custom { case rate(Int), length(String), bits(String), trim(String) }
    static let customOf: [String: Custom] = [
        "c-441": .rate(44100), "c-48": .rate(48000), "c-882": .rate(88200), "c-96": .rate(96000),
        "c-full": .length("full"), "c-1024": .length("1024"), "c-2048": .length("2048"), "c-4096": .length("4096"),
        "c-16": .bits("16"), "c-24": .bits("24"), "c-32f": .bits("32f"), "c-set": .trim("set"), "c-individual": .trim("individual")]
    static let spokenOf: [String: String] = [
        "c-441": "44.1 kHz", "c-48": "48 kHz", "c-882": "88.2 kHz", "c-96": "96 kHz", "c-full": "Full room length", "c-1024": "1024 samples",
        "c-2048": "2048 samples", "c-4096": "4096 samples", "c-16": "16-bit", "c-24": "24-bit", "c-32f": "32-bit float",
        "c-set": "Keep mic timing", "c-individual": "Trim each mic"]

    func isOn(_ c: Custom) -> Bool {
        switch c {
        case .rate(let r): return m.exportRates.contains(r)
        case .length(let l): return m.lengths.contains(l)
        case .bits(let b): return m.bits.contains(b)
        case .trim(let t): return m.trims.contains(t)
        }
    }
    func flip(_ c: Custom) {
        switch c {
        case .rate(let r): if m.exportRates.contains(r) { m.exportRates.remove(r) } else { m.exportRates.insert(r) }
        case .length(let l): if m.lengths.contains(l) { m.lengths.remove(l) } else { m.lengths.insert(l) }
        case .bits(let b): if m.bits.contains(b) { m.bits.remove(b) } else { m.bits.insert(b) }
        case .trim(let t): if m.trims.contains(t) { m.trims.remove(t) } else { m.trims.insert(t) }
        }
    }

    var body: some View {
        if let r = RackKit.ready("formats"), let s = r.1.formats, let keys = s.keys {
            let kit = r.0, u = r.1
            let full = fullSetting(s.wheels)
            let on = lit(keys)
            RackSetupFrame(kit: kit, unit: u, on: on) {
                RackWheelFigures(kit: kit, wheels: s.wheels, figures: RackWheelButtons.figures(s.wheels, [full]))
                RackCoverPicture(kit: kit, unit: u, cover: s.cover, shut: shut)
            } controls: {
                if !shut {
                    toggles(s.toggles ?? [])
                    ForEach(Array(keys.enumerated()), id: \.offset) { i, k in
                        if let c = Self.customOf[k.id] {
                            let lit = m.customOn && isOn(c)
                            RackPressButton(kit: kit, unit: u, rect: k.rect, downLayer: "k\(i)-\(lit ? "litdown" : "down")",
                                            label: "Custom files, \(Self.spokenOf[k.id] ?? k.id)",
                                            help: m.customOn ? "Custom files are saved in More formats › Custom" : "Set CUSTOM to ON to choose custom files") { flip(c) }
                                .disabled(!m.customOn)
                                .accessibilityAddTraits(lit ? .isSelected : [])
                        }
                    }
                    RackWheelButtons(kit: kit, unit: u, wheels: s.wheels, settings: [full], locked: !m.customOn)
                }
                RackCoverControl(cover: s.cover, shut: $shut, name: "File options", summary: summary)
            }
        }
    }

    func lit(_ keys: [RackKit.KeyRect]) -> Set<String> {
        var on = Set(keys.indices.compactMap { i -> String? in
            guard m.customOn, let c = Self.customOf[keys[i].id], isOn(c) else { return nil }
            return "k\(i)-lit"
        })
        if m.keepPolarity { on.insert("t0-down") }
        if !m.customOn { on.insert("t1-down") }
        return on
    }

    @ViewBuilder func toggles(_ ts: [RackKit.Setup.Toggle]) -> some View {
        ForEach(Array(ts.enumerated()), id: \.offset) { i, t in
            let up = i == 0 ? !m.keepPolarity : m.customOn
            let names = i == 0 ? ("Positive", "As recorded") : ("On", "Off")
            let set: (Bool) -> Void = { u in if i == 0 { m.keepPolarity = !u } else { m.customOn = u } }
            ZStack(alignment: .topLeading) {
                Button { set(true) } label: { Color.clear.frame(width: t.up[2], height: t.up[3]) }
                    .buttonStyle(.plain).contentShape(Rectangle()).offset(x: t.up[0], y: t.up[1])
                    .help(i == 0 ? "Each IR is made with its main peak positive, as in commercial IR packs, so mics blend without cancellation" : "Make the custom files chosen on the keys")
                Button { set(false) } label: { Color.clear.frame(width: t.down[2], height: t.down[3]) }
                    .buttonStyle(.plain).contentShape(Rectangle()).offset(x: t.down[0], y: t.down[1])
                    .help(i == 0 ? "Keep each IR's polarity as recorded" : "No custom files")
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(i == 0 ? "Polarity" : "Custom files")
            .accessibilityValue(up ? names.0 : names.1)
            .accessibilityAdjustableAction { d in set(d == .increment) }
        }
    }

    var summary: String {
        var s = m.keepPolarity ? "polarity as recorded" : "polarity positive"
        s += m.customOn ? ", custom files on, full room \(Int(m.fullMs)) ms" : ", custom files off"
        return s
    }

    func fullSetting(_ w: RackKit.Wheels) -> WheelSetting {
        WheelSetting(modules: w.modules("fullms"), figures: { v in let i = Int(v.rounded()); return [i / 1000 % 10, i / 100 % 10, i % 100 >= 50 ? 5 : 0] },
                     steps: [1000, 100, 50], range: 50...1000, get: { m.fullMs }, set: { m.fullMs = $0 },
                     name: "Full room length", spoken: { "\(Int($0)) milliseconds" })
    }
}
#endif
