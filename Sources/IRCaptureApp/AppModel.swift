#if os(macOS)
import AppKit
import AVFoundation
import Foundation
import IRCaptureCore
import UniformTypeIdentifiers

enum Role: String, CaseIterable, Codable, Identifiable {
    case off, mic, ref
    var id: String { rawValue }
    var label: String { switch self { case .off: return "Not used"; case .mic: return "Mic"; case .ref: return "Reference tap" } }
}

struct InputRow: Identifiable, Codable, Equatable {
    var id: Int            // 0-based device input channel
    var role: Role
    var name: String
}

struct LogicChannel: Identifiable {
    let id = UUID()
    let url: URL
    let channel: Int
    let channels: Int
    let fs: Int
    let frames: Int
    let bits: Int
    var role: Role
    var name: String
    var label: String { url.lastPathComponent + (channels > 1 ? " · ch \(channel + 1)" : "") }
    var meta: String { "\(rateTag(fs).dropLast()) kHz · \(bits)-bit · " + String(format: "%.1f s", Double(frames) / Double(fs)) }
}

struct ResultSummary {
    var title: String
    var names: [String]
    var diagnostics: [(label: String, diag: ChannelDiagnostics)]
    var warnings: [String]
    var referenced: Bool
    var curves: (fc: [Double], curves: [String: [Double]])
    var folder: URL
    var fileCount: Int
}

struct NAMInput: Identifiable {
    let id = UUID()
    let url: URL
    let channel: Int
    let channels: Int
    let fs: Int
    let frames: Int
    let bits: Int
    var use: Bool
    var name: String
    var label: String { url.lastPathComponent + (channels > 1 ? " · ch \(channel + 1)" : "") }
    var meta: String { "\(rateTag(fs).dropLast()) kHz · \(bits)-bit · " + String(format: "%.1f s", Double(frames) / Double(fs)) }
}

struct NAMSummary {
    var title: String
    var kind: NAMKind
    var names: [String]
    var diagnostics: [String: NAMChannelInfo]
    var warnings: [String]
    var notes: [String]
    var folder: URL
    var files: [String]
}

enum Busy: Equatable {
    case preparing(String)
    case recording(Double)
    case processing(String)
    var text: String {
        switch self {
        case .preparing(let t): return t
        case .recording(let p): return "Playing the sweeps and recording — \(Int(p * 100))%. Keep the room quiet."
        case .processing(let t): return t + "…"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    private let defaults = UserDefaults.standard

    // ---------------------------------------------------------------- interface
    @Published var devices: [AudioDevice] = []
    @Published var deviceUID: String { didSet { defaults.set(deviceUID, forKey: "deviceUID"); deviceChanged() } }
    @Published var rate: Int { didSet { defaults.set(rate, forKey: "rate") } }
    @Published var outChannel: Int { didSet { defaults.set(outChannel, forKey: "outChannel") } }
    @Published var inputs: [InputRow] = [] { didSet { saveInputs() } }

    // ---------------------------------------------------------------- sweep
    @Published var level: Double { didSet { defaults.set(level, forKey: "level") } }
    @Published var nSweeps: Int { didSet { defaults.set(nSweeps, forKey: "nSweeps") } }
    @Published var duration: Double { didSet { defaults.set(duration, forKey: "duration") } }
    @Published var gap: Double { didSet { defaults.set(gap, forKey: "gap") } }
    @Published var discard: Int { didSet { defaults.set(discard, forKey: "discard") } }

    // ---------------------------------------------------------------- output
    @Published var exportRates: Set<Int> { didSet { defaults.set(Array(exportRates), forKey: "exportRates") } }
    @Published var lengths: Set<String> { didSet { defaults.set(Array(lengths), forKey: "lengths") } }
    @Published var bits: Set<String> { didSet { defaults.set(Array(bits), forKey: "bits") } }
    @Published var trims: Set<String> { didSet { defaults.set(Array(trims), forKey: "trims") } }
    @Published var fullMs: Double { didSet { defaults.set(fullMs, forKey: "fullMs") } }
    @Published var captureName: String { didSet { defaults.set(captureName, forKey: "captureName") } }
    @Published var notes: String = ""
    @Published var outputFolder: URL { didSet { defaults.set(outputFolder.path, forKey: "outputFolder") } }

    // ---------------------------------------------------------------- state
    @Published var levelRunning = false
    @Published var levelReadings: [LevelReading] = []
    @Published var levelError: String?
    @Published var busy: Busy?
    @Published var errorText: String?
    @Published var result: ResultSummary?
    private var levelTask: Task<Void, Never>?
    private var captureTask: Task<Void, Never>?

    // ---------------------------------------------------------------- Logic tab
    @Published var logicChannels: [LogicChannel] = []
    @Published var logicRate: Int { didSet { defaults.set(logicRate, forKey: "logicRate") } }
    @Published var logicMessage: String?
    @Published var signalMessage: String?

    // ---------------------------------------------------------------- NAM tab
    @Published var namInputs: [NAMInput] = []
    @Published var namKind: NAMKind { didSet { defaults.set(namKind.rawValue, forKey: "namKind") } }
    @Published var namName: String { didSet { defaults.set(namName, forKey: "namName") } }
    @Published var namMessage: String?
    @Published var namError: String?
    @Published var namResult: NAMSummary?

    init() {
        let d = UserDefaults.standard
        deviceUID = d.string(forKey: "deviceUID") ?? ""
        rate = d.object(forKey: "rate") as? Int ?? 96000
        outChannel = d.object(forKey: "outChannel") as? Int ?? 0
        level = d.object(forKey: "level") as? Double ?? -12
        nSweeps = d.object(forKey: "nSweeps") as? Int ?? 5
        duration = d.object(forKey: "duration") as? Double ?? 6
        gap = d.object(forKey: "gap") as? Double ?? 2
        discard = d.object(forKey: "discard") as? Int ?? 1
        exportRates = Set(d.array(forKey: "exportRates") as? [Int] ?? [44100, 48000, 88200, 96000])
        lengths = Set(d.array(forKey: "lengths") as? [String] ?? ["full", "1024", "2048", "4096"])
        bits = Set(d.array(forKey: "bits") as? [String] ?? ["24"])
        trims = Set(d.array(forKey: "trims") as? [String] ?? ["set"])
        fullMs = d.object(forKey: "fullMs") as? Double ?? 500
        captureName = d.string(forKey: "captureName") ?? "Cab_Position1"
        logicRate = d.object(forKey: "logicRate") as? Int ?? 96000
        namKind = NAMKind(rawValue: d.string(forKey: "namKind") ?? "amp") ?? .amp
        namName = d.string(forKey: "namName") ?? "Amp_Settings1"
        let music = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSHomeDirectory())
        outputFolder = d.string(forKey: "outputFolder").map { URL(fileURLWithPath: $0) } ?? music.appendingPathComponent("IR Captures")
        refreshDevices()
    }

    // ---------------------------------------------------------------- devices
    var duplexDevices: [AudioDevice] { devices.filter(\.isDuplex) }
    var device: AudioDevice? { devices.first { $0.uid == deviceUID && $0.isDuplex } }
    var deviceRates: [Int] { device?.sampleRates.isEmpty == false ? device!.sampleRates : CoreAudioHelper.captureRates }

    func refreshDevices() {
        devices = CoreAudioHelper.devices()
        if device == nil, let first = duplexDevices.first(where: { $0.inputChannels > 2 }) ?? duplexDevices.first {
            deviceUID = first.uid
        } else {
            deviceChanged()
        }
    }

    private func deviceChanged() {
        guard let dev = device else { inputs = []; return }
        if outChannel >= dev.outputChannels { outChannel = 0 }
        if !dev.sampleRates.isEmpty && !dev.sampleRates.contains(rate) { rate = dev.sampleRates.contains(96000) ? 96000 : dev.sampleRates.max()! }
        var saved: [InputRow] = []
        if let data = defaults.data(forKey: "inputs." + dev.uid), let rows = try? JSONDecoder().decode([InputRow].self, from: data) { saved = rows }
        inputs = (0..<dev.inputChannels).map { ch in
            saved.first { $0.id == ch } ?? InputRow(id: ch, role: ch == 0 ? .mic : .off, name: "Input\(ch + 1)")
        }
    }

    private func saveInputs() {
        guard let dev = device, let data = try? JSONEncoder().encode(inputs) else { return }
        defaults.set(data, forKey: "inputs." + dev.uid)
    }

    func setRole(_ role: Role, for id: Int) {
        if role == .ref { for i in inputs.indices where inputs[i].role == .ref { inputs[i].role = .mic } }
        if let i = inputs.firstIndex(where: { $0.id == id }) { inputs[i].role = role }
    }

    // ---------------------------------------------------------------- settings
    func spec(fs: Int) throws -> SweepSpec {
        try SweepSpec(fs: fs, duration: duration, nSweeps: nSweeps, discard: discard, gap: gap, levelDBFS: level)
    }
    var signalSeconds: Double { 1 + Double(nSweeps) * (duration + gap) + 0.5 }

    func exportOptions() -> ExportOptions {
        var e = ExportOptions()
        e.rates = CoreAudioHelper.captureRates.filter { exportRates.contains($0) }
        e.lengths = ["full", "1024", "2048", "4096"].filter { lengths.contains($0) }.compactMap { IRLength($0) }
        e.bits = BitDepth.allCases.filter { bits.contains($0.rawValue) }
        e.trim = TrimMode.allCases.filter { trims.contains($0.rawValue) }
        e.fullMs = max(50, min(1000, fullMs))
        return e
    }

    var outputProblem: String? {
        let e = exportOptions()
        if e.rates.isEmpty || e.lengths.isEmpty || e.bits.isEmpty || e.trim.isEmpty {
            return "Choose at least one sample rate, length, bit depth and trimming option under Output files."
        }
        return nil
    }

    static func namesProblem(_ names: [String]) -> String? {
        if names.isEmpty { return "Mark at least one input as a mic." }
        var seen = Set<String>()
        for n in names {
            let k = safeName(n).lowercased()
            if k == "reference" { return "“reference” is kept for the reference tap. Give that mic another name." }
            if seen.contains(k) { return "Two mics are both named “\(n)”. Give each a different name." }
            seen.insert(k)
        }
        return nil
    }

    var captureProblem: String? {
        guard device != nil else { return "Choose an audio interface in step 1." }
        if let p = AppModel.namesProblem(inputs.filter { $0.role == .mic }.map(\.name)) { return p }
        return outputProblem
    }

    func chooseOutputFolder() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true
        p.prompt = "Use This Folder"
        p.directoryURL = outputFolder
        if p.runModal() == .OK, let u = p.url { outputFolder = u }
    }

    private func uniqueCaptureName(_ base: String) -> String {
        let fm = FileManager.default
        var name = base, k = 2
        while fm.fileExists(atPath: outputFolder.appendingPathComponent(name).path) { name = "\(base)_\(k)"; k += 1 }
        return name
    }

    private func microphoneAllowed() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }
    private let micDenied = "IR Capture isn't allowed to record. Open System Settings › Privacy & Security › Microphone, turn on IR Capture, then quit and reopen the app."

    // ---------------------------------------------------------------- level check
    func toggleLevelCheck() {
        if levelRunning { levelTask?.cancel(); levelTask = nil; levelRunning = false; return }
        guard let dev = device else { levelError = "Choose an audio interface first."; return }
        let rows = inputs.filter { $0.role != .off }
        guard !rows.isEmpty else { levelError = "Mark at least one input as a mic."; return }
        levelError = nil; levelReadings = []; levelRunning = true
        let fs = rate, out = outChannel
        levelTask = Task {
            defer { levelRunning = false }
            guard await microphoneAllowed() else { levelError = micDenied; return }
            do {
                try await Task.detached { try CoreAudioHelper.setNominalRate(dev.id, fs) }.value
                var lvl = level
                let firstLevel = lvl
                var check = try await Task.detached { try LevelCheck(fs: fs, levelDBFS: firstLevel) }.value
                while !Task.isCancelled {
                    if level != lvl { lvl = level; let l = lvl; check = try await Task.detached { try LevelCheck(fs: fs, levelDBFS: l) }.value }
                    let rows = inputs.filter { $0.role != .off }
                    let labels = rows.map { $0.role == .ref ? "Reference tap" : $0.name }
                    let rec = try await DuplexIO.run(device: dev, fs: fs, outChannel: out, inputs: rows.map(\.id),
                                                     signal: check.signal, extraSeconds: 0.4, cancelled: { Task.isCancelled })
                    let c = check
                    let readings = await Task.detached { c.read(rec.map { $0.map(Double.init) }, labels: labels, target: -6) }.value
                    if !Task.isCancelled { levelReadings = readings }
                }
            } catch is CancellationError {
            } catch {
                levelError = error.localizedDescription
            }
        }
    }

    // ---------------------------------------------------------------- capture
    func startCapture() {
        if let p = captureProblem { errorText = p; return }
        guard let dev = device else { return }
        if levelRunning { levelTask?.cancel(); levelRunning = false }
        errorText = nil
        let mics = inputs.filter { $0.role == .mic }, ref = inputs.first { $0.role == .ref }
        let names = mics.map { safeName($0.name) }
        let channelList = mics.map(\.id) + (ref.map { [$0.id] } ?? [])
        let refIndex: Int? = ref == nil ? nil : mics.count
        let fs = rate, out = outChannel, eo = exportOptions(), outDir = outputFolder, noteText = notes
        let capture = uniqueCaptureName(safeName(captureName.isEmpty ? "Cab" : captureName))
        busy = .preparing("Getting ready")
        captureTask = Task {
            defer { busy = nil; captureTask = nil }
            guard await microphoneAllowed() else { errorText = micDenied; return }
            do {
                let spec = try self.spec(fs: fs)
                busy = .preparing("Setting the interface to \(rateTag(fs).dropLast()) kHz")
                try await Task.detached { try CoreAudioHelper.setNominalRate(dev.id, fs) }.value
                let signal = await Task.detached { makeTestSignal(spec) }.value
                busy = .recording(0)
                let rec = try await DuplexIO.run(device: dev, fs: fs, outChannel: out, inputs: channelList, signal: signal,
                                                 extraSeconds: 1.0, cancelled: { Task.isCancelled },
                                                 progress: { p in Task { @MainActor in if case .recording = self.busy { self.busy = .recording(p) } } })
                busy = .processing("Saving the raw recording")
                var extra: [(String, JSON)] = [
                    ("channels", .object([
                        ("interface", .string(dev.name)),
                        ("output", .int(out + 1)),
                        ("mics", .object(zip(names, mics).map { ($0.0, JSON.int($0.1.id + 1)) })),
                        ("reference", ref.map { JSON.int($0.id + 1) } ?? JSON.null)])),
                    ("notes", .string(noteText)),
                    ("app", .string("IR Capture (Mac) \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")),
                ]
                extra.append(("recorded_with", .string("direct")))
                let report = { (t: String) in Task { @MainActor in self.busy = .processing(t) } }
                let processed = try await Task.detached(priority: .userInitiated) { () -> ProcessedCapture in
                    let raw = outDir.appendingPathComponent(capture).appendingPathComponent("raw")
                    try FileManager.default.createDirectory(at: raw, withIntermediateDirectories: true)
                    try writeWavFloat(rec, rate: fs).write(to: raw.appendingPathComponent("\(capture)_recording.wav"))
                    try spec.json.serialized().write(to: raw.appendingPathComponent("\(capture)_signal.json"), atomically: true, encoding: .utf8)
                    return try processAndWrite(rec: rec.map { $0.map(Double.init) }, spec: spec, names: names, refIndex: refIndex,
                                               capture: capture, outDir: outDir, export: eo, extra: extra, progress: { report($0) })
                }.value
                show(processed, title: capture)
            } catch is CancellationError {
                errorText = "Capture stopped."
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    func cancelCapture() { captureTask?.cancel() }

    private func show(_ p: ProcessedCapture, title: String) {
        result = ResultSummary(title: title, names: p.result.names, diagnostics: p.result.diagnostics, warnings: p.result.warnings,
                               referenced: p.result.referenced, curves: p.curves, folder: p.folder, fileCount: p.fileCount)
    }

    func revealResult() {
        guard let r = result else { return }
        NSWorkspace.shared.activateFileViewerSelecting([r.folder])
    }

    // ---------------------------------------------------------------- Logic: test signal
    func saveTestSignal() {
        signalMessage = nil
        let spec: SweepSpec
        do { spec = try self.spec(fs: logicRate) } catch { signalMessage = error.localizedDescription; return }
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true
        p.prompt = "Save Here"; p.message = "Choose a folder for the test signal"
        guard p.runModal() == .OK, let dir = p.url else { return }
        let tag = rateTag(spec.fs), base = "ircapture_sweeps_\(tag)"
        let x = makeTestSignal(spec)
        let howto = """
        Cab IR Capture test signal

        \(spec.nSweeps) sweeps of \(spec.duration) s, \(spec.gap) s gaps, \(Int(spec.f1)) Hz to \(Int(spec.f2.rounded())) Hz, peak \(spec.levelDBFS) dBFS, \(tag).
        Length \(String(format: "%.1f", Double(x.count) / Double(spec.fs))) s.

        Put \(base).wav at bar 1 of a \(tag) Logic project, record the mics while it plays,
        then process the recordings in IR Capture (Use Logic recordings) with the same settings.
        The .json file records these settings.

        """
        do {
            try writeWavFloat([x], rate: spec.fs).write(to: dir.appendingPathComponent(base + ".wav"))
            try spec.json.serialized().write(to: dir.appendingPathComponent(base + ".json"), atomically: true, encoding: .utf8)
            try howto.write(to: dir.appendingPathComponent("How to use.txt"), atomically: true, encoding: .utf8)
            signalMessage = "Saved \(base).wav in \(dir.lastPathComponent). Keep these settings for step 3."
            NSWorkspace.shared.activateFileViewerSelecting([dir.appendingPathComponent(base + ".wav")])
        } catch {
            signalMessage = error.localizedDescription
        }
    }

    /// Loads the sweep settings from a test signal's .json (written by this app, the page or the Python tool).
    func loadSignalSettings() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.json]; p.message = "Choose the .json file saved with the test signal"
        guard p.runModal() == .OK, let u = p.url else { return }
        do {
            let s = try SweepSpec.load(jsonData: Data(contentsOf: u))
            logicRate = s.fs; level = s.levelDBFS; nSweeps = s.nSweeps; duration = s.duration; gap = s.gap; discard = s.discard
            signalMessage = "Loaded the settings from \(u.lastPathComponent)."
        } catch { signalMessage = "\(u.lastPathComponent): \(error.localizedDescription)" }
    }

    // ---------------------------------------------------------------- Logic: files
    func chooseLogicFiles() {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = true; p.allowedContentTypes = [.wav]
        p.message = "Select the mic and reference WAV files Logic exported"
        if p.runModal() == .OK { addLogicFiles(p.urls) }
    }

    func addLogicFiles(_ urls: [URL]) {
        logicMessage = nil
        for u in urls where u.pathExtension.lowercased() == "wav" {
            do {
                let info = try WavInfo(Data(contentsOf: u, options: .mappedIfSafe))
                _ = try info.channel(0).count
                let stem = safeName(u.deletingPathExtension().lastPathComponent)
                let isSweep = stem.range(of: "sweep|ircapture", options: [.regularExpression, .caseInsensitive]) != nil
                for c in 0..<info.channels {
                    let hasRef = logicChannels.contains { $0.role == .ref }
                    let isRef = !isSweep && !hasRef && stem.range(of: "ref|tap|terminal|speaker.?out", options: [.regularExpression, .caseInsensitive]) != nil
                    logicChannels.append(LogicChannel(url: u, channel: c, channels: info.channels, fs: info.fs, frames: info.frames,
                                                      bits: info.bits, role: isSweep ? .off : isRef ? .ref : .mic,
                                                      name: stem + (info.channels > 1 ? "_\(c + 1)" : "")))
                }
            } catch {
                logicMessage = "\(u.lastPathComponent): \(error.localizedDescription). Export WAV files from Logic (16, 24 or 32-bit)."
            }
        }
        if let fs = logicChannels.first?.fs, Set(logicChannels.map(\.fs)).count == 1, CoreAudioHelper.captureRates.contains(fs) { logicRate = fs }
    }

    func setLogicRole(_ role: Role, for id: UUID) {
        if role == .ref { for i in logicChannels.indices where logicChannels[i].role == .ref { logicChannels[i].role = .mic } }
        if let i = logicChannels.firstIndex(where: { $0.id == id }) { logicChannels[i].role = role }
    }

    func removeLogicFile(_ url: URL) { logicChannels.removeAll { $0.url == url } }

    var logicProblem: String? {
        guard !logicChannels.isEmpty else { return "Add the exported WAV files." }
        let rates = Set(logicChannels.map(\.fs))
        if rates.count > 1 { return "These files have different sample rates. They need to come from the same take." }
        if rates.first! != logicRate {
            return "The recordings are \(rateTag(rates.first!).dropLast()) kHz but the test signal setting is \(rateTag(logicRate).dropLast()) kHz. Set step 1 to match the recording."
        }
        if let p = AppModel.namesProblem(logicChannels.filter { $0.role == .mic }.map(\.name)) { return p }
        let shortest = logicChannels.map { Double($0.frames) / Double($0.fs) }.min()!
        if shortest < signalSeconds - 1.5 {
            return String(format: "The recordings are %.1f s long, shorter than the %.1f s test signal. Check the sweep settings, or record the whole pass.", shortest, signalSeconds)
        }
        return outputProblem
    }

    func processLogic() {
        if let p = logicProblem { errorText = p; return }
        errorText = nil
        let used = logicChannels.filter { $0.role != .off }
        let fs = logicRate, eo = exportOptions(), outDir = outputFolder, noteText = notes
        let capture = uniqueCaptureName(safeName(captureName.isEmpty ? "Cab" : captureName))
        busy = .processing("Reading the recordings")
        captureTask = Task {
            defer { busy = nil; captureTask = nil }
            do {
                let spec = try self.spec(fs: fs)
                let report = { (t: String) in Task { @MainActor in self.busy = .processing(t) } }
                let processed = try await Task.detached(priority: .userInitiated) { () -> ProcessedCapture in
                    var cache: [URL: WavInfo] = [:]
                    var rec: [[Double]] = [], names: [String] = [], refIndex: Int? = nil
                    for c in used {
                        let info = try cache[c.url] ?? WavInfo(Data(contentsOf: c.url, options: .mappedIfSafe))
                        cache[c.url] = info
                        rec.append(try info.channel(c.channel))
                        if c.role == .ref { refIndex = rec.count - 1 } else { names.append(safeName(c.name)) }
                    }
                    let n = rec.map(\.count).min()!
                    rec = rec.map { $0.count > n ? Array($0.prefix(n)) : $0 }
                    let extra: [(String, JSON)] = [
                        ("channels", .array(used.map { c in JSON.object([("file", .string(c.url.lastPathComponent)), ("channel", .int(c.channel + 1)),
                                                                     ("role", .string(c.role.rawValue)), ("name", .string(safeName(c.name)))]) })),
                        ("notes", .string(noteText)), ("recorded_with", .string("logic")),
                    ]
                    return try processAndWrite(rec: rec, spec: spec, names: names, refIndex: refIndex, capture: capture,
                                               outDir: outDir, export: eo, extra: extra, progress: { report($0) })
                }.value
                show(processed, title: capture)
            } catch {
                errorText = error.localizedDescription
            }
        }
    }
    // ---------------------------------------------------------------- NAM: files
    func chooseNAMFiles() {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = true; p.allowedContentTypes = [.wav]
        p.message = "Select the WAV files Logic exported (load box line out or mics)"
        if p.runModal() == .OK { addNAMFiles(p.urls) }
    }

    func addNAMFiles(_ urls: [URL]) {
        namMessage = nil
        for u in urls where u.pathExtension.lowercased() == "wav" {
            do {
                let info = try WavInfo(Data(contentsOf: u, options: .mappedIfSafe))
                _ = try info.channel(0).count
                let stem = safeName(u.deletingPathExtension().lastPathComponent)
                let seconds = Double(info.frames) / Double(info.fs)
                let isSweep = stem.range(of: "t3k|sweep|^input|v3_0_0", options: [.regularExpression, .caseInsensitive]) != nil && abs(seconds - 190) < 0.05
                for c in 0..<info.channels {
                    namInputs.append(NAMInput(url: u, channel: c, channels: info.channels, fs: info.fs, frames: info.frames, bits: info.bits,
                                              use: !isSweep, name: stem + (info.channels > 1 ? "_\(c + 1)" : "")))
                }
            } catch {
                namMessage = "\(u.lastPathComponent): \(error.localizedDescription). Export WAV files from Logic (16, 24 or 32-bit)."
            }
        }
    }

    func removeNAMFile(_ url: URL) { namInputs.removeAll { $0.url == url } }

    var namProblem: String? {
        let used = namInputs.filter(\.use)
        guard !namInputs.isEmpty else { return "Add the exported WAV files." }
        guard !used.isEmpty else { return "Choose Use for at least one channel." }
        var seen = Set<String>()
        for c in used {
            let k = NAMPrep.safe(c.name).lowercased()
            if seen.contains(k) { return "Two channels are both named “\(c.name)”. Give each a different name." }
            seen.insert(k)
        }
        for c in used where Double(c.frames) / Double(c.fs) < 180 {
            return "\(c.url.lastPathComponent) is only \(Int(Double(c.frames) / Double(c.fs))) s long. The training signal is 190 s: record the whole pass."
        }
        return nil
    }

    func prepareNAM() {
        if let p = namProblem { namError = p; return }
        namError = nil
        let used = namInputs.filter(\.use), kind = namKind, outDir = outputFolder
        let capture = uniqueCaptureName(NAMPrep.safe(namName.isEmpty ? "Amp" : namName))
        busy = .processing("Reading the recordings")
        captureTask = Task {
            defer { busy = nil; captureTask = nil }
            do {
                let report = { (t: String) in Task { @MainActor in self.busy = .processing(t) } }
                let (res, folder) = try await Task.detached(priority: .userInitiated) { () -> (NAMResult, URL) in
                    var cache: [URL: WavInfo] = [:]
                    var done: [(name: String, result: NAMChannelResult)] = []
                    for c in used {
                        let info = try cache[c.url] ?? WavInfo(Data(contentsOf: c.url, options: .mappedIfSafe))
                        cache[c.url] = info
                        let name = NAMPrep.safe(c.name)
                        done.append((name, try NAMPrep.prepareChannel(try info.channel(c.channel), fs: info.fs, label: name, progress: { report($0) })))
                    }
                    let res = NAMPrep.finish(kind: kind, channels: done)
                    report("Saving files")
                    let extra: [(String, JSON)] = [
                        ("channels", .array(used.map { c in JSON.object([("file", .string(c.url.lastPathComponent)), ("channel", .int(c.channel + 1)),
                                                                     ("name", .string(NAMPrep.safe(c.name)))]) })),
                        ("app", .string("IR Capture (Mac) \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")),
                    ]
                    return (res, try NAMPrep.write(res, capture: capture, outDir: outDir, extra: extra))
                }.value
                namResult = NAMSummary(title: capture, kind: res.kind, names: res.names, diagnostics: res.diagnostics, warnings: res.warnings,
                                       notes: res.notes, folder: folder, files: res.names.map { NAMPrep.fileName(capture, $0) })
            } catch {
                namError = error.localizedDescription
            }
        }
    }

    func revealNAM() {
        guard let r = namResult else { return }
        NSWorkspace.shared.activateFileViewerSelecting(r.files.map { r.folder.appendingPathComponent($0) })
    }

    func openTONE3000() {
        if let u = URL(string: "https://www.tone3000.com/capture") { NSWorkspace.shared.open(u) }
    }
}
#endif
