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
        // The wall runs to the top of the window, behind the traffic lights; the shelf stands below them.
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appInfo) {
                Button("About \(Product.name)") { Support.showAbout() }
            }
            CommandGroup(after: .toolbar) {
                PageSizeMenu()
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

/// View › Page Size: how large the page is drawn. Fit to Window (the default) grows it with the window's width.
enum PageSize: String, CaseIterable {
    case fit, actual, large, larger
    static let key = "pageSize"
    /// The page's own width at actual size (the 900 pt column, the stage's padding and moulding).
    static let baseWidth: CGFloat = 960
    var title: String {
        switch self {
        case .fit: return "Fit to Window"
        case .actual: return "Actual Size"
        case .large: return "Large (125 %)"
        case .larger: return "Larger (150 %)"
        }
    }
    /// The page's smallest size (the window's minimum): a scale never lays it out smaller than this, so the
    /// shelf and the stage never overrun each other in a small window.
    static let minPage = CGSize(width: 780, height: 640)
    static func scale(_ p: PageSize, window: CGSize) -> CGFloat {
        let wanted = rawScale(p, window: window)
        guard window.width > 0, window.height > 0 else { return 1 }
        return max(1, min(wanted, window.width / minPage.width, window.height / minPage.height))
    }
    static func rawScale(_ p: PageSize, window: CGSize) -> CGFloat {
        if let i = ProcessInfo.processInfo.arguments.firstIndex(of: "--page-scale"), i + 1 < ProcessInfo.processInfo.arguments.count,
           let v = Double(ProcessInfo.processInfo.arguments[i + 1]) { return CGFloat(v) }       // CI hook
        switch p {
        case .actual: return 1
        case .large: return 1.25
        case .larger: return 1.5
        case .fit:
            guard window.width > 0 else { return 1 }
            // in steps of 1/16, so a window being resized doesn't redraw every picture at every pixel
            let s = min(1.5, max(1, window.width / baseWidth))
            return (s * 16).rounded(.down) / 16
        }
    }
}

struct PageSizeMenu: View {
    @AppStorage(PageSize.key) private var pageSize = PageSize.fit.rawValue
    var body: some View {
        Picker("Page Size", selection: $pageSize) {
            ForEach(PageSize.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var m: AppModel
    @AppStorage(PageSize.key) private var pageSize = PageSize.fit.rawValue
    var body: some View {
        // (11-10, Lowell: "scale larger as long as it's still super crisp") The whole page, wall and shelf included,
        // is laid out at its own size and drawn larger: Fit to Window grows it with a wide window (up to 1.5 times),
        // or a fixed size from View › Page Size. The pictures carry 3 to 6 px a point, enough for 1.5 times on Retina.
        GeometryReader { g in
            let s = PageSize.scale(PageSize(rawValue: pageSize) ?? .fit, window: g.size)
            page
                .frame(width: g.size.width / s, height: g.size.height / s)
                .scaleEffect(s, anchor: .topLeading)
                .frame(width: g.size.width, height: g.size.height, alignment: .topLeading)
                .clipped()
        }
        .background(WorkshopWall().ignoresSafeArea())
        .sheet(isPresented: $m.showWelcome) { WelcomeSheet().environmentObject(m).workshopDefaults(.panel) }
        .sheet(item: $m.helpPage) { p in HelpSheet(page: p).environmentObject(m).workshopDefaults(.panel) }
        .sheet(isPresented: Binding(get: { m.reexportFolder != nil }, set: { if !$0 { m.reexportFolder = nil } })) {
            ReexportSheet().environmentObject(m).workshopDefaults(.panel)
        }
        .onAppear { runAutomation() }
    }

    @ViewBuilder var steps: some View {
        VStack(alignment: .leading, spacing: 18) {
            if m.job == .nam {
                NAMJob()
                if let r = m.namResult { NAMResultsView(r: r).id("namresults") }
            } else {
                CabJob()
                if let r = m.result { ResultsView(r: r).id("results") }
            }
        }
    }

    @ViewBuilder var page: some View {
        VStack(spacing: 0) {
            Shelf()
            if RackKit.shared != nil {
                // (Phase 7a) the rack bay standing against the wall: the units scroll, the wall and the shelf stay
                scroller {
                    steps
                        .padding(.bottom, 18)
                        .inRackBay()
                        .padding(.top, 10).padding(.bottom, 48)
                        .frame(maxWidth: .infinity)
                        .environment(\.swellTheme, m.job == .nam ? .nam : .cab)
                }
                .overlay(alignment: .top) {
                    // the shelf's shadow on the wall
                    LinearGradient(colors: [Color.black.opacity(0.5), Color.black.opacity(0.14), .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 30).allowsHitTesting(false).accessibilityHidden(true)
                }
            } else {
                StageOpening {
                    scroller {
                        steps
                            .padding(22).frame(maxWidth: 900, alignment: .leading).frame(maxWidth: .infinity)
                            .environment(\.swellTheme, m.job == .nam ? .nam : .cab)
                    }
                }
                .padding(.horizontal, 24).padding(.bottom, 22)
            }
        }
        .background(WorkshopWall())
        .workshopDefaults()
    }

    /// The page's scroll view, with its hooks (scroll to the results, CI's scroll to the machine).
    @ViewBuilder func scroller<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        let c = content()
        ScrollViewReader { proxy in
            ScrollView {
                c
            }
            .clipped()     // (under View › Page Size's scale the scroll view's own clip runs short; this one holds)
            .onChange(of: m.result?.folder) { _ in withAnimation { proxy.scrollTo("results", anchor: .top) } }
            .task {
                // CI hook: open scrolled to the tape machine (screenshot-deck.png, screenshot-cart.png).
                guard ProcessInfo.processInfo.arguments.contains("--scroll-to-machine") else { return }
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                proxy.scrollTo("machine", anchor: .top)
            }
            .onChange(of: m.namResult?.folder) { _ in withAnimation { proxy.scrollTo("namresults", anchor: .top) } }
        }
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
        let micNames = ["SM57", "R121", "MD421", "e906", "C414", "Room", "Reference"]
        let vus: [Double] = [0.4, -1.5, 2.2, -2.8, -7, 1, -0.5]
        let eyes: [Double] = [0.9, 0.75, 1.0, 0.6, 0.35, 0.5, 1.0]
        let view = VStack(alignment: .leading, spacing: 22) {
            Engraved("Cab IR: four inputs, full-size meters, noise eyes", size: 12)
            MeterBridge(count: 4) {
                MeterModule(label: "SM57", vu: 0, dbfs: "−6.0 dBFS", clipped: false, advice: ("OK", goodColor), eye: (1.0, true)) {
                    HStack(spacing: 6) { Pill(text: "H2 −52", color: goodColor); Pill(text: "H3 −47", color: goodColor) }
                }
                MeterModule(label: "R121", vu: -9, dbfs: "−15.0 dBFS", clipped: false, advice: ("Turn up 9 dB", warnColor), eye: (0.55, true)) { EmptyView() }
                MeterModule(label: "Room", vu: 4, dbfs: "−0.1 dBFS", clipped: true, advice: ("CLIP: turn down", badColor), eye: (0.2, true)) { EmptyView() }
                MeterModule(label: "Reference", vu: nil, dbfs: "−72.0 dBFS", clipped: false, advice: ("No signal: check cable", badColor), eye: (nil, false)) { EmptyView() }
            }
            if let d = TapePieces.deck {
                Engraved("Cab IR: the reel deck, 37 % into a capture (reels turned, packs sized, counter, REC lit)", size: 12)
                ScaledMachine(size: d.size, outline: d.outline) {
                    ReelDeckFace(d: d, state: DeckState(phiS: 23, phiT: 71, p: 0.37, seconds: 27, recording: true)) {
                        HStack(spacing: 8) {
                            HStack(spacing: 14) {
                                Button("Check levels") {}.buttonStyle(KeyButtonStyle(key: "Check levels", size: 12))
                                Button("Capture") {}.buttonStyle(KeyButtonStyle(key: "Capture", lit: true, size: 13))
                            }
                            JewelLamp(colour: "red", on: true, diameter: d.jewel.d * 0.82).frame(width: d.jewel.d, height: d.jewel.d)
                                .alignmentGuide(.deckJewel) { $0[HorizontalAlignment.center] }
                            Button("Stop") {}.buttonStyle(KeyButtonStyle(key: "Stop", size: 12))
                        }
                    }
                }
                Engraved("The same deck idle: tape on the supply reel", size: 12)
                ScaledMachine(size: d.size, outline: d.outline) {
                    ReelDeckFace(d: d, state: DeckState(phiS: 0, phiT: 0, p: 0, seconds: 43, recording: false)) { EmptyView() }
                }
            }
            if let b = TapePieces.box("reel") {
                HStack(alignment: .top, spacing: 20) {
                    TapeBox(kind: "reel", box: b, title: "Mesa_4x12_V30",
                            lines: [("Mics", "SM57, R121, Room"), ("Load", "Mesa_4x12_V30_SM57.wav"), ("Files", "86 IRs, README.txt"), ("Ref", "Reference used")],
                            stamp: ("Excellent", goodColor))
                    if let c = TapePieces.box("cart") {
                        TapeBox(kind: "cart", box: c, title: "JCM800_Gain6_Bass5", lines: [("Amp only", "Suhr"), ("Files", "1 WAV, UPLOAD-STEPS.txt")],
                                stamp: ("Ready to upload", goodColor))
                    }
                }
            }
            Engraved("Cab IR: six mics and a reference, four to a row", size: 12)
            MeterBridge(count: 7) {
                ForEach(0..<7, id: \.self) { i in
                    MeterModule(label: micNames[i], vu: vus[i],
                                dbfs: String(format: "%.1f dBFS", -6 + vus[i]), clipped: false,
                                advice: i == 4 ? ("Turn up 7 dB", warnColor) : ("OK", goodColor),
                                eye: (closure: eyes[i], lit: true)) {
                        if i < 6 {
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 6) { Pill(text: "H2 −51", color: goodColor); Pill(text: "H3 −48", color: goodColor) }
                                VStack(alignment: .leading, spacing: 5) { Pill(text: "H2 −51", color: goodColor); Pill(text: "H3 −48", color: goodColor) }
                            }
                        }
                    }
                }
            }
            HStack(spacing: 18) {
                VStack(spacing: 3) { NixieReadout(value: 45); Engraved("Seconds left", size: 9, dim: true) }
                Button("Capture") {}.buttonStyle(KeyButtonStyle(key: "Capture", lit: true, size: 16, big: true))
                Button("Check levels") {}.buttonStyle(KeyButtonStyle(key: "Check levels", size: 14, big: true))
                Button("Mic") {}.buttonStyle(KeyButtonStyle(key: "Mic", lit: true, size: 11))
                Button("Off") {}.buttonStyle(KeyButtonStyle(key: "Off", size: 11))
            }
            HStack(spacing: 18) {
                StatusLine(text: "Excellent", color: goodColor)
                StatusLine(text: "Setting sweep level", color: warnColor)
                StatusLine(text: "Record again", color: badColor)
                Pill(text: "−11.6 dBFS", color: goodColor)
                Lamp(state: .amber, size: 46)
            }
            // (11-11) the lettering: the status line on the VFD, mic names on scribble strips, printed keys
            Engraved("The status line, mic names on tape, printed keys", size: 12)
            VFDStatusLine(text: vfdLine(left: "Ready", middle: "Scarlett 18i20 USB", right: "96K", n: VFDStatusLine.n))
            HStack(spacing: 16) {
                ScribbleNameField(name: .constant("SM57 cap edge"), strip: 0)
                ScribbleNameField(name: .constant("R121 6 in center, 15 deg off axis"), strip: 1)
                ScribbleNameField(name: .constant(""), strip: 2)
            }
            HStack(spacing: 12) {
                Button("Show in Finder") {}.buttonStyle(KeyButtonStyle(key: "Show in Finder", size: 12))
                Button("Re-export…") {}.buttonStyle(KeyButtonStyle(key: "Re-export…"))
                Button("Record again") {}.buttonStyle(KeyButtonStyle(key: "Record again", size: 13))
                Button("Import DAW recordings…") {}.buttonStyle(KeyButtonStyle(key: "Import DAW recordings…"))
                Button("Remove") {}.buttonStyle(KeyButtonStyle(key: "Remove", size: 10)).disabled(true)
            }
            JobStepper(steps: [("Connect", true), ("Set levels", true), ("Capture", false), ("Results", false)])
            Engraved("The rack bay's step strip: two steps done, the third current", size: 12)
            RackStepStrip(steps: [("Connect", true), ("Set levels", true), ("Capture", false), ("Results", false)])
            if RackMeterBridge.available {
                Engraved("The meter bridge: three inputs in a level check (OK; 9 dB low; clipping with distortion), a blank plate in the fourth slot", size: 12)
                RackMeterBridge(channels: [
                    RackChannel(id: 0, name: "SM57 cap edge", vu: -0.4, peak: -6.4, lamps: [1], eye: (0.9, true), spoken: "level OK"),
                    RackChannel(id: 1, name: "R121 center", vu: -9, peak: -15.0, lamps: [0], eye: (0.55, true), spoken: "9 dB low"),
                    RackChannel(id: 2, name: "Room 3 m", vu: 3.3, peak: -0.1, lamps: [2, 3, 4], eye: (0.2, true), spoken: "clipping"),
                ])
                Engraved("Before the level check: four inputs named, the meters at rest", size: 12)
                RackMeterBridge(channels: [RackChannel(id: 0, name: "SM57"), RackChannel(id: 1, name: "R121 6 in center, 15 deg off axis"),
                                           RackChannel(id: 2, name: "MD421"), RackChannel(id: 7, name: "Reference")])
            }
            if let r = RackKit.ready("patch"), let p = r.1.patch {
                let roles: [Int: Role] = [0: .mic, 1: .mic, 2: .mic, 5: .ref]
                Engraved("The patch unit: a six-input interface, three mics and a reference, the two empty slots plugged", size: 12)
                RackPatchUnit(kit: r.0, unit: r.1, patch: p, bank: 0, count: 6, role: { roles[$0] ?? .off }, set: { _, _ in })
                Engraved("The second patch unit of an 18-input interface: inputs 9 to 16, input 12 a mic", size: 12)
                RackPatchUnit(kit: r.0, unit: r.1, patch: p, bank: 1, count: 18, role: { $0 == 11 ? .mic : .off }, set: { _, _ in })
            }
            if RackResultsUnit.available {
                Engraved("The results unit: the take sheet typed for two mics and a reference, a distortion figure ringed, stamped CHECK NOTES", size: 12)
                RackResultsUnit(sheet: TakeSheet(
                    capture: "Mesa_4x12_V30_posA", date: "11 NOV 26", interface: "Scarlett 18i20 USB", rate: "96 kHz",
                    rows: [TakeSheet.Row(name: "SM57", colour: 0, values: ["peak": "-11.6", "noise": "-108", "tail": "36", "h2": "-45", "h3": "-52", "arrival": "0.17"]),
                           TakeSheet.Row(name: "R121 center", colour: 1, values: ["peak": "-10.5", "noise": "-84", "tail": "451", "h2": "-27", "h3": "-51", "arrival": "0.29"],
                                         ring: ["h2"]),
                           TakeSheet.Row(name: "Reference", colour: nil, values: ["peak": "-21.1", "noise": "-122", "tail": "360", "h2": "-", "h3": "-", "arrival": "-"])],
                    files: ["Mesa_4x12_V30_posA_SM57.wav", "Mesa_4x12_V30_posA_R121_center.wav", "48 kHz  24-bit  500 ms"],
                    notes: ["R121 center: harmonic distortion is 27 dB below the linear response. The speaker is being driven hard; an IR can't capture that, so try about 6 dB less level.",
                            "86 IR files, README.txt, report.json. Reference used.", "Notes: 57 1 in off cap edge; 121 6 in center"],
                    verdict: "check", seed: 7))
            }
            if RackChartUnit.available {
                Engraved("The chart panel: the hook-up drawing and the card, rendered whole", size: 12)
                RackChartUnit()
            }
            if RackPreflightUnit.available {
                Engraved("The pre-flight typed in: ticked lines, levels and a noisy room ringed, the files crossed", size: 12)
                RackPreflightUnit(lines: [
                    PreflightLine(item: "Mics", reading: "2: SM57 cap edge, R121 center", mark: .tick),
                    PreflightLine(item: "Reference", reading: "Input 8", mark: .tick),
                    PreflightLine(item: "Sample rate", reading: "96 kHz on Scarlett 18i20 USB", mark: .tick),
                    PreflightLine(item: "Levels", reading: "R121 center low by 9 dB", mark: .ring),
                    PreflightLine(item: "Sweep level", reading: "-12 dBFS, set automatically", mark: .tick),
                    PreflightLine(item: "Room noise", reading: "Noisy: R121 center at -38 dBFS", mark: .ring, aside: "fridge? fan?"),
                    PreflightLine(item: "Files", reading: "None chosen", mark: .cross),
                ])
                Engraved("Before the level check: levels, sweep level and room noise not measured yet", size: 12)
                RackPreflightUnit(lines: [
                    PreflightLine(item: "Mics", reading: "1: SM57", mark: .tick),
                    PreflightLine(item: "Reference", reading: "None", mark: .tick),
                    PreflightLine(item: "Sample rate", reading: "48 kHz on USB Audio CODEC", mark: .tick),
                    PreflightLine(item: "Levels", reading: "Not checked yet", mark: .none),
                    PreflightLine(item: "Sweep level", reading: "Set automatically", mark: .none),
                    PreflightLine(item: "Room noise", reading: "Not measured yet", mark: .none),
                    PreflightLine(item: "Files", reading: "Universal, Mixes of two mics", mark: .tick),
                ])
            }
            HStack(alignment: .top, spacing: 16) {
                Checklist(items: ["A manila card.", "Its second line, for the look of it."], style: PaperStyle(stock: .manila, ring: true))
                    .frame(width: 250)
                PreflightList(items: [PreflightItem(level: .ok, text: "2 mics (SM57, R121)"), PreflightItem(level: .warn, text: "Room is noisy"),
                                      PreflightItem(level: .block, text: "Choose a capture name")])
                    .frame(width: 250)
            }
            .padding(.top, 8)
            WiringDiagram(wiring: .cabRef).onPaper(padding: 14, style: .drawing)
        }
        .padding(24).frame(width: 880)
        .onPanel()
        let nam = VStack(alignment: .leading, spacing: 18) {
            Engraved("Amp (NAM): graphite panel, LED lamps, LED-ladder meters", size: 12)
            JobStepper(steps: [("Signal", true), ("Connect", true), ("Set levels", false), ("Record", false), ("Upload", false)])
            RackStepStrip(steps: [("Signal", true), ("Connect", true), ("Set levels", false), ("Record", false), ("Upload", false)])
            if let c = TapePieces.cart {
                Engraved("Amp NAM: the cart machine, 74 s into the take (playhead, timer, READY and CUE lamps, RECORD lit)", size: 12)
                ScaledMachine(size: c.size, outline: c.outline) {
                    CartFace(c: c, state: CartState(playhead: 74, secondsLeft: 116, ready: true, cues: true)) {
                        ForEach(["check", "record", "stop"], id: \.self) { k in
                            let r = c.keys[k] ?? [0, 0, 1, 1]
                            Button(k) {}.buttonStyle(CartKeyStyle(key: k, rect: CGRect(x: 0, y: 0, width: r[2], height: r[3]), lit: k == "record"))
                                .offset(x: r[0], y: r[1])
                        }
                    }
                }
            }
            if RackNAMMeterBridge.available {
                Engraved("The NAM meter bridge: three inputs in a level check (OK; 12 dB low; clipped), a blank plate in the fourth slot", size: 12)
                RackNAMMeterBridge(channels: [
                    RackNAMChannel.reading(id: 0, name: "Line out", peak: -8.2, level: -9.6, clipped: false),
                    RackNAMChannel.reading(id: 1, name: "SM57 cap edge", peak: -20.6, level: -23.1, clipped: false),
                    RackNAMChannel.reading(id: 2, name: "R121", peak: -0.2, level: -1.4, clipped: true),
                ])
                Engraved("Before the level check: two inputs set to Use, the meters dark", size: 12)
                RackNAMMeterBridge(channels: [RackNAMChannel(id: 0, name: "Suhr line out"), RackNAMChannel(id: 1, name: "SM57")])
            }
            NAMMeterTable(meters: [NAMMeter(id: 0, label: "Suhr", peakDB: -8.2, clipped: false), NAMMeter(id: 1, label: "SM57", peakDB: -19.5, clipped: false),
                                   NAMMeter(id: 2, label: "R121", peakDB: -0.2, clipped: true)])
            WiringDiagram(wiring: .namAmp).onPaper(padding: 14, style: .drawing)
        }
        .padding(24).frame(width: 880)
        .onPanel()
        .environment(\.swellTheme, .nam)
        let sheet = VStack(alignment: .leading, spacing: 24) { view; nam }
            .padding(20)
            .background(WorkshopWall())
            .workshopDefaults()
        let r = ImageRenderer(content: sheet)
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
    /// The interface and the rate it runs at, under the status (the bench's status box shows its rate the same way).
    var rig: String {
        guard let d = m.device else { return "No interface connected" }
        let rate = m.job == .nam ? 48000 : m.captureRate
        return "\(d.name) · \(rateTag(rate).dropLast()) kHz"
    }
    /// The rate for the VFD's right end, "96K".
    var rateText: String { "\(rateTag(m.job == .nam ? 48000 : m.captureRate).dropLast())K" }
    var body: some View {
        let st = status
        let g = ShelfGeometry.own
        ZStack(alignment: .topLeading) {
            if let g {
                FrameStrip(name: g.plank, height: g.plankHeight, pxPerPoint: g.pxPerPoint).offset(y: g.plankTop)
            } else {
                FrameStrip(name: "frame-plank", height: 53.75).padding(.top, 56)
                FrameStrip(name: "frame-trim-top", height: 21.88).padding(.top, 97)
            }
            // With the own pieces each box picture carries its right end's shadow (about 76 pt): the boxes overlap there.
            HStack(alignment: .top, spacing: g == nil ? 16 : -36) {
                ShelfBox(finish: "bronze") {
                    Button("Cab IR") { m.job = .cab }.buttonStyle(KeyButtonStyle(key: "Cab IR", lit: m.job == .cab, size: 13))
                    Button("Amp NAM") { m.job = .nam }.buttonStyle(KeyButtonStyle(key: "Amp NAM", lit: m.job == .nam, size: 13))
                }
                .disabled(m.busy != nil)
                Spacer(minLength: 0)
                ShelfBox(finish: "oxblood") {
                    Group {
                        if g != nil {
                            JewelLamp(colour: st.0 == .red ? "red" : "amber", on: st.0 != .off, diameter: 22)
                        } else {
                            Lamp(state: st.0, size: 46)
                        }
                    }
                    .accessibilityHidden(true)
                    if GasKit.display("line") != nil {
                        // (11-11) the status on the bench's VFD: the status, the interface (shortened to fit), the rate
                        // (Phase 7a) during the Cab IR level check, the advice for the input that most needs it
                        let advice = m.job == .cab && m.levelRunning && RackMeterBridge.available ? m.levelGuidance : nil
                        let left = advice ?? st.1
                        let room = left.count + rateText.count + 1 <= VFDStatusLine.n
                        VFDStatusLine(text: vfdLine(left: left, middle: advice == nil ? (m.device?.name ?? "No interface") : "",
                                                    right: m.device == nil || !room ? "" : rateText, n: VFDStatusLine.n))
                            .help(rig)
                    } else {
                        GlassWindow(size: 13) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(st.1).textCase(.uppercase).tracking(1.4)
                                Text(rig).font(.swellLegend(10)).tracking(0.6).opacity(0.78)
                            }
                            .frame(minWidth: 172, alignment: .leading)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Status: \(st.1)")
                Spacer(minLength: 0)
                ShelfBox(finish: "bronze") {
                    Button("Help") { m.helpPage = .quickStart }.buttonStyle(KeyButtonStyle(key: "Help", size: 13))
                }
            }
            .padding(.horizontal, 26).offset(y: g?.boxTop ?? 2)
        }
        .frame(height: g?.height ?? 119, alignment: .top)
    }
}

/// IR Capture's own shelf (design/render/ircapture_kit.py: the plank and the boxes rendered in the Tools studio,
/// orthographic; since 11-10 seen from 9 degrees below, as the shelf is above the eye: its front edge and underside,
/// no top), read from SwellKit/irc-shelf.json.
/// nil when the file or a picture is missing: the shelf then uses the bench's frame pieces (seen from below).
struct ShelfGeometry: Decodable {
    let pxPerPoint: CGFloat
    let plank: String
    /// The plank strip's height (pt, its shadow included), how far its top sits below the box picture's top, and
    /// where the shelf ends in the strip (its front edge's bottom from above; from below, the underside's back edge
    /// against the wall): the shelf's frame ends there; the shadow runs on over the stage.
    let plankHeight: CGFloat
    let plankBelowBoxTop: CGFloat
    let plankFrontBottom: CGFloat
    /// Box pictures by finish ("bronze", "oxblood"); their height, 9-slice insets and front face (pt from the picture's edges).
    let boxes: [String: String]
    let boxHeight: CGFloat
    let boxInsets: [CGFloat]       // top, leading, bottom, trailing
    let boxFace: [CGFloat]         // top, leading, bottom, trailing
    /// The box pictures' top under the title bar (pt; negative runs their transparent margin up behind it).
    let boxTop: CGFloat
    /// The opening's moulding, seen from the same camera: strips this wide (pt), at the same scale.
    let trimH: String
    let trimV: String
    let trimWidth: CGFloat
    var plankTop: CGFloat { boxTop + plankBelowBoxTop }
    /// Wall between the plank's front edge and the opening (the opening's top moulding sits in it).
    let gapBelowPlank: CGFloat
    var height: CGFloat { plankTop + plankFrontBottom + gapBelowPlank }
    func insets(_ a: [CGFloat]) -> EdgeInsets { EdgeInsets(top: a[0], leading: a[1], bottom: a[2], trailing: a[3]) }
    func boxPiece(_ finish: String) -> SwellNine.Piece {
        SwellNine.Piece(name: boxes[finish] ?? boxes["bronze"] ?? "", pxPerPoint: pxPerPoint, insets: insets(boxInsets), mode: .tile, outset: 0)
    }

    static let own: ShelfGeometry? = {
        let url = SwellKit.folder.appendingPathComponent("irc-shelf.json")
        guard let data = try? Data(contentsOf: url), let g = try? JSONDecoder().decode(ShelfGeometry.self, from: data),
              g.boxInsets.count == 4, g.boxFace.count == 4 else { return nil }
        let files = [g.plank, g.trimH, g.trimV] + Array(g.boxes.values)
        guard files.allSatisfy({ SwellPictures.shared.cgImage($0 + ".webp") != nil }) else { return nil }
        return g
    }()
}

// ------------------------------------------------------------------ building blocks
/// One step: a hammertone panel, its title engraved, a jewel for its state (amber: to do; green: done).
struct Step<Content: View>: View {
    /// nil: a panel without a step number (Capture name and files).
    var n: Int? = nil
    let title: String
    var subtitle: String? = nil
    var done = false
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                DoneLamp(done: done, diameter: 26)
                    .accessibilityElement()
                    .accessibilityLabel(done ? "Done" : "To do")
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if let n { Engraved("Step \(n)", size: 10, dim: true) }
                        Engraved(title, size: 17)
                    }
                    if let s = subtitle { Text(s).font(.swellBody(13)).fixedSize(horizontal: false, vertical: true) }
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onPanel(seed: n ?? 5)
    }
}

/// The steps of a job as indicator lamps with engraved legends: green when done, unlit when not.
struct JobStepper: View {
    let steps: [(String, Bool)]
    var body: some View {
        HStack(spacing: 18) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                HStack(spacing: 7) {
                    DoneLamp(done: s.1, diameter: 18, offIsAmber: false)
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
                if text.contains("Audio MIDI Setup") { Button("Open Audio MIDI Setup") { CoreAudioHelper.openAudioMIDISetup() }.buttonStyle(KeyButtonStyle(key: "Open Audio MIDI Setup")) }
                if text.contains("Privacy & Security") { Button("Open Privacy & Security") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!) }.buttonStyle(KeyButtonStyle(key: "Open Privacy & Security")) }
            }
        }
        .onPaper(padding: 11)
    }
}

/// Numbered instructions, printed on a card.
struct Checklist: View {
    let items: [String]
    var style = PaperStyle.card
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, t in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(i + 1).").font(.swellBody(13, semibold: true)).foregroundColor(Swell.tagError).frame(width: 20, alignment: .trailing)
                    Text(t).font(.swellBody(13)).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onPaper(style: style)
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
                if b.progress != nil { Button("Stop") { m.cancelCapture() }.buttonStyle(KeyButtonStyle(key: "Stop", lit: true, size: 13)) }
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
            Button("Change…") { m.chooseOutputFolder() }.buttonStyle(KeyButtonStyle(key: "Change…"))
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
        if RackResultsUnit.available {
            // (Phase 7a) the results unit: the take sheet filled in, its stamp, FINDER, RE-EXPORT, RECORD AGAIN; the
            // scope still the old panel under it until its unit is built
            VStack(alignment: .leading, spacing: 18) {
                RackResultsUnit(sheet: TakeSheet(r), finder: { m.revealResult() },
                                reexport: { m.reexportMessage = nil; m.reexportFolder = r.folder },
                                recordAgain: { m.startCapture() },
                                recordAgainEnabled: r.direct && m.busy == nil && m.captureProblem == nil)
                scope.frame(maxWidth: .infinity, alignment: .leading).onPanel()
            }
        } else {
            classic
        }
    }

    /// The frequency response on the scope's screen.
    @ViewBuilder var scope: some View {
        VStack(alignment: .leading, spacing: 14) {
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
                    SweptResponsePlot(fc: r.curves.fc, curves: r.names.map { r.curves.curves[$0] ?? [] }).frame(height: 300)
                        .id(r.folder)
                }
            }
        }
    }

    /// The results before the rack bay (the tape box, notes, the table, the scope).
    @ViewBuilder var classic: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let b = TapePieces.box("reel") {
                // Phase 7: the capture goes back in its box; the track sheet lists what is on it.
                HStack(alignment: .top, spacing: 20) {
                    VStack(spacing: 12) {
                        TapeBox(kind: "reel", box: b, title: r.title,
                                lines: [("Mics", r.names.joined(separator: ", ")), ("Load", r.topFiles.first ?? "Universal file"),
                                        ("Files", "\(r.fileCount) IRs, README.txt"), ("Ref", r.referenced ? "Reference used" : "None")],
                                stamp: quality)
                        HStack(spacing: 10) {
                            Button("Finder") { m.revealResult() }.buttonStyle(KeyButtonStyle(key: "Show in Finder", size: 12))
                                .help("Show the capture folder in the Finder")
                            Button("Re-export") { m.reexportMessage = nil; m.reexportFolder = r.folder }.buttonStyle(KeyButtonStyle(key: "Re-export…", size: 12))
                                .help("Make other formats from the raw take of this capture without a new recording")
                        }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Engraved("Results", size: 17)
                            Spacer()
                            StatusLine(text: quality.0, color: quality.1, diameter: 20).font(.swellLegend(14))
                        }
                        ResultsNotes(r: r)
                    }
                }
            } else {
            HStack(spacing: 12) {
                Engraved("Results", size: 17)
                GlassWindow(size: 14) { Text(r.title) }
                Spacer()
                StatusLine(text: quality.0, color: quality.1, diameter: 20).font(.swellLegend(14))
            }
            ResultsNotes(r: r)
            }
            if TapePieces.box("reel") != nil { DiagnosticsTable(r: r) }
            if TapePieces.box("reel") == nil { DiagnosticsTable(r: r) }
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
                    SweptResponsePlot(fc: r.curves.fc, curves: r.names.map { r.curves.curves[$0] ?? [] }).frame(height: 300)
                        .id(r.folder)
                }
            }
            HStack(spacing: 10) {
                Button("Show in Finder") { m.revealResult() }.buttonStyle(KeyButtonStyle(key: "Show in Finder", size: 13))
                Button("Re-export…") { m.reexportMessage = nil; m.reexportFolder = r.folder }.buttonStyle(KeyButtonStyle(key: "Re-export…"))
                    .help("Make other formats from the raw take of this capture without a new recording")
                Note("\(r.fileCount) IR files, README.txt and report.json in \(r.folder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))")
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onPanel()
    }
}

/// The results' warnings, notes and the files to load.
struct ResultsNotes: View {
    @EnvironmentObject var m: AppModel
    let r: ResultSummary
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(r.warnings, id: \.self) { w in WarningTag(text: w, severe: r.droppedOut && w == r.warnings.first) }
            if r.droppedOut {
                HStack {
                    Button("Record again") { m.startCapture() }.buttonStyle(KeyButtonStyle(key: "Record again", size: 13))
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
        }
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
                    Button("Cancel") { m.reexportFolder = nil }.buttonStyle(KeyButtonStyle(key: "Cancel")).keyboardShortcut(.cancelAction)
                    Button("Re-export") { if let f = m.reexportFolder { m.reexport(f) } }
                        .keyboardShortcut(.defaultAction).buttonStyle(KeyButtonStyle(key: "Re-export", lit: processing != nil, size: 13))
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

/// The response plot drawn on as the beam sweeps from 20 Hz to 20 kHz when the results arrive, as a sweep would.
struct SweptResponsePlot: View {
    let fc: [Double]
    let curves: [[Double]]
    @State private var progress = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        BeamPlot(fc: fc, curves: curves, progress: progress)
            .onAppear {
                if reduceMotion { progress = 1; return }
                progress = 0
                withAnimation(.easeInOut(duration: 1.6)) { progress = 1 }
            }
    }
    private struct BeamPlot: View, Animatable {
        let fc: [Double]
        let curves: [[Double]]
        var progress: Double
        var animatableData: Double { get { progress } set { progress = newValue } }
        var body: some View { ResponsePlot(fc: fc, curves: curves, onScreen: true, progress: progress) }
    }
}

struct ResponsePlot: View {
    let fc: [Double]
    let curves: [[Double]]
    /// Drawn on the instrument's dark screen (dim phosphor grid, lifted mic colours).
    var onScreen = false
    /// How much of the plot the beam has drawn, left to right (1: all of it).
    var progress: Double = 1
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
            let reach = L + max(0, min(1, progress)) * (W - L - R)
            for (k, c) in curves.enumerated() where c.count == fc.count {
                var p = Path()
                var head: CGPoint? = nil
                for (i, f) in fc.enumerated() {
                    let pt = CGPoint(x: X(f), y: Y(c[i]))
                    if pt.x > reach + 0.5 { break }
                    if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                    head = pt
                }
                let col = onScreen ? screenColor(k) : micColors[k % micColors.count]
                if onScreen { ctx.stroke(p, with: .color(col.opacity(0.35)), style: StrokeStyle(lineWidth: 5, lineJoin: .round)) }
                ctx.stroke(p, with: .color(col), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                if onScreen, progress < 0.999, let h = head {
                    ctx.fill(Path(ellipseIn: CGRect(x: h.x - 4, y: h.y - 4, width: 8, height: 8)), with: .color(col.opacity(0.45)))
                    ctx.fill(Path(ellipseIn: CGRect(x: h.x - 2, y: h.y - 2, width: 4, height: 4)), with: .color(.white.opacity(0.9)))
                }
            }
            ctx.draw(Text("dB").font(onScreen ? Font.swellMono(10) : Font.system(size: 10, design: .monospaced)).foregroundColor(ink), at: CGPoint(x: 4, y: T + 6), anchor: .leading)
        }
    }
}
#endif
