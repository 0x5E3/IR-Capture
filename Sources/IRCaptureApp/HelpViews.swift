#if os(macOS)
import AppKit
import AVFoundation
import SwiftUI
import IRCaptureCore

// ------------------------------------------------------------------ wiring diagrams (P0.12)
struct DiagramNode {
    enum Kind { case interface, gear, speaker, mic, tap }
    let title: String
    let sub: String
    let kind: Kind
    /// Label on the arrow coming into this node.
    var via: String? = nil
}

enum Wiring: String, CaseIterable {
    case cabNoRef, cabRef, namAmp, namFull, pad
    /// The four hook-ups (the pad is a build drawing, shown on the reference page).
    static var hookups: [Wiring] { [.cabNoRef, .cabRef, .namAmp, .namFull] }
    var title: String {
        switch self {
        case .cabNoRef: return "Cab IR, no reference"
        case .cabRef: return "Cab IR with a reference"
        case .namAmp: return "NAM: amp only"
        case .namFull: return "NAM: full chain"
        case .pad: return "A 20 dB reference pad"
        }
    }
    var rows: [[DiagramNode]] {
        let out = DiagramNode(title: "Interface", sub: "Output", kind: .interface)
        let power = DiagramNode(title: "Amp FX return", sub: "or a clean power amp", kind: .gear, via: "line level")
        let cab = DiagramNode(title: "Cab", sub: "speaker", kind: .speaker, via: "speaker cable")
        let mics = DiagramNode(title: "Mic(s)", sub: "on the cab", kind: .mic)
        let ins = DiagramNode(title: "Interface", sub: "mic inputs", kind: .interface, via: "XLR")
        let reamp = DiagramNode(title: "Reamp box", sub: "", kind: .gear, via: "line level")
        let ampIn = DiagramNode(title: "Amp", sub: "guitar input", kind: .gear, via: "instrument level")
        switch self {
        case .cabNoRef:
            return [[out, power, cab], [mics, ins]]
        case .cabRef:
            return [[out, power, cab], [mics, ins],
                    [DiagramNode(title: "Speaker terminals", sub: "amp output", kind: .speaker),
                     DiagramNode(title: "Reference", sub: "load-box line out or 20 dB pad", kind: .tap),
                     DiagramNode(title: "Interface", sub: "a line input", kind: .interface, via: "line level")]]
        case .namAmp:
            return [[out, reamp, ampIn],
                    [DiagramNode(title: "Amp", sub: "speaker output", kind: .gear),
                     DiagramNode(title: "Load box", sub: "reactive, cab sim off", kind: .tap, via: "speaker cable"),
                     DiagramNode(title: "Interface", sub: "a line input", kind: .interface, via: "line out")]]
        case .namFull:
            return [[out, reamp, ampIn],
                    [DiagramNode(title: "Amp", sub: "speaker output", kind: .gear), DiagramNode(title: "Cab", sub: "speaker", kind: .speaker, via: "speaker cable")],
                    [mics, ins]]
        case .pad:
            return [[DiagramNode(title: "Speaker +", sub: "terminal", kind: .speaker),
                     DiagramNode(title: "Tap point", sub: "between the resistors", kind: .tap, via: "10 kΩ, ½ W"),
                     DiagramNode(title: "Speaker −", sub: "terminal", kind: .speaker, via: "1.1 kΩ")],
                    [DiagramNode(title: "Tap point", sub: "", kind: .tap),
                     DiagramNode(title: "¼\" jack", sub: "tip; sleeve to speaker −", kind: .gear, via: "wire"),
                     DiagramNode(title: "Interface", sub: "a line input, phantom off", kind: .interface, via: "cable")]]
        }
    }
    var footnote: String {
        switch self {
        case .cabNoRef, .cabRef: return "Studio monitors muted. Amp master low to start."
        case .namAmp: return "Gates, reverb, delay and loop effects off."
        case .namFull: return "Gates, reverb, delay and loop effects off. Studio monitors muted."
        case .pad: return "Connect the pad in parallel with the speaker. Keep the speaker connected. Voltage division: about 10:1 (−19 dB)."
        }
    }
}

struct WiringDiagram: View {
    let wiring: Wiring
    var compact = false
    @Environment(\.swellSurface) private var surface
    /// On paper the diagram is a draftsman's line drawing in ink; elsewhere (the exported PNGs) it keeps its colours.
    var ink: Bool { surface == .paper }
    func color(_ k: DiagramNode.Kind) -> Color {
        if ink { return Swell.tagInk }
        switch k {
        case .interface: return lamp
        case .gear: return Color(red: 0.45, green: 0.5, blue: 0.58)
        case .speaker: return Color(red: 0.36, green: 0.45, blue: 0.36)
        case .mic: return Color(red: 0.44, green: 0.64, blue: 0.84)
        case .tap: return Color(red: 0.61, green: 0.45, blue: 0.7)
        }
    }
    var nodeWidth: CGFloat { compact ? 112 : 132 }
    var iconSize: CGSize { compact ? CGSize(width: 60, height: 36) : CGSize(width: 72, height: 44) }
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 14) {
            ForEach(Array(wiring.rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.offset) { i, n in
                        if i > 0 {
                            VStack(spacing: 1) {
                                Text(n.via ?? "").font(ink ? Font.swellBody(10) : Font.system(size: 9)).foregroundStyle(ink ? Swell.tagInk.opacity(0.8) : Color.secondary).lineLimit(1).minimumScaleFactor(0.8)
                                InkArrow(color: ink ? Swell.tagInk : Color.secondary)
                            }
                            .frame(width: compact ? 58 : 74)
                            .padding(.top, max(0, iconSize.height / 2 - 17))
                        }
                        VStack(spacing: 3) {
                            GearIcon(kind: GearIcon.Kind(n))
                                .stroke(color(n.kind), style: StrokeStyle(lineWidth: ink ? 1.25 : 1.5, lineCap: .round, lineJoin: .round))
                                .frame(width: iconSize.width, height: iconSize.height)
                                .accessibilityHidden(true)
                            Text(n.title).font(ink ? Font.swellLegend(compact ? 10.5 : 11.5) : Font.system(size: compact ? 11 : 12, weight: .semibold))
                                .textCase(ink ? Text.Case.uppercase : nil).tracking(ink ? 0.6 : 0).multilineTextAlignment(.center)
                            if !n.sub.isEmpty {
                                Text(n.sub).font(ink ? Font.swellBody(compact ? 10 : 11) : Font.system(size: compact ? 9 : 10))
                                    .foregroundStyle(ink ? Swell.tagInk.opacity(0.8) : Color.secondary).multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(width: nodeWidth)
                    }
                }
            }
            HStack(alignment: .bottom, spacing: 12) {
                Text(wiring.footnote).font(ink ? Font.swellBody(11) : Font.caption).foregroundStyle(ink ? Swell.tagInk.opacity(0.8) : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if ink && !compact { TitleBlock(title: wiring.title, number: (Wiring.allCases.firstIndex(of: wiring) ?? 0) + 1) }
            }
        }
        .padding(ink ? 0 : (compact ? 8 : 12))
        .background(RoundedRectangle(cornerRadius: 8).fill(ink ? Color.clear : Color.secondary.opacity(0.05)))
    }
}

/// A drawing's title block in the lower right, as on a drafting sheet.
struct TitleBlock: View {
    let title: String
    let number: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.swellLegend(9.5)).textCase(.uppercase).tracking(0.8)
                .padding(.horizontal, 6).padding(.vertical, 3)
            Rectangle().fill(Swell.tagInk.opacity(0.7)).frame(height: 0.8)
            HStack(spacing: 0) {
                Text("Wiring").font(.swellLegend(8)).textCase(.uppercase).tracking(0.8).padding(.horizontal, 6).padding(.vertical, 2)
                Rectangle().fill(Swell.tagInk.opacity(0.7)).frame(width: 0.8)
                Text("Dwg W-\(number)").font(.swellLegend(8)).textCase(.uppercase).tracking(0.8).padding(.horizontal, 6).padding(.vertical, 2)
            }
        }
        .foregroundColor(Swell.tagInk)
        .fixedSize()
        .overlay(Rectangle().stroke(Swell.tagInk.opacity(0.8), lineWidth: 1))
        .accessibilityHidden(true)
    }
}

/// The gear in a wiring drawing, drawn as a draftsman would: an interface, an amp, a reamp box, a cab with its
/// speakers, the speaker terminals, a mic, a load box, a pad, a jack. Line drawings only (the bench's rule: real-looking
/// gear on the rig, line drawings on paper). Every figure fits its rect.
struct GearIcon: Shape {
    enum Kind {
        case interface, amp, reamp, cab, terminals, mic, loadBox, pad, jack
        init(_ n: DiagramNode) {
            let t = n.title.lowercased()
            if t.hasPrefix("interface") { self = .interface }
            else if t.hasPrefix("reamp") { self = .reamp }
            else if t.hasPrefix("amp") { self = .amp }
            else if t.hasPrefix("cab") { self = .cab }
            else if t.hasPrefix("speaker") { self = .terminals }
            else if t.hasPrefix("mic") { self = .mic }
            else if t.hasPrefix("load box") || t.hasPrefix("reference") { self = .loadBox }
            else if t.hasPrefix("tap point") { self = .pad }
            else if t.contains("jack") { self = .jack }
            else {
                switch n.kind {
                case .interface: self = .interface
                case .speaker: self = .cab
                case .mic: self = .mic
                case .tap: self = .loadBox
                case .gear: self = .amp
                }
            }
        }
    }
    let kind: Kind
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height, x0 = r.minX, y0 = r.minY
        func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x0 + x * w, y: y0 + y * h) }
        func circle(_ cx: CGFloat, _ cy: CGFloat, _ rr: CGFloat) { p.addEllipse(in: CGRect(x: x0 + cx * w - rr, y: y0 + cy * h - rr, width: 2 * rr, height: 2 * rr)) }
        func box(_ a: CGFloat, _ b: CGFloat, _ c: CGFloat, _ d: CGFloat, _ rad: CGFloat = 2) {
            p.addRoundedRect(in: CGRect(x: x0 + a * w, y: y0 + b * h, width: (c - a) * w, height: (d - b) * h), cornerSize: CGSize(width: rad, height: rad))
        }
        func line(_ a: CGPoint, _ b: CGPoint) { p.move(to: a); p.addLine(to: b) }
        let u = min(w, h)
        switch kind {
        case .interface:
            // a desktop interface: the case, two gain knobs, two combo jacks, a little meter row
            box(0.04, 0.3, 0.96, 0.86, 3)
            line(P(0.04, 0.42), P(0.96, 0.42))
            circle(0.17, 0.64, u * 0.1); line(P(0.17, 0.64), P(0.21, 0.56))
            circle(0.36, 0.64, u * 0.1); line(P(0.36, 0.64), P(0.40, 0.56))
            circle(0.62, 0.64, u * 0.11); circle(0.62, 0.64, u * 0.04)
            circle(0.84, 0.64, u * 0.11); circle(0.84, 0.64, u * 0.04)
            for k in 0..<5 { box(0.5 + CGFloat(k) * 0.08, 0.33, 0.55 + CGFloat(k) * 0.08, 0.38, 0.5) }
        case .amp:
            // an amp head: the handle, the cabinet, the control panel with a row of knobs and a pilot
            p.move(to: P(0.36, 0.22)); p.addQuadCurve(to: P(0.64, 0.22), control: P(0.5, 0.02))
            box(0.04, 0.22, 0.96, 0.9, 3)
            box(0.1, 0.32, 0.9, 0.62, 1.5)
            for k in 0..<5 { circle(0.2 + CGFloat(k) * 0.13, 0.47, u * 0.06) }
            circle(0.84, 0.47, u * 0.035)
            line(P(0.1, 0.76), P(0.9, 0.76))
        case .reamp:
            // a small reamp box: two jacks and a ground-lift switch
            box(0.22, 0.36, 0.78, 0.84, 3)
            circle(0.36, 0.6, u * 0.09); circle(0.36, 0.6, u * 0.035)
            circle(0.64, 0.6, u * 0.09); circle(0.64, 0.6, u * 0.035)
            line(P(0.5, 0.48), P(0.5, 0.56))
        case .cab:
            // a closed-back cab: the box, the baffle, four speakers with their dust caps
            box(0.16, 0.06, 0.84, 0.96, 3)
            box(0.21, 0.12, 0.79, 0.9, 1.5)
            for (cx, cy) in [(0.37, 0.32), (0.63, 0.32), (0.37, 0.7), (0.63, 0.7)] as [(CGFloat, CGFloat)] {
                circle(cx, cy, u * 0.17); circle(cx, cy, u * 0.05)
            }
        case .terminals:
            // two binding posts on a plate, + and −
            box(0.18, 0.3, 0.82, 0.86, 2.5)
            circle(0.36, 0.58, u * 0.12); circle(0.36, 0.58, u * 0.05)
            circle(0.64, 0.58, u * 0.12); circle(0.64, 0.58, u * 0.05)
            line(P(0.32, 0.36), P(0.40, 0.36)); line(P(0.36, 0.32), P(0.36, 0.40))
            line(P(0.60, 0.36), P(0.68, 0.36))
        case .mic:
            // a dynamic mic on its side, aimed left at a speaker: grille, body, XLR end, a few grille lines
            box(0.12, 0.42, 0.32, 0.7, 6)
            for k in 1..<4 { line(P(0.12 + CGFloat(k) * 0.05, 0.43), P(0.12 + CGFloat(k) * 0.05, 0.69)) }
            p.move(to: P(0.32, 0.46)); p.addLine(to: P(0.8, 0.5)); p.addLine(to: P(0.8, 0.62)); p.addLine(to: P(0.32, 0.66))
            box(0.8, 0.48, 0.9, 0.64, 1)
            line(P(0.9, 0.56), P(0.98, 0.56))
        case .loadBox:
            // a load box: the case with cooling slots, a resistor drawn on its face
            box(0.1, 0.3, 0.9, 0.88, 3)
            for k in 0..<6 { line(P(0.2 + CGFloat(k) * 0.12, 0.36), P(0.2 + CGFloat(k) * 0.12, 0.46)) }
            p.move(to: P(0.18, 0.68))
            p.addLine(to: P(0.3, 0.68))
            for k in 0..<6 { p.addLine(to: P(0.33 + CGFloat(k) * 0.06, k % 2 == 0 ? 0.58 : 0.78)) }
            p.addLine(to: P(0.7, 0.68)); p.addLine(to: P(0.82, 0.68))
        case .pad:
            // two resistors in series and the tap point between them
            p.move(to: P(0.04, 0.6)); p.addLine(to: P(0.12, 0.6))
            for k in 0..<6 { p.addLine(to: P(0.15 + CGFloat(k) * 0.045, k % 2 == 0 ? 0.48 : 0.72)) }
            p.addLine(to: P(0.42, 0.6)); p.addLine(to: P(0.58, 0.6))
            for k in 0..<6 { p.addLine(to: P(0.61 + CGFloat(k) * 0.045, k % 2 == 0 ? 0.48 : 0.72)) }
            p.addLine(to: P(0.88, 0.6)); p.addLine(to: P(0.96, 0.6))
            circle(0.5, 0.6, u * 0.04); line(P(0.5, 0.6), P(0.5, 0.92))
        case .jack:
            // a quarter-inch jack: the barrel, the nut, the tip and sleeve lugs
            box(0.24, 0.44, 0.62, 0.74, 2)
            box(0.62, 0.48, 0.72, 0.7, 1)
            line(P(0.72, 0.59), P(0.86, 0.59))
            line(P(0.3, 0.74), P(0.3, 0.88)); line(P(0.5, 0.74), P(0.5, 0.88))
        }
        return p
    }
}

/// An arrow drawn in ink, for the line drawings.
struct InkArrow: View {
    var color: Color = Swell.tagInk
    var body: some View {
        Path { p in
            p.move(to: CGPoint(x: 2, y: 5)); p.addLine(to: CGPoint(x: 30, y: 5))
            p.move(to: CGPoint(x: 24, y: 1)); p.addLine(to: CGPoint(x: 30, y: 5)); p.addLine(to: CGPoint(x: 24, y: 9))
        }
        .stroke(color, style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
        .frame(width: 32, height: 10)
        .accessibilityHidden(true)
    }
}

/// `IR Capture --render-diagrams <dir>`: writes each diagram as a PNG, for the Quick start PDF and the website.
enum DiagramExport {
    @MainActor
    static func render(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for w in Wiring.allCases {
            let view = VStack(alignment: .leading, spacing: 8) {
                Text(w.title).font(.system(size: 14, weight: .semibold))
                WiringDiagram(wiring: w)
            }
            .padding(16).background(Color.white).environment(\.colorScheme, .light)
            let r = ImageRenderer(content: view)
            r.scale = 3
            if let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: dir.appendingPathComponent("wiring-\(w.rawValue).png"))
            }
        }
    }
}

// ------------------------------------------------------------------ Welcome (P0.4)
struct WelcomeSheet: View {
    @EnvironmentObject var m: AppModel
    @State private var page = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Engraved(["Welcome to \(Product.name)", "Wiring", "Output files"][page], size: 20)
                Spacer()
                HStack(spacing: 6) { ForEach(0..<3) { i in JewelLamp(colour: "amber", on: i == page, diameter: 14) } }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Page \(page + 1) of 3")
            }
            Group {
                if page == 0 { needs } else if page == 1 { wiring } else { gets }
            }
            .frame(maxWidth: .infinity, minHeight: 360, alignment: .topLeading)
            HStack {
                if page > 0 { Button("Back") { page -= 1 }.buttonStyle(KeyButtonStyle(key: "Back", size: 13)) }
                Spacer()
                if page < 2 { Button("Next") { page += 1 }.keyboardShortcut(.defaultAction).buttonStyle(KeyButtonStyle(key: "Next", lit: true, size: 13)) }
                else { Button("Start") { m.finishWelcome() }.keyboardShortcut(.defaultAction).buttonStyle(KeyButtonStyle(key: "Start", lit: true, size: 13)) }
            }
        }
        .onCrinkle(padding: 30)
        .frame(width: 740)
    }

    var needs: some View {
        VStack(alignment: .leading, spacing: 12) {
            Engraved("What you need")
            Checklist(items: [
                "A Mac with macOS 13 or later.",
                "An audio interface with at least 1 output and 1 input. With two or more inputs, several mics can be recorded at once.",
                "Your mic(s), amp, cab and cables.",
                "Optional: a reference (a load box with a line out, or a reference tap). For NAM captures: a reamp box, and a load box for amp-only models.",
            ])
            Engraved("Microphone access").padding(.top, 6)
            Note("macOS requires permission before any app can record from an interface, including an interface with no microphones connected. \(Product.name) records the mic and reference inputs only while the test sweeps are played.", color: .primary)
            HStack {
                switch m.micStatus {
                case .authorized:
                    StatusLine(text: "Allowed", color: goodColor)
                case .notDetermined:
                    Button("Allow recording…") { m.requestMicrophone() }.buttonStyle(KeyButtonStyle(key: "Allow recording…", size: 13))
                default:
                    StatusLine(text: "Recording is turned off for \(Product.name).", color: badColor)
                    Button("Open Privacy & Security") { m.openPrivacySettings() }.buttonStyle(KeyButtonStyle(key: "Open Privacy & Security"))
                }
            }
        }
    }

    var wiring: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Wiring.hookups, id: \.self) { w in
                    VStack(alignment: .leading, spacing: 8) {
                        Engraved(w.title, size: 12)
                        WiringDiagram(wiring: w, compact: true)
                    }
                    .onPaper()
                }
            }
        }
        .frame(height: 360)
    }

    var gets: some View {
        VStack(alignment: .leading, spacing: 12) {
            Checklist(items: [
                "Cab IR: one finished file per mic, at the top of the capture folder (48 kHz, 24-bit, 500 ms). Compatible with IR loaders, DAW plug-ins and modelers. All-sample-rate, Strymon Iridium, minimum-phase and two-mic mix versions are available as options. Files can be re-exported later without a new recording.",
                "A measurement report: levels, room noise, speaker distortion and mic timing, with corrective steps where required.",
                "Amp (NAM): aligned and verified files for upload to TONE3000. The model is trained on TONE3000.",
            ])
            Note("The four steps are listed in Help › Quick Start. To send system details to support, use Help › Contact Support.")
        }
    }
}

// ------------------------------------------------------------------ Help pages (P0.2, P0.6, section 6)
struct HelpSheet: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.dismiss) private var dismiss
    @State var page: HelpPage
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                KeyChoice(selection: $page, options: HelpPage.allCases.map { ($0, $0.title) }, size: 11)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction).buttonStyle(KeyButtonStyle(key: "Done", size: 12))
            }.padding(.bottom, 14)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch page {
                    case .quickStart: QuickStartPage()
                    case .wiring: ForEach(Wiring.hookups, id: \.self) { w in Text(w.title).font(.swellBody(17, semibold: true)); WiringDiagram(wiring: w) }
                    case .reference: ReferencePage()
                    case .troubleshooting: TroubleshootingPage()
                    }
                }
                .font(.swellBody(14))
                .padding(26).onPaper(padding: 0)
                .padding(4)
            }
            HStack {
                Button("Contact Support…") { m.contactSupport() }.buttonStyle(KeyButtonStyle(key: "Contact Support…"))
                Button("Show Log File") { Log.reveal() }.buttonStyle(KeyButtonStyle(key: "Show Log File"))
                Spacer()
                Engraved("\(Product.name) \(Product.fullVersion)", size: 10, dim: true)
            }.padding(.top, 14)
        }
        .onCrinkle(padding: 22)
        .frame(width: 780, height: 660)
    }
}

struct QuickStartPage: View {
    var body: some View {
        Text("Your first cab IR").font(.swellBody(20, semibold: true))
        Checklist(items: [
            "Connect. Interface output → amp FX return or clean power amp → cab. Connect the mics on the cab to the interface. Set the amp master low. Mute the studio monitors.",
            "Set levels. Click Check levels. Room noise is measured for 2 seconds, a clean sweep level is set, and short sweeps are looped. Adjust each preamp until the meter shows OK.",
            "Capture. Enter a name (e.g. 412_V30_PosA) and click Capture. Duration: about 45 seconds.",
            "Results. Load the file at the top of the capture folder (one per mic) into your IR loader, DAW plug-in or modeler.",
        ])
        Text("A NAM amp model").font(.swellBody(20, semibold: true)).padding(.top, 8)
        Checklist(items: [
            "Download T3K-sweep-v3.wav from tone3000.com/capture, then click Find it in Downloads in the Amp (NAM) tab.",
            "Interface output → reamp box → amp input. Amp → load box. Load box line out → interface input.",
            "Click Check levels, then Record (3 minutes 12 seconds). Do not adjust any controls during the recording.",
            "Upload the WAV files at tone3000.com/capture. TONE3000 trains the model and provides a .nam file.",
        ])
        // (11-12) what the old panels said beside their controls, now that the controls are rack units
        Text("The set-up units").font(.swellBody(20, semibold: true)).padding(.top, 8)
        Checklist(items: [
            "INTERFACE: click SELECT for the list of interfaces, or turn it with the scroll wheel. OUT TO AMP: the interface output connected to the amp. AUDIO SETUP opens Audio MIDI Setup. If inputs and outputs are on two devices, combine them into an aggregate device there.",
            "REFERENCE: NONE, LOAD BOX (a load box line out) or TAP OR PAD (a reference tap or a 20 dB pad across the speaker terminals). Set the input it is connected to to REF on the inputs unit. See Help › The reference tap.",
            "CAPTURE NAME: cab and mic position, e.g. 412_V30_PosA. All file names start with this name. Click a line on the card to type on it. NOTES are saved in report.json.",
            "FILES: UNIVERSAL makes one file per mic at the top of the capture folder (48 kHz, 24-bit, 500 ms). Use it for devices not listed (Quad Cortex, ToneX, Fractal, Kemper Cab Maker). These manufacturers do not publish a fixed format. Conversion is done by their software on import. ALL RATES makes 44.1, 48, 88.2 and 96 kHz files at 500 ms and 200 ms. IRIDIUM makes the Strymon Iridium format.",
            "ALSO MAKE: MIN PHASE makes minimum-phase versions of the close mics. MIXES makes two-mic blends. A mic named Room or Amb (Room L, Ambient) is treated as a room mic: it has no minimum-phase version and is mixed with close mics at 80/20 and 60/40.",
            "The sweep and file options units are under smoked covers. Click a cover to lift it. Click its hinges to shut it.",
            "RATE: AUTO records at the highest rate of the interface, up to 96 kHz. All other rates are made from this capture. The interface is reset to its previous rate afterwards.",
            "LEVEL: AUTO starts at −18 dBFS. The level is raised in steps while speaker distortion stays low, and reduced if distortion increases.",
            "SWEEPS, LENGTH, GAP, WARM-UP: set the gap longer than the room reverb tail. The warm-up sweeps are discarded. Each doubling of the sweep count lowers the noise floor by about 3 dB.",
            "POLARITY: POSITIVE makes each IR with its main peak positive, as in commercial IR packs, so mics blend without cancellation. An inverted mic is flipped, and the flip is listed in the results. AS RECORDED keeps the polarity of each recording.",
            "CUSTOM: ON adds the files chosen on the keys, in More formats › Custom. KEEP TIMING: all mics are trimmed by the same amount and share one gain, so the blend matches the original mics. EACH MIC: each file starts at its own first arrival and is normalized separately. FULL ms: the length of the FULL files.",
            "PRINT, on the response plotter: print the response chart, or save it as a PDF in the capture folder. The style (plotter colours, or black and white) and the curves (all mics, each mic on its own page, the mixes) are chosen in the same menu.",
            "Status: the line on the shelf's display. During the level check, the noise measurement, the sweep level being set and the input that most needs a change are shown there. During the capture and processing, the step in progress is shown. NOT READY: the reason is marked with a red cross on the pre-flight. FAULT: the lamp is red, and the message is typed in red in the TROUBLE box at the foot of the pre-flight. Hold the pointer over the display for the whole sentence.",
        ])
        Text("The DAW route").font(.swellBody(20, semibold: true)).padding(.top, 8)
        Note("IMPORT DAW, on the connect unit, opens the DAW route: the test signal is played from a DAW (Logic, Reaper, Ableton, Pro Tools, GarageBand), the mics are recorded there, and the IRs are made from the exported files. ‹ RECORD HERE returns to recording with the app. The steps apply to any DAW. Menu names are from Logic.", color: .primary)
        Checklist(items: [
            "TEST SIGNAL: set RATE to the sample rate of the DAW project and LEVEL to the sweep peak. SWEEPS, LENGTH, GAP and WARM-UP as on the sweep unit. SAVE SIGNAL saves the sweeps as a WAV file, with a .json file of the settings and a How to use.txt file. LOAD SIGNAL sets the controls from a saved .json file. Use the same settings when the files are added.",
            "In the DAW: set the project to the test signal's rate. Drag the sweep WAV onto a new audio track at the start (bar 1 in Logic). Route that track only to the interface output connected to the amp FX return or a clean power amp (not the guitar input). Mute the studio monitors. Otherwise the room mic records them.",
            "Create one audio track per mic, and one for the reference if used. Name each track after its mic (SM57, R121, Room). Name the reference track Ref. The exported files use these names. Record-enable all tracks. Turn input monitoring off. Use no plug-ins.",
            "Play the sweep track and watch the meters. Set each mic preamp so the sweep peaks at about −6 dBFS. No track may clip. Record one full pass. Keep the room quiet. Do not move the mics.",
            "Export every track as a WAV file (in Logic: File › Export › All Tracks as Audio Files), 24-bit or 32-bit float, at the project rate, with Normalize off and faders at 0 dB.",
            "TRACKS: ADD FILES adds the exported WAV files, or drop them on the track sheet. One line per track (a stereo file takes two lines). A file named after the sweep is set to OFF. Set each line's switch to MIC, OFF or REF. Only one track is the reference. Click a mic's name on the sheet to change it; it is used in the file names. Right-click a line to remove its file. CLEAR takes every file off the sheet.",
            "Then the capture card, the files and the file options as in the record route, and MAKE IRS. Anything missing before MAKE IRS can be used is shown on the display. A problem with a file is shown in a message window.",
        ])
        Text("Re-export").font(.swellBody(20, semibold: true)).padding(.top, 8)
        Note("RE-EXPORT OLD, on the files unit, and RE-EXPORT, on the results unit, make the files of a past capture again from its raw take, with the files and file options chosen now. No new recording is made. The previously generated files are moved to the Trash. The raw take and the report history are kept. The name, notes and folder of the past capture are typed on its card. CHOOSE selects another capture folder (it contains a Raw take folder). CANCEL leaves the re-export without changes. Captures made before version 1.0 have no raw take and cannot be re-exported.", color: .primary)
    }
}

struct ReferencePage: View {
    var body: some View {
        Text("What the reference does").font(.swellBody(20, semibold: true))
        Note("A reference is a copy of the voltage across the speaker terminals. It is recorded on a separate line input during the sweep. Each mic recording is divided by the reference. The resulting IR contains the speaker, mic and room only, independent of the amp. Without a reference, the IR also contains the power amp response. With a tube amp, this adds about 5 dB of the speaker impedance peak around resonance. Most commercial IRs are made this way. The IR then includes the response of that amp.", color: .primary)
        Note("NAM: an amp-only model already contains the impedance peak, because the load box line out includes it. Use such a model with IRs made with a reference. Otherwise the peak is applied twice.", color: .primary)
        Text("Three ways to get one").font(.swellBody(16, semibold: true)).padding(.top, 4)
        Checklist(items: [
            "None. Acceptable for a first capture.",
            "A load box or attenuator with a speaker-through and a line out, connected between the amp and the cab. The line out is a tap of the amp output voltage. Connect it to a line input with one cable. Turn off any cab simulation or EQ on that output. Set any attenuation to bypass for the capture.",
            "A reference tap or a home-made pad across the speaker terminals (below).",
        ])
        Text("Build a 20 dB pad").font(.swellBody(16, semibold: true)).padding(.top, 4)
        WiringDiagram(wiring: .pad, compact: true)
        Checklist(items: [
            "Parts: one 10 kΩ resistor (½ W, metal film), one 1.1 kΩ resistor (¼ W or more), a ¼\" jack, two clips or a speaker-cable splitter, and a small box.",
            "Connect the 10 kΩ from the speaker's + terminal to a tap point, and the 1.1 kΩ from the tap point to the speaker's − terminal. Voltage division: about 10:1 (−19 dB).",
            "Wire the tap point to the jack tip and the speaker − terminal to the jack sleeve. Connect the jack to a line input, not a mic or instrument input. Turn phantom power off.",
            "Keep the speaker connected at all times. Connect the pad in parallel with the speaker, never in place of it. A tube amp must always have a load.",
        ])
        Note("Bridged speaker outputs (many class-D and some solid-state amps) have no grounded terminal. A plain pad shorts such an output through the interface ground. Use an isolated tap (transformer) or a balanced input with both legs padded. The same fix applies to hum on the tap.", color: badColor)
    }
}

struct TroubleshootingPage: View {
    let items: [(String, String)] = [
        ("The app does not open", "Signed releases open with a double-click. Pre-release builds require one additional step on first launch: System Settings › Privacy & Security, scroll down, click Open Anyway."),
        ("No interface found", "Connect the interface and switch it on. It is detected automatically. The interface must have both inputs and outputs. If inputs and outputs are on two devices, combine them into an aggregate device in Audio MIDI Setup."),
        ("No signal on an input", "Check the cable. Check that the preamp gain is above zero. Turn on phantom power for condenser mics. Set the input to Mic in Connect."),
        ("CLIP", "Turn that preamp down until the meter shows OK. If all inputs clip, turn the amp master down."),
        ("Distortion is orange or red", "Speaker drive is too high for a clean IR. Turn the amp master down. An IR is linear. Higher volume does not improve it."),
        ("Noisy input", "Noise source in the room: refrigerator, air conditioning, fans, a computer, or the studio monitors. Reduce the noise and check levels again."),
        ("Hum on the reference tap", "Use an isolated tap or a balanced input, or connect the amp and the interface to the same power strip."),
        ("The IR sounds thin or dull", "Common causes: mic placement (move toward or away from the cone center), studio monitors not muted, or the sweep connected to the guitar input instead of the FX return."),
        ("Audio dropped out", "Another app interrupted the interface. Quit browsers, video calls and other audio apps, then record again. If dropouts continue, increase the interface buffer size."),
        ("Sample rate did not switch", "In Audio MIDI Setup (or the interface control panel), set the interface to the requested rate, then try again."),
        ("Microphone permission", "System Settings › Privacy & Security › Microphone: turn on \(Product.name), then quit and reopen the app."),
    ]
    var body: some View {
        Text("Troubleshooting").font(.swellBody(20, semibold: true))
        ForEach(items.indices, id: \.self) { i in
            let t = items[i]
            VStack(alignment: .leading, spacing: 3) {
                Text(t.0).font(.swellBody(14, semibold: true))
                Note(t.1, color: .primary)
                if t.1.contains("Audio MIDI Setup") { Button("Open Audio MIDI Setup") { CoreAudioHelper.openAudioMIDISetup() }.buttonStyle(KeyButtonStyle(key: "Open Audio MIDI Setup")).controlSize(.small) }
            }
        }
    }
}
#endif
