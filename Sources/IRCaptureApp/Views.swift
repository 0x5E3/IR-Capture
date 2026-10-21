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
        WindowGroup("IR Capture") {
            ContentView().environmentObject(model)
                .frame(minWidth: 760, minHeight: 640)
        }
        .defaultSize(width: 900, height: 940)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}

struct ContentView: View {
    @EnvironmentObject var m: AppModel
    @State private var tab = 0
    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text("Capture with the app").tag(0)
                Text("Use Logic recordings").tag(1)
            }
            .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 420).padding(.vertical, 12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if tab == 0 { CaptureTab() } else { LogicTab() }
                    if let r = m.result { ResultsView(r: r) }
                    Text("Method: exponential sine sweeps (Farina), averaged, with harmonic distortion windowed out. With a reference tap each IR is the speaker-terminal voltage to microphone response. IR Capture \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev").")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(22).frame(maxWidth: 880, alignment: .leading).frame(maxWidth: .infinity)
            }
        }
        .disabled(false)
    }
}

// ------------------------------------------------------------------ building blocks
struct Step<Content: View>: View {
    let n: Int
    let title: String
    var subtitle: String? = nil
    @ViewBuilder let content: Content
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(n)").font(.system(size: 14, weight: .bold)).foregroundStyle(.black)
                        .frame(width: 24, height: 24).background(Circle().fill(lamp))
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

struct Note: View {
    let text: String
    var color: Color = .secondary
    init(_ t: String, color: Color = .secondary) { text = t; self.color = color }
    var body: some View { Text(text).font(.callout).foregroundStyle(color).fixedSize(horizontal: false, vertical: true) }
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

struct BusyLine: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        if let b = m.busy {
            VStack(alignment: .leading, spacing: 6) {
                if case .recording(let p) = b { ProgressView(value: p).tint(lamp) } else { ProgressView().controlSize(.small) }
                HStack {
                    Text(b.text).foregroundStyle(.secondary)
                    Spacer()
                    if case .recording = b { Button("Stop") { m.cancelCapture() } }
                }
            }
        }
        if let e = m.errorText { Note(e, color: badColor) }
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

struct LevelPicker: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        Picker("Sweep level", selection: $m.level) {
            ForEach([-6.0, -12, -18, -24], id: \.self) { Text("\(Int($0)) dBFS").tag($0) }
        }.frame(width: 200)
    }
}

struct OutputOptions: View {
    @EnvironmentObject var m: AppModel
    func toggle<T: Hashable>(_ set: Binding<Set<T>>, _ v: T) -> Binding<Bool> {
        Binding(get: { set.wrappedValue.contains(v) }, set: { on in if on { set.wrappedValue.insert(v) } else { set.wrappedValue.remove(v) } })
    }
    var body: some View {
        DisclosureGroup("Output files") {
            VStack(alignment: .leading, spacing: 12) {
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
                Note("“Keep mic timing” trims every mic by the same amount and gives them one shared gain, so they blend the way the real mics did. “Trim each mic” starts each file at its own first arrival and normalizes it on its own. Level is matched across sample rates.")
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

struct ReferenceAside: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("REFERENCE TAP (RECOMMENDED)").font(.caption.weight(.semibold)).kerning(0.8).foregroundStyle(.secondary)
            Note("Pad the voltage across the speaker terminals by about 20 dB (for example 10 kΩ in series, 1.1 kΩ to ground) and record it on its own line input. The IRs then come out as speaker, mic and room only, whatever power amp you use.", color: .primary)
            Note("If the amp's speaker output is bridged (neither terminal is ground), or the tap brings in hum, use an isolation transformer or a balanced input. Without a reference the IRs still work, but they include the power amp's own response.", color: .primary)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.1)))
    }
}

// ------------------------------------------------------------------ Capture tab
struct CaptureTab: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Step(n: 1, title: "Interface and inputs", subtitle: "Pick the interface, the output that feeds the power amp, and what's plugged into each input.") {
                if m.duplexDevices.isEmpty {
                    Note("No audio interface with both inputs and outputs was found. Connect it, then click Refresh.", color: badColor)
                }
                HStack(spacing: 16) {
                    Picker("Interface", selection: $m.deviceUID) {
                        ForEach(m.duplexDevices) { d in Text("\(d.name)  (\(d.inputChannels) in / \(d.outputChannels) out)").tag(d.uid) }
                    }.frame(maxWidth: 420)
                    Button("Refresh") { m.refreshDevices() }
                }
                if let dev = m.device {
                    HStack(spacing: 16) {
                        Picker("Sample rate", selection: $m.rate) {
                            ForEach(m.deviceRates, id: \.self) { Text("\(rateTag($0).dropLast()) kHz").tag($0) }
                        }.frame(width: 200)
                        Picker("Output to the amp", selection: $m.outChannel) {
                            ForEach(0..<dev.outputChannels, id: \.self) { Text("Output \($0 + 1)").tag($0) }
                        }.frame(width: 230)
                        LevelPicker()
                    }
                    Note("Use the highest sample rate your interface does well; every other rate is made from this one capture. IR Capture switches the interface to this rate when it runs.")
                    InputsGrid()
                }
                SweepSettings()
            }

            Step(n: 2, title: "Set the levels", subtitle: "Short sweeps play on a loop so you can set each preamp.") {
                Checklist(items: [
                    "Mute the studio monitors so the room mic only hears the cab. Wear ear protection: the sweeps play at full amp volume.",
                    "Set the amp to the loudness you want, then click Start level check.",
                    "Turn each preamp until its line says OK (the sweep peaks near −6 dBFS). Nothing should say CLIP.",
                    "If distortion shows orange or red, lower the sweep level in step 1 or the amp volume. An IR is linear, so pushing the speaker gains nothing.",
                ])
                HStack {
                    Button(m.levelRunning ? "Stop level check" : "Start level check") { m.toggleLevelCheck() }
                        .buttonStyle(.borderedProminent).tint(m.levelRunning ? .secondary : lamp)
                        .disabled(m.busy != nil || m.device == nil)
                    if m.levelRunning { ProgressView().controlSize(.small); Text("Playing short sweeps…").foregroundStyle(.secondary) }
                }
                if let e = m.levelError { Note(e, color: badColor) }
                if !m.levelReadings.isEmpty { LevelTable(readings: m.levelReadings) }
            }

            Step(n: 3, title: "Capture", subtitle: String(format: "One button. It plays %d sweeps (about %.0f s), records every input, and saves finished IRs.", m.nSweeps, m.signalSeconds)) {
                CaptureNameFields()
                OutputOptions()
                HStack {
                    Button("Capture") { m.startCapture() }
                        .buttonStyle(.borderedProminent).tint(lamp).controlSize(.large)
                        .disabled(m.busy != nil || m.captureProblem != nil)
                    if let p = m.captureProblem, m.busy == nil { Note(p, color: warnColor) }
                }
                BusyLine()
            }
        }
    }
}

struct InputsGrid: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                GridRow {
                    Text("INPUT").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text("USE").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text("MIC NAME").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                ForEach($m.inputs) { $row in
                    GridRow {
                        Text("Input \(row.id + 1)").monospacedDigit()
                        Picker("", selection: Binding(get: { row.role }, set: { m.setRole($0, for: row.id) })) {
                            ForEach(Role.allCases) { Text($0.label).tag($0) }
                        }.labelsHidden().frame(width: 150)
                        TextField("SM57, R121, Room…", text: $row.name).frame(width: 220).disabled(row.role != .mic)
                    }
                    .foregroundStyle(row.role == .off ? .secondary : .primary)
                }
            }
            Note("Name each mic (the name goes into the IR file names). Mark the input with the speaker-terminal tap as Reference tap.")
            ReferenceAside()
        }
    }
}

struct LevelTable: View {
    let readings: [LevelReading]
    func meterColor(_ r: LevelReading) -> Color { r.clipped ? badColor : abs(r.changeDB) <= 3 ? goodColor : warnColor }
    func advice(_ r: LevelReading) -> (String, Color) {
        if r.clipped { return ("CLIP — turn down", badColor) }
        let d = r.changeDB
        if abs(d) <= 3 { return ("OK", goodColor) }
        return (d > 0 ? "Turn up \(Int(d.rounded())) dB" : "Turn down \(Int((-d).rounded())) dB", warnColor)
    }
    func distColor(_ v: Double) -> Color { v > -30 ? badColor : v > -40 ? warnColor : goodColor }
    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
            ForEach(readings) { r in
                GridRow {
                    Text(r.label).bold()
                    GeometryReader { g in
                        let frac = max(0, min(1, (r.peakDBFS + 60) / 60))
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(0.15))
                            RoundedRectangle(cornerRadius: 3).fill(meterColor(r)).frame(width: g.size.width * frac)
                            Rectangle().fill(Color.primary.opacity(0.6)).frame(width: 2).offset(x: g.size.width * 0.9 - 1)
                        }
                    }.frame(width: 220, height: 12)
                    Text(String(format: "%.1f dBFS", r.peakDBFS)).monospacedDigit()
                    let a = advice(r)
                    Pill(text: a.0, color: a.1)
                    if r.label == "Reference tap" {
                        Text("")
                    } else {
                        HStack(spacing: 6) {
                            Pill(text: String(format: "H2 %.0f", r.h2), color: distColor(r.h2))
                            Pill(text: String(format: "H3 %.0f", r.h3), color: distColor(r.h3))
                        }
                    }
                }
            }
        }
    }
}

// ------------------------------------------------------------------ Logic tab
struct LogicTab: View {
    @EnvironmentObject var m: AppModel
    @State private var dropping = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Step(n: 1, title: "Test signal", subtitle: "Save the sweeps to play from Logic. Pick the sample rate your Logic project will run at.") {
                HStack(spacing: 16) {
                    Picker("Capture rate", selection: $m.logicRate) {
                        ForEach(CoreAudioHelper.captureRates, id: \.self) { Text("\(rateTag($0).dropLast()) kHz").tag($0) }
                    }.frame(width: 200)
                    LevelPicker()
                }
                SweepSettings()
                HStack {
                    Button("Save test signal…") { m.saveTestSignal() }.buttonStyle(.borderedProminent).tint(lamp)
                    Button("Load settings from a test signal…") { m.loadSignalSettings() }
                }
                Note(m.signalMessage ?? "Keep these settings when you process the recording in step 3. The app remembers them.")
            }

            Step(n: 2, title: "Record in Logic") {
                Checklist(items: [
                    "Set the Logic project to the capture rate above. Drag the sweep WAV onto a new audio track at bar 1.",
                    "Send that track only to the interface output that feeds the power amp. Mute the studio monitors so the room mic doesn't hear them.",
                    "Make one audio track per mic and one for the reference tap if you have it. Name each track after its mic (SM57, R121, Room…) and name the reference track “Ref”; the exported files take these names. Record-enable them all, with input monitoring off and no plug-ins.",
                    "Play the sweep track and watch the meters. Set each mic preamp so the loudest point of the sweep peaks around −6 dBFS. Nothing should clip.",
                    "Record one full pass. Keep the room quiet and don't touch the mics.",
                    "Choose File › Export › All Tracks as Audio Files. Pick WAV, 24-bit or 32-bit float, at the project sample rate, with Normalize off. Leave the faders at 0 dB.",
                ])
                ReferenceAside()
            }

            Step(n: 3, title: "Make the IRs", subtitle: "Add the exported WAV files, check the names, and click Make IRs.") {
                VStack(spacing: 6) {
                    Text("Drag the exported WAV files here").bold()
                    Button("or choose them…") { m.chooseLogicFiles() }.buttonStyle(.link)
                    Text("If the sweep track's file comes along too, that's fine; it's skipped automatically.").font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 18)
                .background(RoundedRectangle(cornerRadius: 6).strokeBorder(dropping ? lamp : Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 2, dash: [6])))
                .onDrop(of: [.fileURL], isTargeted: $dropping) { providers in
                    for p in providers {
                        _ = p.loadObject(ofClass: URL.self) { url, _ in
                            if let url { DispatchQueue.main.async { m.addLogicFiles([url]) } }
                        }
                    }
                    return true
                }
                if let msg = m.logicMessage { Note(msg, color: badColor) }
                if !m.logicChannels.isEmpty { LogicGrid() }
                CaptureNameFields()
                OutputOptions()
                HStack {
                    Button("Make IRs") { m.processLogic() }
                        .buttonStyle(.borderedProminent).tint(lamp).controlSize(.large)
                        .disabled(m.busy != nil || m.logicProblem != nil)
                    if let p = m.logicProblem, m.busy == nil, !m.logicChannels.isEmpty { Note(p, color: warnColor) }
                }
                BusyLine()
            }
        }
    }
}

struct LogicGrid: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
            GridRow {
                Text("FILE").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text("MIC NAME").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text("ROLE").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text("")
            }
            ForEach($m.logicChannels) { $c in
                GridRow {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.label).font(.system(.callout, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                        Text(c.meta).font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: 280, alignment: .leading)
                    TextField("", text: $c.name).frame(width: 180).disabled(c.role != .mic)
                    Picker("", selection: Binding(get: { c.role }, set: { m.setLogicRole($0, for: c.id) })) {
                        Text("Mic").tag(Role.mic); Text("Reference tap").tag(Role.ref); Text("Skip").tag(Role.off)
                    }.labelsHidden().frame(width: 150)
                    if c.channel == 0 {
                        Button { m.removeLogicFile(c.url) } label: { Image(systemName: "xmark.circle") }.buttonStyle(.borderless).help("Remove this file")
                    } else { Text("") }
                }
            }
        }
    }
}

// ------------------------------------------------------------------ results
struct ResultsView: View {
    @EnvironmentObject var m: AppModel
    let r: ResultSummary
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("RESULTS — \(r.title)").font(.system(size: 15, weight: .semibold)).kerning(0.8)
                    Spacer()
                    if r.warnings.isEmpty { Pill(text: "Capture looks clean", color: goodColor) }
                    else { Pill(text: r.warnings.count == 1 ? "1 thing to check" : "\(r.warnings.count) things to check", color: warnColor) }
                }
                if !r.referenced { Note("No reference tap was used, so these IRs include the power amp's response.") }
                ForEach(r.warnings, id: \.self) { w in
                    Text(w).padding(.horizontal, 10).padding(.vertical, 7).frame(maxWidth: .infinity, alignment: .leading)
                        .background(warnColor.opacity(0.15)).overlay(Rectangle().fill(warnColor).frame(width: 3), alignment: .leading)
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
                    Text("\(r.fileCount) IR files plus report.json in \(r.folder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))")
                        .font(.callout).foregroundStyle(.secondary).lineLimit(2)
                }
            }.padding(8)
        }
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
                        Text(isRef ? "Reference tap" : item.label)
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
