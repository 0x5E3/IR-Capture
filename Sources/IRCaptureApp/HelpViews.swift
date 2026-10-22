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
    case cabNoRef, cabRef, namAmp, namFull
    var title: String {
        switch self {
        case .cabNoRef: return "Cab IR, no reference"
        case .cabRef: return "Cab IR with a reference"
        case .namAmp: return "NAM: amp only"
        case .namFull: return "NAM: full chain"
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
        }
    }
    var footnote: String {
        switch self {
        case .cabNoRef, .cabRef: return "Studio monitors muted. Amp master low to start."
        case .namAmp: return "Gates, reverb, delay and loop effects off."
        case .namFull: return "Gates, reverb, delay and loop effects off. Studio monitors muted."
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
                Text(["Welcome to \(Product.name)", "How it's wired", "What you'll get"][page]).font(.title.weight(.semibold))
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
                "An audio interface with at least 1 output and 1 input. Two or more inputs let you record several mics at once.",
                "Your mic(s), amp, cab and cables.",
                "Optional: a reference (a load box with a line out, or a reference tap). For NAM captures: a reamp box, and a load box for amp-only models.",
            ])
            Divider()
            Text("MICROPHONE ACCESS").font(.caption.weight(.semibold)).kerning(0.8).foregroundStyle(.secondary)
            Note("macOS asks before any app can record from an interface, even one with no microphones plugged in. \(Product.name) records your mics and the reference while it plays the test sweeps, and nothing else.", color: .primary)
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
        VStack(alignment: .leading, spacing: 12) {
            Note("For a cab IR the test sweep goes into the amp's FX return (or a clean power amp), not the guitar input. Mics go into the interface. Each step in the app shows the right picture again.", color: .primary)
            WiringDiagram(wiring: .cabNoRef, compact: true)
            WiringDiagram(wiring: .namAmp, compact: true)
            Button("All wiring pictures…") { m.helpPage = .wiring }.buttonStyle(.link)
        }
    }

    var gets: some View {
        VStack(alignment: .leading, spacing: 12) {
            Checklist(items: [
                "Cab IR: one finished file per mic, at the top of the capture folder (48 kHz, 24-bit, 500 ms). It loads in any IR loader, DAW plug-in or modeler. Helix, Iridium and every-rate versions are a tick away, and you can re-export later without recording again.",
                "A report of what the app measured: levels, room noise, speaker distortion and mic timing, with plain advice if anything needs fixing.",
                "Amp (NAM): files lined up and checked, ready to upload to TONE3000, which trains the model for you.",
            ])
            Note("Help › Quick Start has the four steps any time; Help › Contact Support sends your details to us.")
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
                    case .wiring: ForEach(Wiring.allCases, id: \.self) { w in Text(w.title).font(.headline); WiringDiagram(wiring: w) }
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
            "Connect. Interface output → the amp's FX return or a clean power amp → the cab. Mics on the cab into the interface. Amp master low, studio monitors muted.",
            "Set levels. Click Check levels. The app listens to the room for 2 seconds, finds a clean sweep level, then loops short sweeps. Turn each preamp until it says OK.",
            "Capture. Name it (e.g. 412_V30_PosA) and click Capture. It takes about 45 seconds.",
            "Results. Load the file at the top of the capture folder (one per mic) into your IR loader, DAW plug-in or modeler.",
        ])
        Text("A NAM amp model").font(.title2.weight(.semibold)).padding(.top, 8)
        Checklist(items: [
            "Download T3K-sweep-v3.wav from tone3000.com/capture, then click Find it in Downloads in the Amp (NAM) tab.",
            "Interface output → reamp box → amp input. Amp → load box; its line out → an interface input.",
            "Check levels, then Record (3 minutes 12 seconds). Don't touch any knobs while it runs.",
            "Upload the WAV files at tone3000.com/capture; it trains the model and gives you a .nam file.",
        ])
    }
}

struct ReferencePage: View {
    var body: some View {
        Text("What the reference does").font(.title2.weight(.semibold))
        Note("A reference is a copy of the voltage across the speaker terminals, recorded on its own line input while the sweep plays. The app divides each mic by it, so the IR is the speaker, mic and room only, whatever amp drives it. Without one, the IR also includes the power amp, and with a tube amp that adds about 5 dB of the speaker's impedance bump around its resonance. That isn't wrong, and most commercial IRs are made that way; it just means the IR carries that amp's character.", color: .primary)
        Note("It also matters for NAM: an amp-only model already has the impedance bump in it (the load box's line out carries it), so pair it with IRs made with a reference, or the bump is counted twice.", color: .primary)
        Text("Three ways to get one").font(.title3.weight(.semibold)).padding(.top, 4)
        Checklist(items: [
            "None. Skip it. Fine for a first capture.",
            "A load box or attenuator with a speaker-through and a line out (the kind that sits between the amp and the cab). Its line out is a tap of the amp's output voltage: one cable to a line input. Turn off any cab simulation or EQ on that output, and set any attenuation to bypass for the capture.",
            "A reference tap or a home-made pad across the speaker terminals (below).",
        ])
        Text("Build a 20 dB pad").font(.title3.weight(.semibold)).padding(.top, 4)
        WiringDiagram(wiring: .cabRef, compact: true)
        Checklist(items: [
            "Parts: one 10 kΩ resistor (½ W, metal film), one 1.1 kΩ resistor (¼ W or more), a ¼\" jack, two clips or a speaker-cable splitter, and a small box.",
            "Connect the 10 kΩ from the speaker's + terminal to a tap point, and the 1.1 kΩ from the tap point to the speaker's − terminal. That divides the voltage by about 10 (−19 dB).",
            "Wire the tap point to the jack's tip and the speaker's − terminal to its sleeve. Plug it into a line input (not a mic or instrument input), with phantom power off.",
            "Keep the speaker connected the whole time: the pad goes alongside it, never instead of it. A tube amp must always have its load.",
        ])
        Note("If the amp's speaker output is bridged (many class-D and some solid-state amps: neither terminal is ground), a plain pad will short it through the interface's ground. Use an isolated tap (a transformer) or a balanced input with both legs padded. If the tap brings in hum, the cure is the same.", color: badColor)
    }
}

struct TroubleshootingPage: View {
    let items: [(String, String)] = [
        ("The app won't open", "Signed releases open with a double-click. A pre-release build needs one extra step the first time: System Settings › Privacy & Security, scroll down, Open Anyway."),
        ("No interface found", "Plug it in and switch it on; it appears by itself. It has to have both inputs and outputs. If yours are on two devices, combine them into an aggregate device in Audio MIDI Setup."),
        ("No signal on an input", "Check the cable and that the preamp gain isn't at zero. Phantom power on for condenser mics. Mark the input as Mic in Connect."),
        ("CLIP", "Turn that preamp down until it says OK. If every input clips, turn the amp's master down."),
        ("Distortion is orange or red", "The speaker is being pushed too hard for a clean IR. Turn the amp's master down. An IR is linear, so more volume gains nothing."),
        ("Noisy input", "Something in the room: fridge, air conditioning, fans, a computer, or the studio monitors. Quieten it and check levels again."),
        ("Hum on the reference tap", "Use an isolated tap, a balanced input, or plug the amp and the interface into the same power strip."),
        ("The IR sounds thin or dull", "Usually mic placement (move toward or away from the cone's center), studio monitors left on, or the sweep going into the guitar input instead of the FX return."),
        ("Audio dropped out", "Another app interrupted the interface. Quit browsers, video calls and other audio apps, then record again. If it keeps happening, raise the interface's buffer size."),
        ("Sample rate wouldn't switch", "Set the interface to the rate the app asks for in Audio MIDI Setup (or its own control panel), then try again."),
        ("Microphone permission", "System Settings › Privacy & Security › Microphone: turn on \(Product.name), then quit and reopen it."),
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
