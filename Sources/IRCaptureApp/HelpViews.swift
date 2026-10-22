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
    func color(_ k: DiagramNode.Kind) -> Color {
        switch k {
        case .interface: return lamp
        case .gear: return Color(red: 0.45, green: 0.5, blue: 0.58)
        case .speaker: return Color(red: 0.36, green: 0.45, blue: 0.36)
        case .mic: return Color(red: 0.44, green: 0.64, blue: 0.84)
        case .tap: return Color(red: 0.61, green: 0.45, blue: 0.7)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            ForEach(Array(wiring.rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.offset) { i, n in
                        if i > 0 {
                            VStack(spacing: 1) {
                                Text(n.via ?? "").font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
                                Image(systemName: "arrow.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                            }.frame(width: compact ? 60 : 78)
                        }
                        VStack(spacing: 2) {
                            Text(n.title).font(.system(size: compact ? 11 : 12, weight: .semibold)).multilineTextAlignment(.center)
                            if !n.sub.isEmpty { Text(n.sub).font(.system(size: compact ? 9 : 10)).foregroundStyle(.secondary).multilineTextAlignment(.center) }
                        }
                        .padding(.horizontal, 6).padding(.vertical, compact ? 5 : 8)
                        .frame(width: compact ? 120 : 140)
                        .background(RoundedRectangle(cornerRadius: 7).fill(color(n.kind).opacity(0.16)))
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(color(n.kind), lineWidth: 1.5))
                    }
                }
            }
            Text(wiring.footnote).font(.caption).foregroundStyle(.secondary)
        }
        .padding(compact ? 8 : 12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.05)))
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
                Text(["Welcome to \(Product.name)", "Wiring", "Output files"][page]).font(.title.weight(.semibold))
                Spacer()
                HStack(spacing: 6) { ForEach(0..<3) { i in Circle().fill(i == page ? lamp : Color.secondary.opacity(0.3)).frame(width: 8, height: 8) } }
            }
            Group {
                if page == 0 { needs } else if page == 1 { wiring } else { gets }
            }
            .frame(maxWidth: .infinity, minHeight: 360, alignment: .topLeading)
            HStack {
                if page > 0 { Button("Back") { page -= 1 } }
                Spacer()
                if page < 2 { Button("Next") { page += 1 }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).tint(lamp) }
                else { Button("Start") { m.finishWelcome() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).tint(lamp) }
            }
        }
        .padding(28).frame(width: 720)
    }

    var needs: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("WHAT YOU NEED").font(.caption.weight(.semibold)).kerning(0.8).foregroundStyle(.secondary)
            Checklist(items: [
                "A Mac with macOS 13 or later.",
                "An audio interface with at least 1 output and 1 input. With two or more inputs, several mics can be recorded at once.",
                "Your mic(s), amp, cab and cables.",
                "Optional: a reference (a load box with a line out, or a reference tap). For NAM captures: a reamp box, and a load box for amp-only models.",
            ])
            Divider()
            Text("MICROPHONE ACCESS").font(.caption.weight(.semibold)).kerning(0.8).foregroundStyle(.secondary)
            Note("macOS requires permission before any app can record from an interface, including an interface with no microphones connected. \(Product.name) records the mic and reference inputs only while the test sweeps are played.", color: .primary)
            HStack {
                switch m.micStatus {
                case .authorized:
                    Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(goodColor)
                case .notDetermined:
                    Button("Allow recording…") { m.requestMicrophone() }.buttonStyle(.borderedProminent).tint(lamp)
                default:
                    Note("Recording is turned off for \(Product.name).", color: badColor)
                    Button("Open Privacy & Security") { m.openPrivacySettings() }
                }
            }
        }
    }

    var wiring: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Wiring.hookups, id: \.self) { w in
                    Text(w.title).font(.headline)
                    WiringDiagram(wiring: w, compact: true)
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
                Picker("", selection: $page) { ForEach(HelpPage.allCases) { Text($0.title).tag($0) } }
                    .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 520)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }.padding(16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch page {
                    case .quickStart: QuickStartPage()
                    case .wiring: ForEach(Wiring.hookups, id: \.self) { w in Text(w.title).font(.headline); WiringDiagram(wiring: w) }
                    case .reference: ReferencePage()
                    case .troubleshooting: TroubleshootingPage()
                    }
                }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Button("Contact Support…") { m.contactSupport() }
                Button("Show Log File") { Log.reveal() }
                Spacer()
                Text("\(Product.name) \(Product.fullVersion)").font(.caption).foregroundStyle(.secondary)
            }.padding(12)
        }
        .frame(width: 760, height: 640)
    }
}

struct QuickStartPage: View {
    var body: some View {
        Text("Your first cab IR").font(.title2.weight(.semibold))
        Checklist(items: [
            "Connect. Interface output → amp FX return or clean power amp → cab. Connect the mics on the cab to the interface. Set the amp master low. Mute the studio monitors.",
            "Set levels. Click Check levels. Room noise is measured for 2 seconds, a clean sweep level is set, and short sweeps are looped. Adjust each preamp until the meter shows OK.",
            "Capture. Enter a name (e.g. 412_V30_PosA) and click Capture. Duration: about 45 seconds.",
            "Results. Load the file at the top of the capture folder (one per mic) into your IR loader, DAW plug-in or modeler.",
        ])
        Text("A NAM amp model").font(.title2.weight(.semibold)).padding(.top, 8)
        Checklist(items: [
            "Download T3K-sweep-v3.wav from tone3000.com/capture, then click Find it in Downloads in the Amp (NAM) tab.",
            "Interface output → reamp box → amp input. Amp → load box. Load box line out → interface input.",
            "Click Check levels, then Record (3 minutes 12 seconds). Do not adjust any controls during the recording.",
            "Upload the WAV files at tone3000.com/capture. TONE3000 trains the model and provides a .nam file.",
        ])
    }
}

struct ReferencePage: View {
    var body: some View {
        Text("What the reference does").font(.title2.weight(.semibold))
        Note("A reference is a copy of the voltage across the speaker terminals. It is recorded on a separate line input during the sweep. Each mic recording is divided by the reference. The resulting IR contains the speaker, mic and room only, independent of the amp. Without a reference, the IR also contains the power amp response. With a tube amp, this adds about 5 dB of the speaker impedance peak around resonance. Most commercial IRs are made this way. The IR then includes the response of that amp.", color: .primary)
        Note("NAM: an amp-only model already contains the impedance peak, because the load box line out includes it. Use such a model with IRs made with a reference. Otherwise the peak is applied twice.", color: .primary)
        Text("Three ways to get one").font(.title3.weight(.semibold)).padding(.top, 4)
        Checklist(items: [
            "None. Acceptable for a first capture.",
            "A load box or attenuator with a speaker-through and a line out, connected between the amp and the cab. The line out is a tap of the amp output voltage. Connect it to a line input with one cable. Turn off any cab simulation or EQ on that output. Set any attenuation to bypass for the capture.",
            "A reference tap or a home-made pad across the speaker terminals (below).",
        ])
        Text("Build a 20 dB pad").font(.title3.weight(.semibold)).padding(.top, 4)
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
        Text("Troubleshooting").font(.title2.weight(.semibold))
        ForEach(items.indices, id: \.self) { i in
            let t = items[i]
            VStack(alignment: .leading, spacing: 3) {
                Text(t.0).bold()
                Note(t.1, color: .primary)
                if t.1.contains("Audio MIDI Setup") { Button("Open Audio MIDI Setup") { CoreAudioHelper.openAudioMIDISetup() }.controlSize(.small) }
            }
        }
    }
}
#endif
