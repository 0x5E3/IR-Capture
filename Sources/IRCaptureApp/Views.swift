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
            Picker("", selection: $m.job) {
                Text("Cab IR").tag(Job.cab)
                Text("Amp (NAM)").tag(Job.nam)
            }
            .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 360).padding(.top, 12).padding(.bottom, 4)
            .disabled(m.busy != nil)
            Text(m.job == .cab ? "Record the speaker cab's impulse response." : "Record the amp for a NAM model, trained at TONE3000.")
                .font(.callout).foregroundStyle(.secondary).padding(.bottom, 10)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
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
        .sheet(isPresented: $m.showWelcome) { WelcomeSheet().environmentObject(m) }
        .sheet(item: $m.helpPage) { p in HelpSheet(page: p).environmentObject(m) }
        .sheet(isPresented: Binding(get: { m.reexportFolder != nil }, set: { if !$0 { m.reexportFolder = nil } })) {
            ReexportSheet().environmentObject(m)
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
            m.targets = ["universal", "everything", "helix", "iridium"]
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

// ------------------------------------------------------------------ building blocks
struct Step<Content: View>: View {
    let n: Int
    let title: String
    var subtitle: String? = nil
    var done = false
    @ViewBuilder let content: Content
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    ZStack {
                        Circle().fill(done ? goodColor : lamp).frame(width: 24, height: 24)
                        if done { Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white) }
                        else { Text("\(n)").font(.system(size: 14, weight: .bold)).foregroundStyle(.black) }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title.uppercased()).font(.system(size: 15, weight: .semibold)).kerning(0.8)
                        if let s = subtitle { Text(s).foregroundStyle(.secondary) }
                    }
                }
                content
            }
            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The Connect → Set levels → Capture → Results strip at the top of each job.
struct JobStepper: View {
    let steps: [(String, Bool)]
    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                if i > 0 { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary) }
                HStack(spacing: 5) {
                    Image(systemName: s.1 ? "checkmark.circle.fill" : "\(i + 1).circle")
                        .foregroundStyle(s.1 ? goodColor : Color.secondary)
                    Text(s.0).foregroundStyle(s.1 ? Color.primary : Color.secondary)
                }
            }
        }
        .font(.callout.weight(.medium))
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
    }
}

struct Note: View {
    let text: String
    var color: Color = .secondary
    init(_ t: String, color: Color = .secondary) { text = t; self.color = color }
    var body: some View { Text(text).font(.callout).foregroundStyle(color).fixedSize(horizontal: false, vertical: true) }
}

/// An error line. If the fix is in Audio MIDI Setup, it carries a button that opens it.
struct ErrorNote: View {
    let text: String
    init(_ t: String) { text = t }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Note(text, color: badColor)
            HStack {
                if text.contains("Audio MIDI Setup") { Button("Open Audio MIDI Setup") { CoreAudioHelper.openAudioMIDISetup() } }
                if text.contains("Privacy & Security") { Button("Open Privacy & Security") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!) } }
            }
        }
    }
}

struct Checklist: View {
    let items: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, t in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(i + 1).").bold().foregroundStyle(lamp).frame(width: 20, alignment: .trailing)
                    Text(t).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

struct Pill: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text).font(.caption.weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.18))).foregroundStyle(color)
    }
}

struct Aside<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.caption.weight(.semibold)).kerning(0.8).foregroundStyle(.secondary)
            content
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.1)))
    }
}

struct BusyLine: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        if let b = m.busy {
            VStack(alignment: .leading, spacing: 6) {
                if let p = b.progress { ProgressView(value: p).tint(lamp) } else { ProgressView().controlSize(.small) }
                HStack {
                    Text(b.text).foregroundStyle(.secondary)
                    Spacer()
                    if b.progress != nil { Button("Stop") { m.cancelCapture() } }
                }
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
                Note("The gap has to be longer than the room's reverb tail. The first sweep is a warm-up and isn't used. More sweeps lower the noise floor by about 3 dB each time you double them.")
            }.padding(.top, 8)
        }
    }
}

/// The DAW route's fixed sweep level (the app route sets its own automatically).
struct LevelPicker: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        Picker("Sweep level", selection: $m.level) {
            ForEach([-6.0, -12, -18, -24], id: \.self) { Text("\(Int($0)) dBFS").tag($0) }
        }.frame(width: 200)
    }
}

/// Which files to make (P0.8): Universal by default, plus named targets. Custom lives under Advanced.
struct TargetsPicker: View {
    @EnvironmentObject var m: AppModel
    func on(_ id: String) -> Binding<Bool> {
        Binding(get: { m.targets.contains(id) }, set: { v in if v { m.targets.insert(id) } else { m.targets.remove(id) } })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FILES TO MAKE").font(.caption.weight(.semibold)).kerning(0.8).foregroundStyle(.secondary)
            ForEach(ExportTarget.all) { t in
                VStack(alignment: .leading, spacing: 1) {
                    Toggle(t.title, isOn: on(t.id)).toggleStyle(.checkbox).fontWeight(t.id == "universal" ? .semibold : .regular)
                    Text(t.detail).font(.caption).foregroundStyle(.secondary).padding(.leading, 20).fixedSize(horizontal: false, vertical: true)
                }
            }
            Note("Not listed (Quad Cortex, ToneX, Fractal, Kemper Cab Maker…)? Use Universal; those makers don't publish a fixed format, and their own software converts on import.")
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
                Note("Normally every IR is made with its main peak positive, as commercial IR packs are, so mics blend without cancelling. A mic that came out inverted (a back-of-cab mic, say) is flipped and the results say so.")
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
                    Note("Custom files go in More formats › Custom. “Keep mic timing” trims every mic by the same amount and gives them one shared gain, so they blend the way the real mics did. “Trim each mic” starts each file at its own first arrival and normalizes it on its own.")
                }
            }.padding(.top, 8)
        }
    }
}

struct SaveFolderRow: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        HStack {
            Text("Save to").foregroundStyle(.secondary)
            Text(m.outputFolder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                .font(.system(.body, design: .monospaced)).lineLimit(1).truncationMode(.middle)
            Button("Change…") { m.chooseOutputFolder() }
        }
    }
}

struct CaptureNameFields: View {
    @EnvironmentObject var m: AppModel
    var withNotes = true
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Capture name").foregroundStyle(.secondary)
                TextField("e.g. 412_V30_PosA", text: $m.captureName).frame(maxWidth: 320)
            }
            Note("Which cab and where the mics were, e.g. 412_V30_PosA. Every file starts with this.")
            if withNotes {
                HStack(alignment: .firstTextBaseline) {
                    Text("Notes").foregroundStyle(.secondary)
                    TextField("Mic positions, distances, amp settings… (saved in report.json)", text: $m.notes, axis: .vertical)
                        .lineLimit(1...3)
                }
            }
            SaveFolderRow()
        }
    }
}

/// A text field with a menu of common mic names next to it (names become file names).
struct MicNameField: View {
    @Binding var name: String
    var disabled = false
    var body: some View {
        HStack(spacing: 4) {
            TextField("SM57, R121, Room…", text: $name).frame(width: 180).disabled(disabled)
            Menu {
                ForEach(commonMicNames, id: \.self) { n in Button(n) { name = n } }
            } label: { Image(systemName: "chevron.down") }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 26).disabled(disabled)
            .help("Common mic names")
        }
    }
}

// ------------------------------------------------------------------ results
struct ResultsView: View {
    @EnvironmentObject var m: AppModel
    let r: ResultSummary
    var quality: (String, Color) {
        if r.droppedOut { return ("Record again", badColor) }
        if r.warnings.isEmpty { return ("Excellent", goodColor) }
        return (r.warnings.count == 1 ? "Good — 1 thing to check" : "Check these \(r.warnings.count) things", warnColor)
    }
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("RESULTS — \(r.title)").font(.system(size: 15, weight: .semibold)).kerning(0.8)
                    Spacer()
                    Pill(text: quality.0, color: quality.1)
                }
                ForEach(r.warnings, id: \.self) { w in
                    Text(w).padding(.horizontal, 10).padding(.vertical, 7).frame(maxWidth: .infinity, alignment: .leading)
                        .background((r.droppedOut && w == r.warnings.first ? badColor : warnColor).opacity(0.15))
                        .overlay(Rectangle().fill(r.droppedOut && w == r.warnings.first ? badColor : warnColor).frame(width: 3), alignment: .leading)
                }
                if r.droppedOut {
                    HStack {
                        Button("Record again") { m.startCapture() }.buttonStyle(.borderedProminent).tint(lamp)
                            .disabled(m.busy != nil || m.captureProblem != nil)
                        Note("Quit other apps first (browsers, video calls, other audio software).")
                    }
                }
                if !r.referenced { Note("No reference tap was used, so these IRs include the power amp's response.") }
                ForEach(r.polarityNotes, id: \.self) { n in Note("Polarity: " + n, color: .primary) }
                if !r.topFiles.isEmpty {
                    Aside(title: "Load these") {
                        ForEach(r.topFiles, id: \.self) { f in Text(f).font(.system(.callout, design: .monospaced)) }
                        Note("48 kHz, 24-bit, 500 ms. They load in any IR loader, DAW plug-in or modeler. Other formats are in More formats.")
                    }
                }
                DiagnosticsTable(r: r)
                Text("FREQUENCY RESPONSE, 1/6 OCTAVE").font(.caption.weight(.semibold)).kerning(0.8).foregroundStyle(.secondary)
                HStack(spacing: 14) {
                    ForEach(Array(r.names.enumerated()), id: \.offset) { i, n in
                        HStack(spacing: 5) { RoundedRectangle(cornerRadius: 2).fill(micColors[i % micColors.count]).frame(width: 10, height: 10); Text(n) }
                    }
                }
                ResponsePlot(fc: r.curves.fc, curves: r.names.map { r.curves.curves[$0] ?? [] }).frame(height: 300)
                HStack {
                    Button("Show in Finder") { m.revealResult() }.buttonStyle(.borderedProminent).tint(lamp)
                    Button("Re-export…") { m.reexportMessage = nil; m.reexportFolder = r.folder }
                        .help("Make other formats from this capture's raw take, without recording again")
                    Text("\(r.fileCount) IR files, README.txt and report.json in \(r.folder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))")
                        .font(.callout).foregroundStyle(.secondary).lineLimit(2)
                }
            }.padding(8)
        }
    }
}

struct ReexportSheet: View {
    @EnvironmentObject var m: AppModel
    var processing: String? { if case .processing(let t) = m.busy { return t } else { return nil } }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Re-export \(m.reexportFolder?.lastPathComponent ?? "")").font(.title2.weight(.semibold))
            Note("Makes the files again from this capture's raw take, with the choices below. Nothing is recorded. The old generated files go to the Trash; the raw take and report history stay.")
            TargetsPicker()
            AdvancedOutput()
            if let msg = m.reexportMessage { ErrorNote(msg) }
            if let t = processing { HStack { ProgressView().controlSize(.small); Text(t + "…").foregroundStyle(.secondary) } }
            HStack {
                Spacer()
                Button("Cancel") { m.reexportFolder = nil }.keyboardShortcut(.cancelAction)
                Button("Re-export") { if let f = m.reexportFolder { m.reexport(f) } }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).tint(lamp)
                    .disabled(m.busy != nil || m.outputProblem != nil)
            }
        }
        .padding(24).frame(width: 600)
    }
}

struct DiagnosticsTable: View {
    let r: ResultSummary
    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
            GridRow {
                ForEach(["CHANNEL", "RECORDED PEAK", "NOISE FLOOR", "USABLE TAIL", "DISTORTION", "ARRIVAL"], id: \.self) {
                    Text($0).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
            Divider().gridCellUnsizedAxes(.horizontal)
            ForEach(Array(r.diagnostics.enumerated()), id: \.offset) { i, item in
                let d = item.diag, isRef = item.label == "reference"
                GridRow {
                    HStack(spacing: 6) {
                        if !isRef { RoundedRectangle(cornerRadius: 2).fill(micColors[(r.names.firstIndex(of: item.label) ?? i) % micColors.count]).frame(width: 10, height: 10) }
                        Text(isRef ? "Reference" : item.label)
                    }
                    Pill(text: String(format: "%.1f dBFS", d.recordingPeakDBFS),
                         color: d.recordingPeakDBFS > -0.3 ? badColor : d.recordingPeakDBFS < -30 ? warnColor : goodColor)
                    Text(d.noiseFloorDB.map { String(format: "%.0f dB", $0) } ?? "—").monospacedDigit()
                    Text(d.tailAboveNoiseMs.map { String(format: "%.0f ms", $0) } ?? "—").monospacedDigit()
                    if isRef { Text("—") } else if let w = d.worstHarmonic {
                        Pill(text: "H\(w.n) \(Int(w.db.rounded())) dB", color: w.db > -30 ? badColor : w.db > -40 ? warnColor : goodColor)
                    } else { Pill(text: "below noise", color: goodColor) }
                    Text(isRef ? "—" : (d.arrivalMs.map { String(format: "%.2f ms", $0) } ?? "—") + (r.referenced || isRef ? "" : " (relative)")).monospacedDigit()
                }
            }
        }
    }
}

struct ResponsePlot: View {
    let fc: [Double]
    let curves: [[Double]]
    var body: some View {
        Canvas { ctx, size in
            let L = 44.0, R = 10.0, T = 8.0, B = 24.0
            let W = size.width, H = size.height
            var mx = -Double.infinity
            for c in curves { for (i, v) in c.enumerated() where fc[i] >= 40 && fc[i] <= 12000 { mx = max(mx, v) } }
            if !mx.isFinite { mx = 0 }
            let top = (mx / 10).rounded(.up) * 10 + 5, bot = top - 60
            func X(_ f: Double) -> Double { L + log10(f / 20) / log10(1000) * (W - L - R) }
            func Y(_ v: Double) -> Double { T + (top - max(bot, min(top, v))) / (top - bot) * (H - T - B) }
            ctx.fill(Path(CGRect(x: L, y: T, width: W - L - R, height: H - T - B)), with: .color(.secondary.opacity(0.08)))
            let grid = GraphicsContext.Shading.color(.secondary.opacity(0.25))
            for f in [20.0, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000] {
                var p = Path(); p.move(to: CGPoint(x: X(f), y: T)); p.addLine(to: CGPoint(x: X(f), y: H - B))
                ctx.stroke(p, with: grid, lineWidth: 1)
                let label = f >= 1000 ? "\(Int(f / 1000))k" : "\(Int(f))"
                ctx.draw(Text(label).font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary),
                         at: CGPoint(x: X(f), y: H - B + 12), anchor: f == 20 ? .leading : f == 20000 ? .trailing : .center)
            }
            var v = bot + 5
            while v <= top {
                var p = Path(); p.move(to: CGPoint(x: L, y: Y(v))); p.addLine(to: CGPoint(x: W - R, y: Y(v)))
                ctx.stroke(p, with: grid, lineWidth: 1)
                ctx.draw(Text("\(Int(v - top + 5))").font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary),
                         at: CGPoint(x: L - 6, y: Y(v)), anchor: .trailing)
                v += 10
            }
            for (k, c) in curves.enumerated() where c.count == fc.count {
                var p = Path()
                for (i, f) in fc.enumerated() {
                    let pt = CGPoint(x: X(f), y: Y(c[i]))
                    if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                }
                ctx.stroke(p, with: .color(micColors[k % micColors.count]), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
            }
            ctx.draw(Text("dB").font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary), at: CGPoint(x: 4, y: T + 6), anchor: .leading)
        }
    }
}
#endif
