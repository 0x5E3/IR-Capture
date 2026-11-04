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
                HStack(spacing: 12) {
                    Button("‹ Record here") { m.cabImport = false }.buttonStyle(KeyButtonStyle(key: "‹ Record here"))
                    Engraved("Import DAW recordings", size: 15)
                }
                CabImportSteps()
            } else {
                JobStepper(steps: [("Connect", connected), ("Set levels", levelsDone), ("Capture", m.result != nil), ("Results", m.result != nil)])
                CabConnectStep(done: connected)
                if let d = TapePieces.deck {
                    // Phase 7: the reel deck replaces the Set levels and Capture panels. The capture's name and files
                    // come first, the guidance beside the deck, the meters under it.
                    CabFilesStep()
                    HStack(alignment: .top, spacing: 16) {
                        Checklist(items: levelSteps, style: PaperStyle(stock: .manila, ring: true))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        PreflightList(items: m.preflight).frame(width: 300)
                    }
                    .id("machine")
                    ReelDeck(d: d).padding(.top, 4)
                    CabDeckStatus()
                    if !m.levelReadings.isEmpty { LevelTable(readings: m.levelReadings) }
                } else {
                    CabLevelStep(done: levelsDone)
                    CabCaptureStep()
                }
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Engraved("Recorded in a DAW instead?", size: 12)
                        Note("Play the test signal from Logic, Reaper, Ableton, Pro Tools or GarageBand. Record the mics in the DAW. Import the files here.")
                    }
                    Spacer()
                    Button("Import DAW recordings…") { m.cabImport = true }.buttonStyle(KeyButtonStyle(key: "Import DAW recordings…"))
                    Button("Re-export a past capture…") { m.chooseReexportFolder() }.buttonStyle(KeyButtonStyle(key: "Re-export a past capture…"))
                }
                .onPanel(padding: 16)
            }
        }
    }
}

extension CabJob {
    var levelSteps: [String] {
        [
            "Wear ear protection. The sweeps are played at full amp volume.",
            "Click Check levels. Keep the room quiet for the first 2 seconds during the noise measurement.",
            m.levelChoice == 0 ? "Wait for “Sweep level set”. Then adjust each preamp until its meter shows OK. No meter may show CLIP."
                               : "Adjust each preamp until its meter shows OK (sweep peak near −6 dBFS). No meter may show CLIP.",
            "If distortion is orange or red, lower the amp volume. An IR is linear. Higher speaker drive does not improve it.",
            "Click Capture. The level check is stopped automatically.",
        ]
    }
}

/// The capture's name and the files to make (was part of the Capture panel; the deck has the Capture key).
struct CabFilesStep: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        Step(title: "Capture name and files", subtitle: "Name the capture and choose the formats. The IRs are saved in a folder with this name.",
             done: !m.captureName.isEmpty) {
            CaptureNameFields()
            TargetsPicker()
            AdvancedOutput()
        }
    }
}

/// Under the deck: what the level check or the capture is doing, the sweep level, and any problem.
struct CabDeckStatus: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                if m.levelRunning { StatusLine(text: m.levelPhase ?? "Looping…", color: warnColor) }
                if let b = m.busy {
                    StatusLine(text: b.text, color: warnColor)
                    if b.progress == nil { ProgressView().controlSize(.small) }
                }
                if !m.levelRunning && m.busy == nil, let p = m.captureProblem { WarningTag(text: p) }
                Spacer(minLength: 0)
                if m.levelChoice == 0 && (m.levelRunning || !m.levelReadings.isEmpty) {
                    Pill(text: m.autoLevelSettled ? "Sweep level set (\(Int(m.autoLevel)) dBFS)" : "Setting sweep level (\(Int(m.autoLevel)) dBFS)",
                         color: m.autoLevelSettled ? goodColor : warnColor)
                }
            }
            if let e = m.levelError { ErrorNote(e) }
            if let e = m.errorText { ErrorNote(e) }
        }
    }
}

// ------------------------------------------------------------------ 1. Connect
struct CabConnectStep: View {
    @EnvironmentObject var m: AppModel
    let done: Bool
    var body: some View {
        Step(n: 1, title: "Connect", subtitle: "Wire the rig as shown. Then set the use of each input.", done: done) {
            WiringDiagram(wiring: m.refSource == .none ? .cabNoRef : .cabRef).onPaper(padding: 14, style: .drawing)
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
            Button("Open Audio MIDI Setup") { CoreAudioHelper.openAudioMIDISetup() }.buttonStyle(KeyButtonStyle(key: "Open Audio MIDI Setup"))
                .help("If inputs and outputs are on two devices, combine them into an aggregate device in Audio MIDI Setup")
        }
        HStack(spacing: 16) {
            GlassMenu(title: "Interface", selection: $m.deviceUID,
                      options: m.duplexDevices.map { d in (d.uid, "\(d.name)  (\(d.inputChannels) in / \(d.outputChannels) out)") }, minWidth: 240)
            if let dev = m.device {
                GlassMenu(title: outputLabel, selection: $output, options: (0..<dev.outputChannels).map { ($0, "Output \($0 + 1)") })
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
                    Engraved("Input", size: 10, dim: true)
                    Engraved("Use", size: 10, dim: true)
                    Engraved("Mic name", size: 10, dim: true)
                }
                ForEach($m.inputs) { $row in
                    GridRow {
                        Engraved("Input \(row.id + 1)", size: 12, dim: row.role == .off)
                        if row.role == .ref {
                            HStack(spacing: 6) {
                                StatusLine(text: "Reference", color: lamp, diameter: 13)
                                Button("Off") { m.setRole(.off, for: row.id) }.buttonStyle(KeyButtonStyle(key: "Off", size: 11))
                            }
                            .frame(width: 150, alignment: .leading)
                            Text("")
                        } else {
                            KeyChoice(selection: Binding(get: { row.role }, set: { m.setRole($0, for: row.id) }),
                                      options: [(Role.mic, "Mic"), (Role.off, "Off")])
                                .frame(width: 150, alignment: .leading)
                            MicNameField(name: $row.name, disabled: row.role != .mic)
                        }
                    }
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
                JewelLamp(colour: "amber", on: true, diameter: 15)
                Text("Signal on Input \(r.channel + 1) (\(Int(r.peakDBFS.rounded())) dBFS). Use it?")
                Spacer(minLength: 0)
                Button("As a mic") { m.setRole(.mic, for: r.channel) }.buttonStyle(KeyButtonStyle(key: "As a mic"))
                if m.refCandidate == r.channel || m.refInput == nil {
                    Button(m.refCandidate == r.channel ? "As the reference (detected)" : "As the reference") { m.setRefInput(r.channel) }.buttonStyle(KeyButtonStyle(key: "As the reference"))
                }
            }
            .onPaper(padding: 9)
        }
        if let c = m.refCandidate, m.refInput == nil, !m.idleSignals.contains(where: { $0.channel == c }) {
            HStack(spacing: 10) {
                JewelLamp(colour: "amber", on: true, diameter: 15)
                Text("Input \(c + 1) is probably a reference tap. Its signal arrives first and contains no cab or room sound.")
                Spacer(minLength: 0)
                Button("Use it as the reference") { m.setRefInput(c) }.buttonStyle(KeyButtonStyle(key: "Use it as the reference"))
            }
            .onPaper(padding: 9)
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
            Engraved("Reference source")
            HStack(alignment: .top, spacing: 14) {
                ForEach(RefSource.allCases) { s in
                    VStack(alignment: .leading, spacing: 8) {
                        Button(s.title) { m.refSource = s }.buttonStyle(KeyButtonStyle(key: s.title, lit: m.refSource == s, size: 12))
                        Note(blurb(s))
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            if m.refSource != .none, let dev = m.device {
                HStack(spacing: 14) {
                    GlassMenu(title: "Connected to", selection: Binding(get: { m.refInput ?? -1 }, set: { m.setRefInput($0 < 0 ? nil : $0) }),
                              options: [(-1, "Choose…")] + (0..<dev.inputChannels).map { ($0, "Input \($0 + 1)") })
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
                    GlassMenu(title: "Sample rate", selection: $m.rateChoice,
                              options: [(0, "Automatic (\(rateTag(m.device.map(CoreAudioHelper.bestRate) ?? 96000).dropLast()) kHz)")]
                                + m.deviceRates.map { ($0, "\(rateTag($0).dropLast()) kHz") })
                    GlassMenu(title: "Sweep level", selection: $m.levelChoice,
                              options: [(0.0, "Automatic")] + [-6.0, -12, -18, -24].map { ($0, "\(Int($0)) dBFS") })
                    Button("Open Audio MIDI Setup") { CoreAudioHelper.openAudioMIDISetup() }.buttonStyle(KeyButtonStyle(key: "Open Audio MIDI Setup"))
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
            ], style: PaperStyle(stock: .manila, ring: true))
            HStack(spacing: 12) {
                Button(m.levelRunning ? "Stop" : "Check levels") { m.toggleLevelCheck() }
                    .buttonStyle(KeyButtonStyle(key: "Check levels", lit: m.levelRunning, size: 14, big: true))
                    .disabled(m.busy != nil || m.device == nil)
                if m.levelRunning { StatusLine(text: m.levelPhase ?? "Looping…", color: warnColor) }
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
    /// How far the sweep stands above the room noise, as the magic eye's closure: open at 20 dB, closed at 60 dB.
    func eye(_ r: LevelReading) -> (closure: Double?, lit: Bool) {
        guard let n = m.noise[r.channel] else { return (nil, m.levelRunning) }
        if r.peakDBFS < -60 { return (0, true) }
        return (max(0, min(1, (r.peakDBFS - n - 20) / 40)), true)
    }
    var body: some View {
        let compact = MeterBridge<EmptyView>.compact(readings.count)
        VStack(alignment: .leading, spacing: 10) {
            MeterBridge(count: readings.count) {
                ForEach(readings) { r in
                    // 0 VU is this input's target: changeDB is how far the preamp must move to reach it.
                    MeterModule(label: r.label, vu: r.peakDBFS < -60 ? nil : -r.changeDB,
                                dbfs: String(format: "%.1f dBFS", r.peakDBFS), clipped: r.clipped, advice: advice(r),
                                eye: eye(r), compact: compact) {
                        if r.label != "Reference" {
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 6) {
                                    Pill(text: String(format: "H2 %.0f", r.h2), color: distColor(r.h2))
                                    Pill(text: String(format: "H3 %.0f", r.h3), color: distColor(r.h3))
                                }
                                VStack(alignment: .leading, spacing: 5) {
                                    Pill(text: String(format: "H2 %.0f", r.h2), color: distColor(r.h2))
                                    Pill(text: String(format: "H3 %.0f", r.h3), color: distColor(r.h3))
                                }
                            }
                        }
                        if let n = m.noise[r.channel] {
                            Pill(text: m.noiseNote(r.channel) == nil ? "quiet" : "noisy \(Int(n.rounded()))", color: m.noiseNote(r.channel) == nil ? goodColor : warnColor)
                                .help(m.noiseNote(r.channel) ?? String(format: "Room noise %.0f dBFS", n))
                        }
                    }
                }
            }
            Note("0 VU on each meter is that input's target level (sweep peak \(Int(readings.first?.target.rounded() ?? -6)) dBFS). Within ±3 VU is OK. The figure under each meter is the peak in dBFS. The green eye closes as the input stands clear of the room noise: fully closed at 60 dB or more.")
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
            HStack(spacing: 14) {
                Button("Capture") { m.startCapture() }
                    .buttonStyle(KeyButtonStyle(key: "Capture", lit: m.busy?.progress != nil, size: 16, big: true))
                    .disabled(m.busy != nil || m.captureProblem != nil)
                if let p = m.captureProblem, m.busy == nil { WarningTag(text: p) }
            }
            BusyLine()
        }
    }
}

struct PreflightList: View {
    let items: [PreflightItem]
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Engraved("Before you capture")
            ForEach(items) { i in
                StatusLine(text: i.text, color: i.level == .ok ? goodColor : i.level == .warn ? warnColor : badColor, diameter: 13)
                    .frame(minHeight: 16)
            }
        }
        .onPaper(style: .index)
    }
}

// ------------------------------------------------------------------ Import DAW recordings
struct CabImportSteps: View {
    @EnvironmentObject var m: AppModel
    @State private var dropping = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Step(n: 1, title: "Test signal", subtitle: "Save the sweeps for playback from the DAW. Select the sample rate of the DAW project.") {
                HStack(spacing: 18) {
                    GlassMenu(title: "Capture rate", selection: $m.logicRate,
                              options: CoreAudioHelper.captureRates.map { ($0, "\(rateTag($0).dropLast()) kHz") })
                    LevelPicker()
                }
                SweepSettings()
                HStack {
                    Button("Save test signal…") { m.saveTestSignal() }.buttonStyle(KeyButtonStyle(key: "Save test signal…", size: 13))
                    Button("Load settings from a test signal…") { m.loadSignalSettings() }.buttonStyle(KeyButtonStyle(key: "Load settings from a test signal…"))
                }
                Note(m.signalMessage ?? "Use the same settings when the recordings are added in step 3. The settings are saved.")
            }

            Step(n: 2, title: "Record in your DAW", subtitle: "The steps apply to any DAW. Menu names below are from Logic.") {
                WiringDiagram(wiring: .cabRef, compact: true).onPaper(padding: 14, style: .drawing)
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
                DropPlate(dropping: dropping, note: "If the sweep track file is included, it is skipped automatically.") { m.chooseLogicFiles() }
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
                HStack(spacing: 14) {
                    Button("Make IRs") { m.processLogic() }
                        .buttonStyle(KeyButtonStyle(key: "Make IRs", lit: m.busy != nil, size: 16, big: true))
                        .disabled(m.busy != nil || m.logicProblem != nil)
                    if let p = m.logicProblem, m.busy == nil, !m.logicChannels.isEmpty { WarningTag(text: p) }
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
                Engraved("File", size: 10, dim: true)
                Engraved("Mic name", size: 10, dim: true)
                Engraved("Role", size: 10, dim: true)
                Text("")
            }
            ForEach($m.logicChannels) { $c in
                GridRow {
                    VStack(alignment: .leading, spacing: 2) {
                        GlassWindow(size: 12) { Text(c.label).font(.swellMono(11)).truncationMode(.middle) }
                        Note(c.meta)
                    }.frame(maxWidth: 260, alignment: .leading)
                    MicNameField(name: $c.name, disabled: c.role != .mic)
                    KeyChoice(selection: Binding(get: { c.role }, set: { m.setLogicRole($0, for: c.id) }),
                              options: [(Role.mic, "Mic"), (Role.ref, "Ref"), (Role.off, "Skip")], size: 10)
                    if c.channel == 0 {
                        Button("Remove") { m.removeLogicFile(c.url) }.buttonStyle(KeyButtonStyle(key: "Remove", size: 10)).help("Remove this file")
                    } else { Text("") }
                }
            }
        }
    }
}
/// The drop zone: a dimmed plate with a warm edge, a tag saying what to drop, and a key to choose the files instead.
struct DropPlate: View {
    let dropping: Bool
    let note: String
    let choose: () -> Void
    var body: some View {
        VStack(spacing: 10) {
            Engraved("Drop to load: the exported WAV files", size: 12).onPaper(padding: 8, fill: false)
            Button("Choose files…") { choose() }.buttonStyle(KeyButtonStyle(key: "Choose files…"))
            Note(note)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 20)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(dropping ? 0.55 : 0.35)))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(dropping ? Swell.amber : Swell.crinkleSub.opacity(0.5),
                                                                   style: StrokeStyle(lineWidth: dropping ? 2.5 : 1.5, dash: dropping ? [] : [6])))
        .shadow(color: dropping ? Swell.amber.opacity(0.35) : .clear, radius: 8)
    }
}
#endif
