#if os(macOS)
import SwiftUI
import IRCaptureCore

/// Cab IR: Record here is the main path; Import DAW recordings is the secondary route.
struct CabJob: View {
    @EnvironmentObject var m: AppModel
    var connected: Bool { m.device != nil && AppModel.namesProblem(m.mics.map(\.name)) == nil && (m.refSource == .none || m.refInput != nil) }
    var levelsDone: Bool {
        !m.levelReadings.isEmpty && m.levelReadings.allSatisfy { !$0.clipped && (abs($0.changeDB) <= 3 || $0.label == "Reference") }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if m.cabImport {
                HStack {
                    Button { m.cabImport = false } label: { Label("Record here", systemImage: "chevron.left") }
                    Text("Import DAW recordings").font(.headline)
                }
                CabImportSteps()
            } else {
                JobStepper(steps: [("Connect", connected), ("Set levels", levelsDone), ("Capture", m.result != nil), ("Results", m.result != nil)])
                CabConnectStep(done: connected)
                CabLevelStep(done: levelsDone)
                CabCaptureStep()
                GroupBox {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Recorded in a DAW instead?").bold()
                            Note("Play the test signal from Logic, Reaper, Ableton, Pro Tools or GarageBand. Record the mics in the DAW. Import the files here.")
                        }
                        Spacer()
                        Button("Import DAW recordings…") { m.cabImport = true }
                        Button("Re-export a past capture…") { m.chooseReexportFolder() }
                    }.padding(6)
                }
            }
        }
    }
}

// ------------------------------------------------------------------ 1. Connect
struct CabConnectStep: View {
    @EnvironmentObject var m: AppModel
    let done: Bool
    var body: some View {
        Step(n: 1, title: "Connect", subtitle: "Wire the rig as shown. Then set the use of each input.", done: done) {
            WiringDiagram(wiring: m.refSource == .none ? .cabNoRef : .cabRef)
            Checklist(items: [
                "Interface output → amp FX return (power amp in) or clean power amp → cab. Do not use the guitar input. The preamp distorts the sweeps and the IR is incorrect.",
                "Set the amp master low to start. The remaining levels are set in the level check.",
                "Place the mics on the cab and connect them to the interface mic inputs. Mute the studio monitors. Otherwise the room mic records them.",
            ])
            InterfaceRow(outputLabel: "Output to the amp", output: $m.outChannel)
            if m.device != nil {
                InputsGrid()
                IdleSignalChips()
                ReferenceChooser()
                CabAdvanced()
            }
        }
    }
}

/// Interface picker (it updates by itself when an interface is plugged in) plus the output picker.
struct InterfaceRow: View {
    @EnvironmentObject var m: AppModel
    let outputLabel: String
    @Binding var output: Int
    var showRate = true
    var body: some View {
        if m.duplexDevices.isEmpty {
            Note("No audio interface with both inputs and outputs is connected. Connect the interface and switch it on. It is listed here automatically.", color: badColor)
            Button("Open Audio MIDI Setup") { CoreAudioHelper.openAudioMIDISetup() }
                .help("If inputs and outputs are on two devices, combine them into an aggregate device in Audio MIDI Setup")
        }
        HStack(spacing: 16) {
            Picker("Interface", selection: $m.deviceUID) {
                ForEach(m.duplexDevices) { d in Text("\(d.name)  (\(d.inputChannels) in / \(d.outputChannels) out)").tag(d.uid) }
            }.frame(maxWidth: 420)
            if let dev = m.device {
                Picker(outputLabel, selection: $output) {
                    ForEach(0..<dev.outputChannels, id: \.self) { Text("Output \($0 + 1)").tag($0) }
                }.frame(width: 260)
            }
        }
        .disabled(m.audioActive)
        .help(m.audioActive ? "Stop the level check or recording to change these" : "")
        if showRate, m.device != nil {
            Note("Recording rate: \(rateTag(m.captureRate).dropLast()) kHz\(m.rateChoice == 0 ? " (highest rate of this interface; all other rates are made from this capture)" : ""). The interface is reset to its previous rate afterwards.")
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
                        if row.role == .ref {
                            HStack { Pill(text: "Reference", color: lamp); Button("Not used") { m.setRole(.off, for: row.id) }.buttonStyle(.link) }
                                .frame(width: 150, alignment: .leading)
                            Text("")
                        } else {
                            Picker("", selection: Binding(get: { row.role }, set: { m.setRole($0, for: row.id) })) {
                                Text("Not used").tag(Role.off); Text("Mic").tag(Role.mic)
                            }.labelsHidden().frame(width: 150)
                            MicNameField(name: $row.name, disabled: row.role != .mic)
                        }
                    }
                    .foregroundStyle(row.role == .off ? .secondary : .primary)
                }
            }
            Note("Enter a name for each mic. The name is used in the file names.")
        }
    }
}

/// "Signal on Input 3 — use it as a mic?" for unused inputs that showed signal in the level check.
struct IdleSignalChips: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        ForEach(m.idleSignals) { r in
            HStack(spacing: 10) {
                Image(systemName: "waveform").foregroundStyle(lamp)
                Text("Signal on Input \(r.channel + 1) (\(Int(r.peakDBFS.rounded())) dBFS). Use it?")
                Button("As a mic") { m.setRole(.mic, for: r.channel) }
                if m.refCandidate == r.channel || m.refInput == nil {
                    Button(m.refCandidate == r.channel ? "As the reference (detected)" : "As the reference") { m.setRefInput(r.channel) }
                }
            }
            .padding(8).background(RoundedRectangle(cornerRadius: 6).fill(lamp.opacity(0.12)))
        }
        if let c = m.refCandidate, m.refInput == nil, !m.idleSignals.contains(where: { $0.channel == c }) {
            HStack(spacing: 10) {
                Image(systemName: "lightbulb").foregroundStyle(lamp)
                Text("Input \(c + 1) is probably a reference tap. Its signal arrives first and contains no cab or room sound.")
                Button("Use it as the reference") { m.setRefInput(c) }
            }
            .padding(8).background(RoundedRectangle(cornerRadius: 6).fill(lamp.opacity(0.12)))
        }
    }
}

/// "Where's your reference?" (P0.6)
struct ReferenceChooser: View {
    @EnvironmentObject var m: AppModel
    func blurb(_ s: RefSource) -> String {
        switch s {
        case .none: return "The IR includes the power amp response, as in most commercial IRs. Recommended for a first capture."
        case .loadBox: return "A load box or attenuator with a line out (speaker-through), connected between amp and cab. One cable to a line input."
        case .tap: return "A Swell reference tap, or a 20 dB pad across the speaker terminals, into a line input."
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("REFERENCE SOURCE").font(.caption.weight(.semibold)).kerning(0.8).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 10) {
                ForEach(RefSource.allCases) { s in
                    Button { m.refSource = s } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: s == .none ? "speaker.wave.2" : s == .loadBox ? "rectangle.connected.to.line.below" : "cable.connector")
                                Text(s.title).bold()
                                Spacer()
                                if m.refSource == s { Image(systemName: "checkmark.circle.fill").foregroundStyle(lamp) }
                            }
                            Text(blurb(s)).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(10).frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(m.refSource == s ? lamp.opacity(0.12) : Color.secondary.opacity(0.06)))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(m.refSource == s ? lamp : Color.secondary.opacity(0.25)))
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
            if m.refSource != .none, let dev = m.device {
                HStack {
                    Picker("Connected to", selection: Binding(get: { m.refInput ?? -1 }, set: { m.setRefInput($0 < 0 ? nil : $0) })) {
                        Text("Choose…").tag(-1)
                        ForEach(0..<dev.inputChannels, id: \.self) { Text("Input \($0 + 1)").tag($0) }
                    }.frame(width: 260)
                    Button("Reference tap help…") { m.helpPage = .reference }.buttonStyle(.link)
                }
                if m.refSource == .loadBox {
                    Note("Use the line out only if its signal is the amp speaker voltage. Turn off any cab simulation or EQ on the line out. If attenuation is applied before the speaker-through, the line out does not match the speaker signal. Set the attenuation to bypass (or 0 dB) for the capture.", color: .primary)
                } else {
                    Note("If the amp speaker output is bridged (no grounded terminal), or if there is hum on the tap, use an isolated tap or a balanced input. A parts list is in Help › The Reference Tap.", color: .primary)
                }
            } else {
                Note("With a tube amp and no reference, the IR includes about 5 dB of the speaker impedance peak around resonance. Most commercial IRs are made this way.")
            }
        }
    }
}

struct CabAdvanced: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        DisclosureGroup("Advanced") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 18) {
                    Picker("Sample rate", selection: $m.rateChoice) {
                        Text("Automatic (\(rateTag(m.device.map(CoreAudioHelper.bestRate) ?? 96000).dropLast()) kHz)").tag(0)
                        ForEach(m.deviceRates, id: \.self) { Text("\(rateTag($0).dropLast()) kHz").tag($0) }
                    }.frame(width: 260)
                    Picker("Sweep level", selection: $m.levelChoice) {
                        Text("Automatic").tag(0.0)
                        ForEach([-6.0, -12, -18, -24], id: \.self) { Text("\(Int($0)) dBFS").tag($0) }
                    }.frame(width: 220)
                    Button("Open Audio MIDI Setup") { CoreAudioHelper.openAudioMIDISetup() }
                }
                Note("Automatic sweep level: starts at −18 dBFS and is raised in steps while speaker distortion stays low. It is reduced if distortion increases.")
                SweepSettings()
            }.padding(.top, 8)
        }
    }
}

// ------------------------------------------------------------------ 2. Set levels
struct CabLevelStep: View {
    @EnvironmentObject var m: AppModel
    let done: Bool
    var body: some View {
        Step(n: 2, title: "Set levels", subtitle: "Room noise is measured, the sweep level is set, and short sweeps are looped while each preamp is adjusted.", done: done) {
            Checklist(items: [
                "Wear ear protection. The sweeps are played at full amp volume.",
                "Click Check levels. Keep the room quiet for the first 2 seconds during the noise measurement.",
                m.levelChoice == 0 ? "Wait for “Sweep level set”. Then adjust each preamp until its row shows OK. No row may show CLIP."
                                   : "Adjust each preamp until its row shows OK (sweep peak near −6 dBFS). No row may show CLIP.",
                "If distortion is orange or red, lower the amp volume. An IR is linear. Higher speaker drive does not improve it.",
            ])
            HStack {
                Button(m.levelRunning ? "Stop" : "Check levels") { m.toggleLevelCheck() }
                    .buttonStyle(.borderedProminent).tint(m.levelRunning ? .secondary : lamp)
                    .disabled(m.busy != nil || m.device == nil)
                if m.levelRunning { ProgressView().controlSize(.small); Text(m.levelPhase ?? "").foregroundStyle(.secondary) }
                Spacer()
                if m.levelChoice == 0 && (m.levelRunning || !m.levelReadings.isEmpty) {
                    Pill(text: m.autoLevelSettled ? "Sweep level set (\(Int(m.autoLevel)) dBFS)" : "Setting sweep level (\(Int(m.autoLevel)) dBFS)",
                         color: m.autoLevelSettled ? goodColor : warnColor)
                }
            }
            if let e = m.levelError { ErrorNote(e) }
            if !m.levelReadings.isEmpty { LevelTable(readings: m.levelReadings) }
        }
    }
}

struct LevelTable: View {
    @EnvironmentObject var m: AppModel
    let readings: [LevelReading]
    func meterColor(_ r: LevelReading) -> Color { r.clipped ? badColor : abs(r.changeDB) <= 3 ? goodColor : warnColor }
    func advice(_ r: LevelReading) -> (String, Color) {
        if r.clipped { return ("CLIP: turn down", badColor) }
        if r.peakDBFS < -60 { return ("No signal: check cable", badColor) }
        let d = r.changeDB
        if abs(d) <= 3 { return ("OK", goodColor) }
        return (d > 0 ? "Turn up \(Int(d.rounded())) dB" : "Turn down \(Int((-d).rounded())) dB", warnColor)
    }
    func distColor(_ v: Double) -> Color { v > -30 ? badColor : v > -40 ? warnColor : goodColor }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                        }.frame(width: 200, height: 12)
                        Text(String(format: "%.1f dBFS", r.peakDBFS)).monospacedDigit()
                        let a = advice(r)
                        Pill(text: a.0, color: a.1)
                        if r.label == "Reference" {
                            Text("")
                        } else {
                            HStack(spacing: 6) {
                                Pill(text: String(format: "H2 %.0f", r.h2), color: distColor(r.h2))
                                Pill(text: String(format: "H3 %.0f", r.h3), color: distColor(r.h3))
                            }
                        }
                        if let n = m.noise[r.channel] {
                            Pill(text: m.noiseNote(r.channel) == nil ? "quiet" : "noisy \(Int(n.rounded()))", color: m.noiseNote(r.channel) == nil ? goodColor : warnColor)
                                .help(m.noiseNote(r.channel) ?? String(format: "Room noise %.0f dBFS", n))
                        } else { Text("") }
                    }
                }
            }
            ForEach(readings.compactMap { m.noiseNote($0.channel) }, id: \.self) { Note($0, color: warnColor) }
        }
    }
}

// ------------------------------------------------------------------ 3. Capture
struct CabCaptureStep: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        Step(n: 3, title: "Capture", subtitle: String(format: "Click Capture. %d sweeps are played (about %.0f s), all inputs are recorded, and the finished IRs are saved.", m.nSweeps, m.signalSeconds),
             done: m.result != nil) {
            CaptureNameFields()
            TargetsPicker()
            AdvancedOutput()
            PreflightList(items: m.preflight)
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

struct PreflightList: View {
    let items: [PreflightItem]
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("BEFORE YOU CAPTURE").font(.caption.weight(.semibold)).kerning(0.8).foregroundStyle(.secondary)
            ForEach(items) { i in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: i.level == .ok ? "checkmark.circle.fill" : i.level == .warn ? "exclamationmark.triangle.fill" : "xmark.octagon.fill")
                        .foregroundStyle(i.level == .ok ? goodColor : i.level == .warn ? warnColor : badColor)
                    Text(i.text).fixedSize(horizontal: false, vertical: true)
                }.font(.callout)
            }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.08)))
    }
}

// ------------------------------------------------------------------ Import DAW recordings
struct CabImportSteps: View {
    @EnvironmentObject var m: AppModel
    @State private var dropping = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Step(n: 1, title: "Test signal", subtitle: "Save the sweeps for playback from the DAW. Select the sample rate of the DAW project.") {
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
                Note(m.signalMessage ?? "Use the same settings when the recordings are added in step 3. The settings are saved.")
            }

            Step(n: 2, title: "Record in your DAW", subtitle: "The steps apply to any DAW. Menu names below are from Logic.") {
                WiringDiagram(wiring: .cabRef, compact: true)
                Checklist(items: [
                    "Set the project to the capture rate above. Drag the sweep WAV onto a new audio track at the start (bar 1 in Logic).",
                    "Route that track only to the interface output connected to the amp FX return or a clean power amp (not the guitar input). Mute the studio monitors. Otherwise the room mic records them.",
                    "Create one audio track per mic, and one for the reference if used. Name each track after its mic (SM57, R121, Room…). Name the reference track “Ref”. The exported files use these names. Record-enable all tracks. Turn input monitoring off. Use no plug-ins.",
                    "Play the sweep track and watch the meters. Set each mic preamp so the sweep peaks at about −6 dBFS. No track may clip.",
                    "Record one full pass. Keep the room quiet. Do not move the mics.",
                    "Export every track as a WAV (in Logic: File › Export › All Tracks as Audio Files), 24-bit or 32-bit float, at the project rate, with Normalize off and faders at 0 dB.",
                ])
            }

            Step(n: 3, title: "Make the IRs", subtitle: "Add the exported WAV files, check the names, and click Make IRs.") {
                VStack(spacing: 6) {
                    Text("Drag the exported WAV files here").bold()
                    Button("or choose them…") { m.chooseLogicFiles() }.buttonStyle(.link)
                    Text("If the sweep track file is included, it is skipped automatically.").font(.callout).foregroundStyle(.secondary)
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
                if let msg = m.logicMessage { ErrorNote(msg) }
                if !m.logicChannels.isEmpty { LogicGrid() }
                CaptureNameFields()
                TargetsPicker()
                AdvancedOutput()
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
                    MicNameField(name: $c.name, disabled: c.role != .mic)
                    Picker("", selection: Binding(get: { c.role }, set: { m.setLogicRole($0, for: c.id) })) {
                        Text("Mic").tag(Role.mic); Text("Reference").tag(Role.ref); Text("Skip").tag(Role.off)
                    }.labelsHidden().frame(width: 130)
                    if c.channel == 0 {
                        Button { m.removeLogicFile(c.url) } label: { Image(systemName: "xmark.circle") }.buttonStyle(.borderless).help("Remove this file")
                    } else { Text("") }
                }
            }
        }
    }
}
#endif
