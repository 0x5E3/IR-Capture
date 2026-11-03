#if os(macOS)
import SwiftUI
import IRCaptureCore
import UniformTypeIdentifiers

let lamp = Color(red: 0.91, green: 0.59, blue: 0.18)
let goodColor = Color(red: 0.25, green: 0.62, blue: 0.38)
let warnColor = Color(red: 0.85, green: 0.6, blue: 0.1)
let badColor = Color(red: 0.82, green: 0.25, blue: 0.2)
let micColors: [Color] = [Color(red: 0.92, green: 0.6, blue: 0.24), Color(red: 0.44, green: 0.64, blue: 0.84),
                          Color(red: 0.61, green: 0.8, blue: 0.35), Color(red: 0.81, green: 0.55, blue: 0.75),
                          Color(red: 0.36, green: 0.76, blue: 0.76), Color(red: 0.79, green: 0.72, blue: 0.42)]

@main
struct IRCaptureApp: App {
    @StateObject private var model = AppModel()
    init() { SwellKit.registerFonts() }
    var body: some Scene {
        WindowGroup(Product.name) {
            ContentView().environmentObject(model)
                .frame(minWidth: 780, minHeight: 640)
        }
        .defaultSize(width: 920, height: 960)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appInfo) {
                Button("About \(Product.name)") { Support.showAbout() }
            }
            CommandGroup(replacing: .help) {
                Button("Quick Start") { model.helpPage = .quickStart }
                Button("Wiring") { model.helpPage = .wiring }
                Button("The Reference Tap") { model.helpPage = .reference }
                Button("Troubleshooting") { model.helpPage = .troubleshooting }
                Divider()
                Button("Welcome Screen") { model.showWelcome = true }
                Divider()
                Button("Contact Support…") { model.contactSupport() }
                Button("Show Log File") { Log.reveal() }
                Button("Check for Updates…") { NSWorkspace.shared.open(Product.updatesPage) }
            }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        VStack(spacing: 0) {
            Shelf()
            StageOpening {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            Text(m.job == .cab ? "Record the speaker cab's impulse response." : "Record the amp for a NAM model, trained at TONE3000.")
                                .font(.swellBody(14, semibold: true)).onPaper(padding: 9, fill: false)
                            if m.job == .nam {
                                NAMJob()
                                if let r = m.namResult { NAMResultsView(r: r).id("namresults") }
                            } else {
                                CabJob()
                                if let r = m.result { ResultsView(r: r).id("results") }
                            }
                        }
                        .padding(22).frame(maxWidth: 900, alignment: .leading).frame(maxWidth: .infinity)
                    }
                    .onChange(of: m.result?.folder) { _ in withAnimation { proxy.scrollTo("results", anchor: .top) } }
                    .onChange(of: m.namResult?.folder) { _ in withAnimation { proxy.scrollTo("namresults", anchor: .top) } }
                }
            }
            .padding(.horizontal, 24).padding(.bottom, 22)
        }
        .background(WorkshopWall())
        .workshopDefaults()
        .sheet(isPresented: $m.showWelcome) { WelcomeSheet().environmentObject(m).workshopDefaults(.panel) }
        .sheet(item: $m.helpPage) { p in HelpSheet(page: p).environmentObject(m).workshopDefaults(.panel) }
        .sheet(isPresented: Binding(get: { m.reexportFolder != nil }, set: { if !$0 { m.reexportFolder = nil } })) {
            ReexportSheet().environmentObject(m).workshopDefaults(.panel)
        }
        .onAppear { runAutomation() }
    }

    /// CI hooks: process the simulated recordings, render the diagrams, or open a given view.
    private func runAutomation() {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "--demo"), i + 1 < args.count {
            // `IR Capture --demo <sim_out>` processes the simulated Logic recordings through Import DAW recordings.
            m.job = .cab; m.cabImport = true
            let dir = URL(fileURLWithPath: args[i + 1])
            m.outputFolder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("IRCaptureDemo")
            m.captureName = "demo"
            m.targets = ["universal", "everything", "iridium", "minphase", "mixes"]
            m.customOn = false
            m.keepPolarity = false
            m.addLogicFiles(["logic_close", "logic_room", "logic_ref"].map { dir.appendingPathComponent($0 + ".wav") })
            for c in m.logicChannels where c.role == .mic {
                if let k = m.logicChannels.firstIndex(where: { $0.id == c.id }) {
                    m.logicChannels[k].name = c.name.contains("close") ? "Close" : "Room"
                }
            }
            m.processLogic()
        } else if let i = args.firstIndex(of: "--nam-demo"), i + 1 < args.count {
            m.job = .nam
            m.namMode = "logic"
            let dir = URL(fileURLWithPath: args[i + 1])
            m.outputFolder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("IRCaptureDemo")
            m.namName = "namdemo"
            m.namKind = .full
            m.addNAMFiles(["Suhr", "SM57", "Room96"].map { dir.appendingPathComponent($0 + ".wav") })
            for k in m.namInputs.indices where m.namInputs[k].name == "Room96" { m.namInputs[k].name = "Room" }
            m.prepareNAM()
        } else if let i = args.firstIndex(of: "--nam-direct-demo"), i + 1 < args.count {
            m.runNAMDirectDemo(URL(fileURLWithPath: args[i + 1]))
        } else if let i = args.firstIndex(of: "--render-diagrams"), i + 1 < args.count {
            DiagramExport.render(to: URL(fileURLWithPath: args[i + 1]))
            NSApp.terminate(nil)
        } else if let i = args.firstIndex(of: "--render-gear"), i + 1 < args.count {
            GearPreview.render(to: URL(fileURLWithPath: args[i + 1]).appendingPathComponent("screenshot-gear.png"))
            NSApp.terminate(nil)
        } else if let i = args.firstIndex(of: "--help-page"), i + 1 < args.count {
            m.helpPage = HelpPage(rawValue: args[i + 1])
        } else if args.contains("--welcome") {
            m.showWelcome = true
        } else if args.contains("--nam-tab") {
            m.job = .nam
        } else if args.contains("--logic-tab") {
            m.job = .cab; m.cabImport = true
        } else if args.contains("--cab-tab") {
            m.job = .cab; m.cabImport = false
        }
    }
}

/// `IR Capture --render-gear <dir>`: the meters, nixies, keys and lamps with sample readings, as screenshot-gear.png
/// (CI attaches it to the release; these pieces only appear during a level check or a capture).
enum GearPreview {
    @MainActor
    static func render(to file: URL) {
        let view = VStack(alignment: .leading, spacing: 18) {
            MeterBridge {
                MeterModule(label: "SM57", vu: 0, dbfs: "−6.0 dBFS", clipped: false, advice: ("OK", goodColor)) {
                    HStack(spacing: 6) { Pill(text: "H2 −52", color: goodColor); Pill(text: "H3 −47", color: goodColor) }
                }
                MeterModule(label: "R121", vu: -9, dbfs: "−15.0 dBFS", clipped: false, advice: ("Turn up 9 dB", warnColor)) { EmptyView() }
                MeterModule(label: "Room", vu: 4, dbfs: "−0.1 dBFS", clipped: true, advice: ("CLIP: turn down", badColor)) { EmptyView() }
                MeterModule(label: "Reference", vu: nil, dbfs: "−72.0 dBFS", clipped: false, advice: ("No signal: check cable", badColor)) { EmptyView() }
            }
            HStack(spacing: 18) {
                VStack(spacing: 3) { NixieReadout(value: 45); Engraved("Seconds left", size: 9, dim: true) }
                Button("Capture") {}.buttonStyle(KeyButtonStyle(lit: true, size: 16, big: true))
                Button("Check levels") {}.buttonStyle(KeyButtonStyle(size: 14, big: true))
                Button("Mic") {}.buttonStyle(KeyButtonStyle(lit: true, size: 11))
                Button("Off") {}.buttonStyle(KeyButtonStyle(size: 11))
            }
            HStack(spacing: 18) {
                StatusLine(text: "Excellent", color: goodColor)
                StatusLine(text: "Setting sweep level", color: warnColor)
                StatusLine(text: "Record again", color: badColor)
                Pill(text: "−11.6 dBFS", color: goodColor)
                Lamp(state: .amber, size: 46)
            }
            JobStepper(steps: [("Connect", true), ("Set levels", true), ("Capture", false), ("Results", false)])
        }
        .padding(24).frame(width: 820)
        .onPanel()
        .padding(20)
        .background(WorkshopWall())
        .workshopDefaults()
        let r = ImageRenderer(content: view)
        r.scale = 2
        if let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? png.write(to: file)
        }
    }
}

// ------------------------------------------------------------------ the shelf
/// The oak shelf across the top: the job keys, the pilot lamp with its words, the Help key.
struct Shelf: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false
    var status: (Lamp.Glow, String) {
        if m.errorText != nil || m.levelError != nil || m.namError != nil || m.namLevelError != nil { return (.red, "Error: see the message") }
        if let b = m.busy {
            switch b {
            case .preparing: return (.amber, "Preparing")
            case .recording, .namRecording: return (.amber, "Recording")
            case .processing: return (.amber, "Processing")
            }
        }
        if m.levelRunning || m.namLevelRunning { return (.amber, "Checking levels") }
        return (.off, "Ready")
    }
    var body: some View {
        let st = status
        ZStack(alignment: .topLeading) {
            FrameStrip(name: "frame-plank", height: 53.75).padding(.top, 56)
            FrameStrip(name: "frame-trim-top", height: 21.88).padding(.top, 97)
            HStack(alignment: .top, spacing: 16) {
                ShelfBox {
                    Button("Cab IR") { m.job = .cab }.buttonStyle(KeyButtonStyle(lit: m.job == .cab, size: 13))
                    Button("Amp NAM") { m.job = .nam }.buttonStyle(KeyButtonStyle(lit: m.job == .nam, size: 13))
                }
                .disabled(m.busy != nil)
                Spacer(minLength: 0)
                ShelfBox {
                    Lamp(state: st.0, size: 46)
                        .opacity(st.0 == .amber && pulse ? 0.72 : 1)
                    GlassWindow(size: 13) { Text(st.1).textCase(.uppercase).tracking(1.4).frame(minWidth: 150, alignment: .leading) }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Status: \(st.1)")
                Spacer(minLength: 0)
                ShelfBox {
                    Button("Help") { m.helpPage = .quickStart }.buttonStyle(KeyButtonStyle(size: 13))
                }
            }
            .padding(.horizontal, 26).padding(.top, 2)
        }
        .frame(height: 119, alignment: .top)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

// ------------------------------------------------------------------ building blocks
/// One step: a hammertone panel, its title engraved, a jewel for its state (amber: to do; green: done).
struct Step<Content: View>: View {
    let n: Int
    let title: String
    var subtitle: String? = nil
    var done = false
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                JewelLamp(colour: done ? "green" : "amber", on: true, diameter: 26)
                    .accessibilityLabel(done ? "Done" : "To do")
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Engraved("Step \(n)", size: 10, dim: true)
                        Engraved(title, size: 17)
                    }
                    if let s = subtitle { Text(s).font(.swellBody(13)).fixedSize(horizontal: false, vertical: true) }
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onPanel()
    }
}

/// The steps of a job as indicator lamps with engraved legends: green when done, unlit when not.
struct JobStepper: View {
    let steps: [(String, Bool)]
    var body: some View {
        HStack(spacing: 18) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                HStack(spacing: 7) {
                    JewelLamp(colour: "green", on: s.1, diameter: 18)
                    Engraved(s.0, size: 11, dim: !s.1)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Step \(i + 1), \(s.0): \(s.1 ? "done" : "not done")")
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 2)
        .onPanel(padding: 12)
    }
}

struct Note: View {
    let text: String
    var color: Color = .secondary
    @Environment(\.swellSurface) private var surface
    init(_ t: String, color: Color = .secondary) { text = t; self.color = color }
    var body: some View {
        Text(text).font(.swellBody(13)).foregroundColor(surface.tone(color)).fixedSize(horizontal: false, vertical: true)
    }
}

/// An error, on a tag with a red title. If the fix is in Audio MIDI Setup or Privacy & Security, its key opens it.
struct ErrorNote: View {
    let text: String
    init(_ t: String) { text = t }
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                JewelLamp(colour: "red", on: true, diameter: 14)
                Engraved("Error", size: 11)
            }
            Text(text).font(.swellBody(13, semibold: true)).foregroundColor(Swell.tagError).fixedSize(horizontal: false, vertical: true)
            HStack {
                if text.contains("Audio MIDI Setup") { Button("Open Audio MIDI Setup") { CoreAudioHelper.openAudioMIDISetup() } }
                if text.contains("Privacy & Security") { Button("Open Privacy & Security") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!) } }
            }
        }
        .onPaper(padding: 11)
    }
}

/// Numbered instructions, printed on a card.
struct Checklist: View {
    let items: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, t in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(i + 1).").font(.swellBody(13, semibold: true)).foregroundColor(Swell.tagError).frame(width: 20, alignment: .trailing)
                    Text(t).font(.swellBody(13)).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onPaper()
    }
}

/// A figure with its status (was a coloured pill): a jewel and a small glass window.
struct Pill: View {
    let text: String
    let color: Color
    var body: some View { StatusWindow(text: text, color: color) }
}

/// A printed aside: a card with a heading.
struct Aside<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Engraved(title, size: 11)
            content
        }
        .onPaper()
    }
}

/// Progress of a capture or processing: the seconds left on nixie tubes while recording, the words beside them.
struct BusyLine: View {
    @EnvironmentObject var m: AppModel
    var secondsLeft: Int? {
        switch m.busy {
        case .some(.recording(let p)): return Int(((1 - p) * m.signalSeconds).rounded(.up))
        case .some(.namRecording(let p)): return Int(((1 - p) * 192).rounded(.up))
        default: return nil
        }
    }
    var body: some View {
        if let b = m.busy {
            HStack(alignment: .center, spacing: 14) {
                if let s = secondsLeft {
                    VStack(spacing: 3) {
                        NixieReadout(value: s)
                        Engraved("Seconds left", size: 9, dim: true)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        JewelLamp(colour: "amber", on: true, diameter: 14)
                        Text(b.text)
                    }
                    if let p = b.progress { ProgressView(value: p).tint(Swell.amber) } else { ProgressView().controlSize(.small) }
                }
                if b.progress != nil { Button("Stop") { m.cancelCapture() }.buttonStyle(KeyButtonStyle(lit: true, size: 13)) }
            }
        }
        if let e = m.errorText { ErrorNote(e) }
    }
}

struct SweepSettings: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        DisclosureGroup("Sweep timing") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 18) {
                    Stepper("Sweeps: \(m.nSweeps)", value: $m.nSweeps, in: 2...16)
                    Stepper("Length: \(String(format: "%g", m.duration)) s", value: $m.duration, in: 2...20, step: 0.5)
                    Stepper("Gap: \(String(format: "%g", m.gap)) s", value: $m.gap, in: 1...10, step: 0.5)
                    Stepper("Warm-up: \(m.discard)", value: $m.discard, in: 0...4)
                }
                Note("Set the gap longer than the room reverb tail. The first sweep is a warm-up and is discarded. Each doubling of the sweep count lowers the noise floor by about 3 dB.")
            }.padding(.top, 8)
        }
    }
}

/// The DAW route's fixed sweep level (the app route sets its own automatically).
struct LevelPicker: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        GlassMenu(title: "Sweep level", selection: $m.level, options: [-6.0, -12, -18, -24].map { ($0, "\(Int($0)) dBFS") })
    }
}

/// Which files to make (P0.8): Universal by default, plus named targets. Custom lives under Advanced.
struct TargetsPicker: View {
    @EnvironmentObject var m: AppModel
    func row(_ t: ExportTarget) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Toggle(t.title, isOn: on(t.id)).toggleStyle(.checkbox).fontWeight(t.id == "universal" ? .semibold : .regular)
            Note(t.detail).padding(.leading, 20)
        }
    }
    func on(_ id: String) -> Binding<Bool> {
        Binding(get: { m.targets.contains(id) }, set: { v in if v { m.targets.insert(id) } else { m.targets.remove(id) } })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Engraved("Files to make")
            ForEach(ExportTarget.destinations) { t in row(t) }
            Note("For unlisted devices (Quad Cortex, ToneX, Fractal, Kemper Cab Maker…), use Universal. These manufacturers do not publish a fixed format. Conversion is done by their software on import.")
            Engraved("Also make").padding(.top, 4)
            ForEach(ExportTarget.extras) { t in row(t) }
            Note("Made for each single-file set selected above (Universal, Strymon Iridium). A mic named Room or Amb (Room L, Ambient…) is treated as a room mic. Room mics have no minimum-phase version and are mixed with close mics at 80/20 and 60/40.")
        }
    }
}

/// Advanced output: polarity and the Custom matrix.
struct AdvancedOutput: View {
    @EnvironmentObject var m: AppModel
    func toggle<T: Hashable>(_ set: Binding<Set<T>>, _ v: T) -> Binding<Bool> {
        Binding(get: { set.wrappedValue.contains(v) }, set: { on in if on { set.wrappedValue.insert(v) } else { set.wrappedValue.remove(v) } })
    }
    var body: some View {
        DisclosureGroup("Advanced file options") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Keep polarity as recorded", isOn: $m.keepPolarity).toggleStyle(.checkbox)
                Note("By default, each IR is made with its main peak positive, as in commercial IR packs, so mics blend without cancellation. An inverted mic (for example, a back-of-cab mic) is flipped, and the flip is listed in the results.")
                Toggle("Custom files (pick rates, lengths, bit depth and trimming)", isOn: $m.customOn).toggleStyle(.checkbox)
                if m.customOn {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                        GridRow {
                            Text("Sample rates").foregroundStyle(.secondary)
                            HStack { ForEach(CoreAudioHelper.captureRates, id: \.self) { r in Toggle(rateTag(r), isOn: toggle($m.exportRates, r)) } }
                        }
                        GridRow {
                            Text("Lengths").foregroundStyle(.secondary)
                            HStack {
                                Toggle("Full room", isOn: toggle($m.lengths, "full"))
                                ForEach(["1024", "2048", "4096"], id: \.self) { l in Toggle(l, isOn: toggle($m.lengths, l)) }
                            }
                        }
                        GridRow {
                            Text("Bit depth").foregroundStyle(.secondary)
                            HStack {
                                Toggle("16-bit", isOn: toggle($m.bits, "16"))
                                Toggle("24-bit", isOn: toggle($m.bits, "24"))
                                Toggle("32-bit float", isOn: toggle($m.bits, "32f"))
                            }
                        }
                        GridRow {
                            Text("Trimming").foregroundStyle(.secondary)
                            HStack {
                                Toggle("Keep mic timing", isOn: toggle($m.trims, "set"))
                                Toggle("Trim each mic", isOn: toggle($m.trims, "individual"))
                            }
                        }
                        GridRow {
                            Text("Full room length").foregroundStyle(.secondary)
                            Stepper("\(Int(m.fullMs)) ms", value: $m.fullMs, in: 50...1000, step: 50)
                        }
                    }
                    .toggleStyle(.checkbox)
                    Note("Custom files are saved in More formats › Custom. “Keep mic timing”: all mics are trimmed by the same amount and share one gain, so the blend matches the original mics. “Trim each mic”: each file starts at its own first arrival and is normalized separately.")
                }
            }.padding(.top, 8)
        }
    }
}

struct SaveFolderRow: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        HStack(spacing: 10) {
            Engraved("Save to")
            GlassWindow(size: 12) {
                Text(m.outputFolder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.swellBody(13)).truncationMode(.middle).frame(maxWidth: 420, alignment: .leading)
            }
            Button("Change…") { m.chooseOutputFolder() }
        }
    }
}

struct CaptureNameFields: View {
    @EnvironmentObject var m: AppModel
    var withNotes = true
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Engraved("Capture name")
                GlassField(placeholder: "e.g. 412_V30_PosA", text: $m.captureName).frame(maxWidth: 320)
            }
            Note("Cab and mic position, e.g. 412_V30_PosA. All file names start with this name.")
            if withNotes {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Engraved("Notes")
                    GlassField(placeholder: "Mic positions, distances, amp settings… (saved in report.json)", text: $m.notes, vertical: true)
                }
            }
            SaveFolderRow()
        }
    }
}

/// A mic name in a glass window, with a menu of common names on its chevron (names become file names).
struct MicNameField: View {
    @Binding var name: String
    var disabled = false
    var body: some View {
        HStack(spacing: 0) {
            GlassWindow(size: 13) {
                HStack(spacing: 6) {
                    TextField("SM57, R121, Room…", text: $name).textFieldStyle(.plain)
                        .font(.swellLegend(13)).foregroundColor(Swell.amber)
                    Button {
                        PopUpMenu.show(commonMicNames.map { n in (title: n, checked: n == name, action: { name = n }) })
                    } label: { GlassChevron().padding(4).contentShape(Rectangle()) }
                    .buttonStyle(.plain)
                    .help("Common mic names")
                    .accessibilityLabel("Common mic names")
                }
            }
            .frame(width: 200)
        }
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
    }
}

// ------------------------------------------------------------------ results
/// Mic colours lifted for the dark instrument screen.
func screenColor(_ i: Int) -> Color {
    let c = NSColor(micColors[i % micColors.count]).usingColorSpace(.sRGB) ?? .white
    return Color(.sRGB, red: c.redComponent * 0.75 + 0.25, green: c.greenComponent * 0.75 + 0.25, blue: c.blueComponent * 0.75 + 0.25)
}

/// A warning on a tag (red title for the one that means "record again").
struct WarningTag: View {
    let text: String
    var severe = false
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            JewelLamp(colour: severe ? "red" : "amber", on: true, diameter: 13)
            Text(text).font(.swellBody(13, semibold: severe))
                .foregroundColor(severe ? Swell.tagError : Swell.tagInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onPaper(padding: 10)
    }
}

struct ResultsView: View {
    @EnvironmentObject var m: AppModel
    let r: ResultSummary
    var quality: (String, Color) {
        if r.droppedOut { return ("Record again", badColor) }
        if r.warnings.isEmpty { return ("Excellent", goodColor) }
        return (r.warnings.count == 1 ? "Good: 1 item to check" : "Check \(r.warnings.count) items", warnColor)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Engraved("Results", size: 17)
                GlassWindow(size: 14) { Text(r.title) }
                Spacer()
                StatusLine(text: quality.0, color: quality.1, diameter: 20).font(.swellLegend(14))
            }
            ForEach(r.warnings, id: \.self) { w in WarningTag(text: w, severe: r.droppedOut && w == r.warnings.first) }
            if r.droppedOut {
                HStack {
                    Button("Record again") { m.startCapture() }.buttonStyle(KeyButtonStyle(size: 13))
                        .disabled(m.busy != nil || m.captureProblem != nil)
                    Note("Quit other apps first (browsers, video calls, other audio software).")
                }
            }
            if !r.referenced { Note("No reference tap was used. These IRs include the power amp response.") }
            ForEach(r.polarityNotes, id: \.self) { n in Note("Polarity: " + n, color: .primary) }
            ForEach(r.exportNotes, id: \.self) { n in Note(n, color: .primary) }
            if !r.topFiles.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Engraved("Load these")
                    ForEach(r.topFiles, id: \.self) { f in GlassWindow(size: 12) { Text(f).font(.swellMono(12)) } }
                    Note("48 kHz, 24-bit, 500 ms. Compatible with IR loaders, DAW plug-ins and modelers. Other formats are in More formats.")
                }
            }
            DiagnosticsTable(r: r)
            Engraved("Frequency response, 1/6 octave")
            FaceplateScreen {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 14) {
                        ForEach(Array(r.names.enumerated()), id: \.offset) { i, n in
                            HStack(spacing: 5) {
                                RoundedRectangle(cornerRadius: 2).fill(screenColor(i)).frame(width: 10, height: 10)
                                Text(n).font(.swellLegend(12)).foregroundColor(Color(swellHex: 0xCFE3D6))
                            }
                        }
                    }
                    ResponsePlot(fc: r.curves.fc, curves: r.names.map { r.curves.curves[$0] ?? [] }, onScreen: true).frame(height: 300)
                }
            }
            HStack(spacing: 10) {
                Button("Show in Finder") { m.revealResult() }.buttonStyle(KeyButtonStyle(size: 13))
                Button("Re-export…") { m.reexportMessage = nil; m.reexportFolder = r.folder }
                    .help("Make other formats from the raw take of this capture without a new recording")
                Note("\(r.fileCount) IR files, README.txt and report.json in \(r.folder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))")
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onPanel()
    }
}

struct ReexportSheet: View {
    @EnvironmentObject var m: AppModel
    var processing: String? { if case .processing(let t) = m.busy { return t } else { return nil } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Engraved("Re-export", size: 17)
                    GlassWindow(size: 14) { Text(m.reexportFolder?.lastPathComponent ?? "") }
                }
                Note("The files are rebuilt from the raw take of this capture with the settings below. No new recording is made. Previously generated files are moved to the Trash. The raw take and report history are kept.")
                TargetsPicker()
                AdvancedOutput()
                if let msg = m.reexportMessage { ErrorNote(msg) }
                if let t = processing { StatusLine(text: t + "…", color: warnColor) }
                HStack {
                    Spacer()
                    Button("Cancel") { m.reexportFolder = nil }.keyboardShortcut(.cancelAction)
                    Button("Re-export") { if let f = m.reexportFolder { m.reexport(f) } }
                        .keyboardShortcut(.defaultAction).buttonStyle(KeyButtonStyle(lit: processing != nil, size: 13))
                        .disabled(m.busy != nil || m.outputProblem != nil)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onPanel()
        }
        .padding(12)
        .frame(width: 640, height: 620)
        .background(WorkshopWall())
    }
}

struct DiagnosticsTable: View {
    let r: ResultSummary
    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
            GridRow {
                ForEach(["Channel", "Recorded peak", "Noise floor", "Usable tail", "Distortion", "Arrival"], id: \.self) {
                    Engraved($0, size: 10, dim: true)
                }
            }
            Divider().gridCellUnsizedAxes(.horizontal)
            ForEach(Array(r.diagnostics.enumerated()), id: \.offset) { i, item in
                let d = item.diag, isRef = item.label == "reference"
                GridRow {
                    HStack(spacing: 6) {
                        if !isRef { RoundedRectangle(cornerRadius: 2).fill(screenColor(r.names.firstIndex(of: item.label) ?? i)).frame(width: 10, height: 10) }
                        Engraved(isRef ? "Reference" : item.label, size: 12)
                    }
                    Pill(text: String(format: "%.1f dBFS", d.recordingPeakDBFS),
                         color: d.recordingPeakDBFS > -0.3 ? badColor : d.recordingPeakDBFS < -30 ? warnColor : goodColor)
                    Text(d.noiseFloorDB.map { String(format: "%.0f dB", $0) } ?? "—").font(.swellMono(12))
                    Text(d.tailAboveNoiseMs.map { String(format: "%.0f ms", $0) } ?? "—").font(.swellMono(12))
                    if isRef { Text("—") } else if let w = d.worstHarmonic {
                        Pill(text: "H\(w.n) \(Int(w.db.rounded())) dB", color: w.db > -30 ? badColor : w.db > -40 ? warnColor : goodColor)
                    } else { Pill(text: "below noise", color: goodColor) }
                    Text(isRef ? "—" : (d.arrivalMs.map { String(format: "%.2f ms", $0) } ?? "—") + (r.referenced || isRef ? "" : " (relative)")).font(.swellMono(12))
                }
            }
        }
    }
}

struct ResponsePlot: View {
    let fc: [Double]
    let curves: [[Double]]
    /// Drawn on the instrument's dark screen (dim phosphor grid, lifted mic colours).
    var onScreen = false
    var body: some View {
        Canvas { ctx, size in
            let L = 44.0, R = 10.0, T = 8.0, B = 24.0
            let W = size.width, H = size.height
            let ink: Color = onScreen ? Color(swellHex: 0xA9C9B6) : .secondary
            var mx = -Double.infinity
            for c in curves { for (i, v) in c.enumerated() where fc[i] >= 40 && fc[i] <= 12000 { mx = max(mx, v) } }
            if !mx.isFinite { mx = 0 }
            let top = (mx / 10).rounded(.up) * 10 + 5, bot = top - 60
            func X(_ f: Double) -> Double { L + log10(f / 20) / log10(1000) * (W - L - R) }
            func Y(_ v: Double) -> Double { T + (top - max(bot, min(top, v))) / (top - bot) * (H - T - B) }
            if !onScreen { ctx.fill(Path(CGRect(x: L, y: T, width: W - L - R, height: H - T - B)), with: .color(.secondary.opacity(0.08))) }
            let grid = GraphicsContext.Shading.color(onScreen ? Color(swellHex: 0x7FB79A, opacity: 0.16) : .secondary.opacity(0.25))
            for f in [20.0, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000] {
                var p = Path(); p.move(to: CGPoint(x: X(f), y: T)); p.addLine(to: CGPoint(x: X(f), y: H - B))
                ctx.stroke(p, with: grid, lineWidth: 1)
                let label = f >= 1000 ? "\(Int(f / 1000))k" : "\(Int(f))"
                ctx.draw(Text(label).font(onScreen ? Font.swellMono(10) : Font.system(size: 10, design: .monospaced)).foregroundColor(ink),
                         at: CGPoint(x: X(f), y: H - B + 12), anchor: f == 20 ? .leading : f == 20000 ? .trailing : .center)
            }
            var v = bot + 5
            while v <= top {
                var p = Path(); p.move(to: CGPoint(x: L, y: Y(v))); p.addLine(to: CGPoint(x: W - R, y: Y(v)))
                ctx.stroke(p, with: grid, lineWidth: 1)
                ctx.draw(Text("\(Int(v - top + 5))").font(onScreen ? Font.swellMono(10) : Font.system(size: 10, design: .monospaced)).foregroundColor(ink),
                         at: CGPoint(x: L - 6, y: Y(v)), anchor: .trailing)
                v += 10
            }
            for (k, c) in curves.enumerated() where c.count == fc.count {
                var p = Path()
                for (i, f) in fc.enumerated() {
                    let pt = CGPoint(x: X(f), y: Y(c[i]))
                    if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                }
                let col = onScreen ? screenColor(k) : micColors[k % micColors.count]
                if onScreen { ctx.stroke(p, with: .color(col.opacity(0.35)), style: StrokeStyle(lineWidth: 5, lineJoin: .round)) }
                ctx.stroke(p, with: .color(col), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
            }
            ctx.draw(Text("dB").font(onScreen ? Font.swellMono(10) : Font.system(size: 10, design: .monospaced)).foregroundColor(ink), at: CGPoint(x: 4, y: T + 6), anchor: .leading)
        }
    }
}
#endif
