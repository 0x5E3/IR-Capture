#if os(macOS)
import SwiftUI
import IRCaptureCore

/// Amp (NAM): Record here (the app plays TONE3000's file itself) is the main path; Import DAW recordings is secondary.
struct NAMJob: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if m.namMode == "logic" {
                HStack {
                    Button { m.namMode = "app" } label: { Label("Record here", systemImage: "chevron.left") }
                    Text("Import DAW recordings").font(.headline)
                }
                NAMLogicSteps()
            } else {
                let connected = m.device != nil && !m.namRows.filter(\.use).isEmpty
                JobStepper(steps: [("Signal", m.namSignal != nil), ("Connect", connected), ("Set levels", !m.namMeters.isEmpty && m.namMeters.allSatisfy { !$0.clipped }),
                                   ("Record", m.namResult != nil), ("Upload", false)])
                NAMDirectSteps()
                GroupBox {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Recorded in a DAW instead?").bold()
                            Note("Record the TONE3000 sweep through the amp in Logic, Reaper or any other DAW. Prepare the files here.")
                        }
                        Spacer()
                        Button("Import DAW recordings…") { m.namMode = "logic" }
                    }.padding(6)
                }
            }
        }
    }
}

struct NAMModelChoice: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Capture type", selection: $m.namKind) {
                Text("Amp only (load box line out). For use with any cab IR. Recommended.").tag(NAMKind.amp)
                Text("Full chain (mics on the cab). Amp, cab and mic in one model.").tag(NAMKind.full)
            }.pickerStyle(.radioGroup)
            Note(m.namKind == .amp
                 ? "Use an amp-only model with cab IRs captured with a reference (any option except None). The load box line out already contains the speaker impedance peak. An IR made without a reference applies the peak a second time."
                 : "Each mic produces a separate model. Use close mics. NAM models a short time window only, so room sound is not reproduced accurately.")
        }
    }
}

struct NAMNameRow: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        HStack {
            Text("Capture name").foregroundStyle(.secondary)
            TextField("e.g. JCM800_Gain6_Bass5", text: $m.namName).frame(maxWidth: 320)
        }
        Note("Amp and settings, e.g. JCM800_Gain6_Bass5. All file names start with this name.")
        SaveFolderRow()
    }
}

struct NAMDirectSteps: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Step(n: 1, title: "Training signal", subtitle: "The TONE3000 sweep file. Select it once. The selection is saved.", done: m.namSignal != nil) {
                if m.namSignal == nil {
                    Checklist(items: [
                        "Log in at tone3000.com. Choose Create Tone, then Capture, and download the sweep file, T3K-sweep-v3.wav. Do not open the file in an editor or convert it.",
                        "Click Find it in Downloads. (macOS may request access to the Downloads folder for IR Capture.) Alternatively, click Choose sweep file.",
                    ])
                }
                HStack(spacing: 12) {
                    Button("Open tone3000.com/capture") { m.openTONE3000() }
                    if m.namSignal == nil { Button("Find it in Downloads") { m.findNAMSignal(inDownloads: true) }.buttonStyle(.borderedProminent).tint(lamp) }
                    Button(m.namSignal == nil ? "Choose sweep file…" : "Choose a different file…") { m.chooseNAMSignal() }
                }
                if m.namSignal != nil {
                    Note("✓ \(m.namSignalName) loaded (190 s, 48 kHz). The file is played without modification.", color: goodColor)
                } else if let s = m.namSignalStatus {
                    Note(s, color: s.hasPrefix("Checking") ? .secondary : badColor)
                }
            }

            Step(n: 2, title: "Connect", subtitle: "One interface is used for both. The output is connected to the reamp box. The inputs record the amp.") {
                NAMModelChoice()
                WiringDiagram(wiring: m.namKind == .amp ? .namAmp : .namFull)
                Checklist(items: [
                    "Interface output → reamp box → amp guitar input. The preamp is included in the capture. Turn off noise gates, reverb, delay and all effects-loop devices.",
                    m.namKind == .amp
                        ? "Connect the speaker output to the load box. Connect the load box line out to an interface input. Turn off any cab sim or EQ on the load box."
                        : "Connect the amp to the cab as usual. Connect the mics on the cab to the interface. Mute the studio monitors.",
                    "Turn off any mixer or monitoring software effects on the interface inputs (interface DSP, compressors, gates).",
                ])
                InterfaceRow(outputLabel: "Output to the reamp box", output: $m.namOutChannel, showRate: false)
                if m.device != nil {
                    Note("The interface is set to 48 kHz during the session to match the training signal. The previous rate is restored afterwards.")
                    NAMInputsGrid()
                    Note("Set each input to be recorded to Use and enter a name (Suhr, SM57, R121…). Each input produces a separate file and model.")
                }
            }

            Step(n: 3, title: "Set levels", subtitle: "The loudest 6 seconds of the training signal are looped for setting each input.") {
                Checklist(items: [
                    "Warm the amp up for about 20 minutes. Wear ear protection for full chain captures.",
                    "Click Check levels. Set the reamp level to about the level of a guitar.",
                    "Adjust each input gain until its row shows OK (peaks near −8 dBFS). No row may show CLIP.",
                    "Click Stop. Do not adjust any controls after this point.",
                ])
                HStack {
                    Button(m.namLevelRunning ? "Stop" : "Check levels") { m.toggleNAMLevelCheck() }
                        .buttonStyle(.borderedProminent).tint(m.namLevelRunning ? .secondary : lamp).disabled(m.busy != nil)
                    if m.namLevelRunning { ProgressView().controlSize(.small); Text("Looping…").foregroundStyle(.secondary) }
                }
                if let e = m.namLevelError { ErrorNote(e) }
                if !m.namMeters.isEmpty { NAMMeterTable(meters: m.namMeters) }
            }

            Step(n: 4, title: "Record", subtitle: "The full training signal (3 minutes 10 seconds) is played and all inputs are recorded.", done: m.namResult != nil) {
                NAMNameRow()
                HStack {
                    Button("Record (3 min 12 s)") { m.startNAMCapture() }
                        .buttonStyle(.borderedProminent).tint(lamp).controlSize(.large)
                        .disabled(m.busy != nil || m.namDirectProblem != nil)
                    if let p = m.namDirectProblem, m.busy == nil { Note(p, color: warnColor) }
                }
                if let e = m.namError { ErrorNote(e) }
                BusyLine()
                if m.busy?.progress != nil && !m.namMeters.isEmpty { NAMMeterTable(meters: m.namMeters) }
                Note("After recording, the files are aligned, verified and saved in a folder for upload to TONE3000. The unprocessed recording is kept in a “raw recording” subfolder.")
            }
        }
    }
}

struct NAMInputsGrid: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
            GridRow {
                Text("INPUT").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text("USE").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text("NAME").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            ForEach($m.namRows) { $r in
                GridRow {
                    Text("Input \(r.id + 1)")
                    Picker("", selection: $r.use) { Text("Use").tag(true); Text("Not used").tag(false) }.labelsHidden().frame(width: 130)
                    MicNameField(name: $r.name, disabled: !r.use)
                }
            }
        }
    }
}

struct NAMMeterTable: View {
    let meters: [NAMMeter]
    static let target = -8.0
    func advice(_ x: NAMMeter) -> (String, Color) {
        if x.clipped { return ("CLIP: lower input gain about 6 dB", badColor) }
        if x.peakDB < -60 { return ("No signal: check cable and input", badColor) }
        let change = NAMMeterTable.target - x.peakDB
        if abs(change) <= 3 { return ("OK", goodColor) }
        return (change > 0 ? "Raise about \(Int(change.rounded())) dB" : "Lower about \(Int((-change).rounded())) dB", warnColor)
    }
    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
            ForEach(meters) { x in
                let adv = advice(x)
                let color = adv.1
                GridRow {
                    Text(x.label).frame(width: 130, alignment: .leading).lineLimit(1)
                    GeometryReader { g in
                        let frac = max(0, min(1, (x.peakDB + 48) / 48))
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(0.15))
                            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: g.size.width * frac)
                            Rectangle().fill(Color.primary.opacity(0.5)).frame(width: 2)
                                .offset(x: g.size.width * (NAMMeterTable.target + 48) / 48 - 1)
                        }
                    }.frame(width: 220, height: 12)
                    Text(x.peakDB < -100 ? "—" : String(format: "%.1f dBFS", x.peakDB)).font(.system(.body, design: .monospaced)).frame(width: 100, alignment: .trailing)
                    Text(adv.0).foregroundStyle(color)
                }
            }
        }
    }
}

// Import DAW recordings: the original Logic route, now named for any DAW.
struct NAMLogicSteps: View {
    @EnvironmentObject var m: AppModel
    @State private var dropping = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Step(n: 1, title: "Training signal") {
                Checklist(items: [
                    "Log in at tone3000.com. Choose Create Tone, then Capture, and download the sweep file, T3K-sweep-v3.wav (190 seconds, 48 kHz).",
                    "Use the file without modification. Do not trim, normalize or convert it. The file layout is built in. The file is not required here.",
                ])
                Button("Open tone3000.com/capture") { m.openTONE3000() }
            }

            Step(n: 2, title: "Record in your DAW", subtitle: "The steps apply to any DAW. Menu names below are from Logic.") {
                NAMModelChoice()
                Checklist(items: [
                    "Create a new project at 48 kHz. Drag T3K-sweep-v3.wav onto an audio track at the start.",
                    "Route that track to the interface output connected to the reamp box. Connect the reamp box to the amp input. Turn off noise gates, reverb, delay and all effects-loop devices.",
                    "Amp only: connect the speaker output to the load box, and the load box line out to an interface input. Turn off any cab sim or EQ on the load box. Full chain: connect the amp to the cab as usual, with mics on the cab. Mute the studio monitors.",
                    "Create one audio track per input and name it (Suhr, SM57, R121…). The exported files use these names. Turn input monitoring off. Use no plug-ins.",
                    "Set the reamp level to about the level of a guitar. Play the first 20 seconds. Set each input so the loudest part peaks near −8 dBFS, without clipping.",
                    "Warm up the amp for about 20 minutes. Then record one full pass (3 minutes 10 seconds) plus 1–2 seconds past the end. Do not adjust any controls during the recording.",
                    "Export every track as a WAV (in Logic: File › Export › All Tracks as Audio Files): 24-bit, 48 kHz, Normalize off.",
                ])
            }

            Step(n: 3, title: "Prepare the files", subtitle: "Add the exported WAV files, check the names, and click Prepare files.") {
                VStack(spacing: 6) {
                    Text("Drag the exported WAV files here").bold()
                    Button("or choose them…") { m.chooseNAMFiles() }.buttonStyle(.link)
                    Text("The sweep track file is skipped automatically.").font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 18)
                .background(RoundedRectangle(cornerRadius: 6).strokeBorder(dropping ? lamp : Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 2, dash: [6])))
                .onDrop(of: [.fileURL], isTargeted: $dropping) { providers in
                    for p in providers {
                        _ = p.loadObject(ofClass: URL.self) { url, _ in
                            if let url { DispatchQueue.main.async { m.addNAMFiles([url]) } }
                        }
                    }
                    return true
                }
                if let msg = m.namMessage { ErrorNote(msg) }
                if !m.namInputs.isEmpty { NAMGrid() }
                NAMNameRow()
                HStack {
                    Button("Prepare files") { m.prepareNAM() }
                        .buttonStyle(.borderedProminent).tint(lamp).controlSize(.large)
                        .disabled(m.busy != nil || m.namProblem != nil)
                    if let p = m.namProblem, m.busy == nil, !m.namInputs.isEmpty { Note(p, color: warnColor) }
                }
                if let e = m.namError { ErrorNote(e) }
                BusyLine()
            }
        }
    }
}

struct NAMGrid: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
            GridRow {
                Text("FILE").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text("NAME").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text("USE").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text("")
            }
            ForEach($m.namInputs) { $c in
                GridRow {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.label).font(.system(.callout, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                        Text(c.meta).font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: 280, alignment: .leading)
                    TextField("", text: $c.name).frame(width: 180).disabled(!c.use)
                    Picker("", selection: $c.use) { Text("Use").tag(true); Text("Skip").tag(false) }.labelsHidden().frame(width: 110)
                    if c.channel == 0 {
                        Button { m.removeNAMFile(c.url) } label: { Image(systemName: "xmark.circle") }.buttonStyle(.borderless).help("Remove this file")
                    } else { Text("") }
                }
            }
        }
    }
}

struct NAMResultsView: View {
    @EnvironmentObject var m: AppModel
    let r: NAMSummary
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("UPLOAD FOR TRAINING: \(r.title)").font(.system(size: 15, weight: .semibold)).kerning(0.8)
                    Spacer()
                    if r.droppedOut { Pill(text: "Record again", color: badColor) }
                    else if r.warnings.isEmpty { Pill(text: "Ready to upload", color: goodColor) }
                    else { Pill(text: r.warnings.count == 1 ? "1 item to check" : "\(r.warnings.count) items to check", color: warnColor) }
                }
                ForEach(r.warnings, id: \.self) { w in
                    Text(w).padding(.horizontal, 10).padding(.vertical, 7).frame(maxWidth: .infinity, alignment: .leading)
                        .background(warnColor.opacity(0.15)).overlay(Rectangle().fill(warnColor).frame(width: 3), alignment: .leading)
                }
                if r.droppedOut {
                    HStack {
                        Button("Record again") { m.startNAMCapture() }.buttonStyle(.borderedProminent).tint(lamp)
                            .disabled(m.busy != nil || m.namDirectProblem != nil)
                        Note("Quit other apps first (browsers, video calls, other audio software).")
                    }
                }
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow {
                        ForEach(["CHANNEL", "PEAK", "NOISE", "START VS END", "LINED UP"], id: \.self) {
                            Text($0).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        }
                    }
                    Divider().gridCellUnsizedAxes(.horizontal)
                    ForEach(r.names, id: \.self) { n in
                        let d = r.diagnostics[n]!
                        GridRow {
                            Text(n)
                            Pill(text: String(format: "%.1f dBFS", d.peakDBFS),
                                 color: d.clippedSamples > 0 || d.peakDBFS > -3 ? badColor : d.peakDBFS < -24 ? warnColor : goodColor)
                            Pill(text: String(format: "%.0f dBFS", d.noiseDBFS) + (d.humHz.map { " · \($0) Hz hum" } ?? ""),
                                 color: (d.noiseBelowPeakDB ?? 99) < 40 ? badColor : d.humHz != nil ? warnColor : goodColor)
                            Pill(text: d.replicateESR < 0.0001 ? "< 0.0001" : String(format: "%.4f", d.replicateESR),
                                 color: d.replicateESR > 0.005 ? badColor : d.replicateESR > 0.001 ? warnColor : goodColor)
                            Text(String(format: "%.1f ms", d.offsetMs) + (d.polarityInverted ? " · inverted" : "")
                                 + (abs(d.driftSamples) > 1 ? " · drift \(d.driftSamples)" : "")
                                 + (r.names.count > 1 ? String(format: " · +%.2f ms", d.delayVsFirstMs) : "")).monospacedDigit()
                        }
                    }
                }
                Checklist(items: [
                    "Click Show in Finder. The folder contains one WAV per channel (48 kHz, 24-bit, mono), report.json and UPLOAD-STEPS.txt.",
                    "At tone3000.com/capture, upload the WAV files, one model per file.",
                    "Settings: Model Standard, Best Fit on, 400 max epochs (TONE3000 recommendation). Name each model with the amp, its control settings and, for mics, the mic and position. Set the model to private unless it is to be shared.",
                    "Training time: about 5–20 minutes. Check the ESR after training. Below 0.01: very good. 0.3 or higher: the capture failed. Download the .nam file for use in a NAM player.",
                ])
                Note("“Start vs end” compares the first 9 seconds of the take with the last 9 seconds. Both sections contain the same signal. The value indicates amp drift during the recording. Model accuracy is limited to about this value. Below 0.001: excellent.")
                HStack {
                    Button("Show in Finder") { m.revealNAM() }.buttonStyle(.borderedProminent).tint(lamp)
                    Button("Open tone3000.com/capture") { m.openTONE3000() }
                    Text(r.folder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")).font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
            }.padding(8)
        }
    }
}
#endif
