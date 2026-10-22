#if os(macOS)
import AppKit
import AVFoundation
import Foundation
import IRCaptureCore
import UniformTypeIdentifiers

enum Role: String, CaseIterable, Codable, Identifiable {
    case off, mic, ref
    var id: String { rawValue }
    var label: String { switch self { case .off: return "Not used"; case .mic: return "Mic"; case .ref: return "Reference" } }
}

/// The two jobs the window is organized around.
enum Job: String, CaseIterable { case cab, nam }

/// Where the reference comes from (P0.6). Only the presentation differs; every non-none source is a tap of
/// the amp's output voltage on its own line input.
enum RefSource: String, CaseIterable, Identifiable {
    case none, loadBox, tap
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: return "None (simplest)"
        case .loadBox: return "Load box line out"
        case .tap: return "Reference tap or pad"
        }
    }
}

enum HelpPage: String, Identifiable, CaseIterable {
    case quickStart, wiring, reference, troubleshooting
    var id: String { rawValue }
    var title: String {
        switch self {
        case .quickStart: return "Quick start"
        case .wiring: return "Wiring"
        case .reference: return "The reference tap"
        case .troubleshooting: return "Troubleshooting"
        }
    }
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
    var polarityNotes: [String] = []
    /// Files at the top of the capture folder (the Universal ones).
    var topFiles: [String] = []
    var droppedOut = false
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

/// One interface input for direct NAM capture.
struct NAMRow: Identifiable, Codable, Equatable {
    var id: Int            // 0-based device input channel
    var use: Bool
    var name: String
}

/// Live level of one input during the NAM level check or capture.
struct NAMMeter: Identifiable {
    let id: Int
    var label: String
    var peakDB: Double     // highest peak over the last few seconds
    var clipped: Bool
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
    var droppedOut = false
}

/// One line of the pre-flight summary before Capture (P0.7). A block stops Capture; a warning doesn't.
struct PreflightItem: Identifiable {
    enum Level { case ok, warn, block }
    let id = UUID()
    let level: Level
    let text: String
}

enum Busy: Equatable {
    case preparing(String)
    case recording(Double)
    case namRecording(Double)
    case processing(String)
    var text: String {
        switch self {
        case .preparing(let t): return t
        case .recording(let p): return "Playing the sweeps and recording — \(Int(p * 100))%. Keep the room quiet."
        case .namRecording(let p):
            let left = max(0, Int(((1 - p) * Double(NAMPrep.length + 2 * NAMPrep.fs) / Double(NAMPrep.fs)).rounded()))
            return "Playing the training signal and recording — \(left / 60):\(String(format: "%02d", left % 60)) left. Don't touch the amp or the gain knobs."
        case .processing(let t): return t + "…"
        }
    }
    var progress: Double? {
        switch self { case .recording(let p), .namRecording(let p): return p; default: return nil }
    }
}

/// Holds a value set from a callback that runs off the main actor.
final class Box<T> { var value: T?; init() {} }

/// Common mic names for the name menus. Names become file names, so short ones read best in Finder.
let commonMicNames = ["SM57", "MD421", "e906", "e609", "R121", "R-10", "SM7B", "C414", "U87", "i5", "M160", "Room", "Back"]

@MainActor
final class AppModel: ObservableObject {
    private let defaults = UserDefaults.standard

    // ---------------------------------------------------------------- window
    @Published var job: Job { didSet { defaults.set(job.rawValue, forKey: "job"); if job != oldValue { stopLevelChecks() } } }
    @Published var cabImport = false              // Cab IR: showing Import DAW recordings instead of Record here
    @Published var showWelcome = false
    @Published var helpPage: HelpPage?
    @Published var micStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .audio)

    // ---------------------------------------------------------------- interface
    @Published var devices: [AudioDevice] = []
    @Published var deviceUID: String { didSet { defaults.set(deviceUID, forKey: "deviceUID"); deviceChanged() } }
    /// 0 = automatic (the highest the interface supports, up to 96 kHz).
    @Published var rateChoice: Int { didSet { defaults.set(rateChoice, forKey: "rateChoice") } }
    @Published var outChannel: Int { didSet { defaults.set(outChannel, forKey: "outChannel") } }
    @Published var inputs: [InputRow] = [] { didSet { saveInputs() } }
    @Published var refSource: RefSource {
        didSet {
            defaults.set(refSource.rawValue, forKey: "refSource")
            if refSource == .none { for i in inputs.indices where inputs[i].role == .ref { inputs[i].role = .off } }
        }
    }

    // ---------------------------------------------------------------- sweep
    /// 0 = automatic (P0.7): set by the level check from the measured distortion.
    @Published var levelChoice: Double { didSet { defaults.set(levelChoice, forKey: "levelChoice") } }
    @Published var autoLevel: Double = -18
    @Published var autoLevelSettled = false
    /// The sweep level of the test signal saved for a DAW (Import DAW recordings).
    @Published var level: Double { didSet { defaults.set(level, forKey: "level") } }
    @Published var nSweeps: Int { didSet { defaults.set(nSweeps, forKey: "nSweeps") } }
    @Published var duration: Double { didSet { defaults.set(duration, forKey: "duration") } }
    @Published var gap: Double { didSet { defaults.set(gap, forKey: "gap") } }
    @Published var discard: Int { didSet { defaults.set(discard, forKey: "discard") } }

    // ---------------------------------------------------------------- output
    @Published var targets: Set<String> { didSet { defaults.set(Array(targets), forKey: "targets") } }
    @Published var customOn: Bool { didSet { defaults.set(customOn, forKey: "customOn") } }
    @Published var keepPolarity: Bool { didSet { defaults.set(keepPolarity, forKey: "keepPolarity") } }
    @Published var exportRates: Set<Int> { didSet { defaults.set(Array(exportRates), forKey: "exportRates") } }
    @Published var lengths: Set<String> { didSet { defaults.set(Array(lengths), forKey: "lengths") } }
    @Published var bits: Set<String> { didSet { defaults.set(Array(bits), forKey: "bits") } }
    @Published var trims: Set<String> { didSet { defaults.set(Array(trims), forKey: "trims") } }
    @Published var fullMs: Double { didSet { defaults.set(fullMs, forKey: "fullMs") } }
    @Published var captureName: String { didSet { defaults.set(captureName, forKey: "captureName") } }
    @Published var notes: String = ""
    @Published var outputFolder: URL { didSet { defaults.set(outputFolder.path, forKey: "outputFolder") } }

    // ---------------------------------------------------------------- level check state
    @Published var levelRunning = false
    @Published var levelPhase: String?
    @Published var levelReadings: [LevelReading] = []
    /// Inputs marked Not used that showed signal during the level check (P0.5 auto-suggest).
    @Published var idleSignals: [LevelReading] = []
    /// The input that looks like a reference tap, if one does.
    @Published var refCandidate: Int?
    /// Room noise per input channel, RMS dBFS, from the 2 s of silence before the sweeps.
    @Published var noise: [Int: Double] = [:]
    @Published var levelError: String?
    @Published var busy: Busy?
    @Published var errorText: String?
    @Published var result: ResultSummary?
    @Published var reexportFolder: URL?
    @Published var reexportMessage: String?
    private var levelTask: Task<Void, Never>?
    private var captureTask: Task<Void, Never>?
    /// The interface's own sample rate before the app changed it, restored when the app is idle again.
    private var savedRate: (id: AudioDeviceID, rate: Double)?
    /// Finishes when the last job that drove the interface (or the rate restore after it) is done.
    /// Every new audio job waits for it, so two jobs never drive the interface at once.
    private var audioChain: Task<Void, Never>?
    /// Each start of a level check gets a new number; a stopped run's cleanup only resets state if it's still current.
    private var levelGen = 0, namGen = 0
    private var autoSteppedDown = false
    private var pendingRefresh = false
    private var deviceSignature = ""

    // ---------------------------------------------------------------- Import DAW recordings (cab)
    @Published var logicChannels: [LogicChannel] = []
    @Published var logicRate: Int { didSet { defaults.set(logicRate, forKey: "logicRate") } }
    @Published var logicMessage: String?
    @Published var signalMessage: String?

    // ---------------------------------------------------------------- NAM
    @Published var namInputs: [NAMInput] = []
    @Published var namKind: NAMKind { didSet { defaults.set(namKind.rawValue, forKey: "namKind") } }
    @Published var namName: String { didSet { defaults.set(namName, forKey: "namName") } }
    @Published var namMessage: String?
    @Published var namError: String?
    @Published var namResult: NAMSummary?
    @Published var namMode: String { didSet { defaults.set(namMode, forKey: "namMode") } }       // "app" or "logic"
    @Published var namOutChannel: Int { didSet { defaults.set(namOutChannel, forKey: "namOutChannel") } }
    @Published var namRows: [NAMRow] = [] { didSet { saveNAMRows() } }
    @Published var namSignalPath: String { didSet { defaults.set(namSignalPath, forKey: "namSignalPath") } }
    @Published var namSignalStatus: String?
    @Published var namSignal: [Float]?
    @Published var namLevelRunning = false
    @Published var namLevelError: String?
    @Published var namMeters: [NAMMeter] = []
    private var namMeterHistory: [Int: [Float]] = [:]
    private var namClipped: Set<Int> = []
    private var namLevelTask: Task<Void, Never>?
    /// CI only: replaces the interface with a simulated one (fixed latency and gain per input).
    var simulateIO = false

    init() {
        let d = UserDefaults.standard
        job = Job(rawValue: d.string(forKey: "job") ?? "cab") ?? .cab
        deviceUID = d.string(forKey: "deviceUID") ?? ""
        rateChoice = d.object(forKey: "rateChoice") as? Int ?? 0
        outChannel = d.object(forKey: "outChannel") as? Int ?? 0
        refSource = RefSource(rawValue: d.string(forKey: "refSource") ?? "none") ?? .none
        levelChoice = d.object(forKey: "levelChoice") as? Double ?? 0
        level = d.object(forKey: "level") as? Double ?? -12
        nSweeps = d.object(forKey: "nSweeps") as? Int ?? 5
        duration = d.object(forKey: "duration") as? Double ?? 6
        gap = d.object(forKey: "gap") as? Double ?? 2
        discard = d.object(forKey: "discard") as? Int ?? 1
        targets = Set(d.array(forKey: "targets") as? [String] ?? ["universal"])
        customOn = d.bool(forKey: "customOn")
        keepPolarity = d.bool(forKey: "keepPolarity")
        exportRates = Set(d.array(forKey: "exportRates") as? [Int] ?? [44100, 48000, 88200, 96000])
        lengths = Set(d.array(forKey: "lengths") as? [String] ?? ["full", "1024", "2048", "4096"])
        bits = Set(d.array(forKey: "bits") as? [String] ?? ["24"])
        trims = Set(d.array(forKey: "trims") as? [String] ?? ["set"])
        fullMs = d.object(forKey: "fullMs") as? Double ?? 500
        captureName = d.string(forKey: "captureName") ?? "Cab_Position1"
        logicRate = d.object(forKey: "logicRate") as? Int ?? 96000
        namKind = NAMKind(rawValue: d.string(forKey: "namKind") ?? "amp") ?? .amp
        namName = d.string(forKey: "namName") ?? "Amp_Settings1"
        namMode = d.string(forKey: "namMode") ?? "app"
        namOutChannel = d.object(forKey: "namOutChannel") as? Int ?? 0
        namSignalPath = d.string(forKey: "namSignalPath") ?? ""
        let music = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSHomeDirectory())
        outputFolder = d.string(forKey: "outputFolder").map { URL(fileURLWithPath: $0) } ?? music.appendingPathComponent("IR Captures")

        let args = ProcessInfo.processInfo.arguments
        let automated = args.contains { $0.hasPrefix("--") }
        IRCaptureVersion = Product.version + " (build \(Product.build))"
        Log.write("launch \(Product.name) \(Product.fullVersion), \(Product.macOS), \(ProcessInfo.processInfo.machineHardwareName)")
        refreshDevices()
        CoreAudioHelper.watchDevices { [weak self] in Task { @MainActor in self?.refreshDevices(hotPlug: true) } }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.restoreRateNow() }
        }
        showWelcome = !d.bool(forKey: "welcomeDone") && !automated
        if !namSignalPath.isEmpty, FileManager.default.fileExists(atPath: namSignalPath), !args.contains("--nam-direct-demo") {
            loadNAMSignal(URL(fileURLWithPath: namSignalPath))
        } else if !automated {
            findNAMSignal(inDownloads: false)          // ~/Music needs no permission; Downloads waits for a click
        }
    }

    // ---------------------------------------------------------------- welcome and help
    func finishWelcome() { defaults.set(true, forKey: "welcomeDone"); showWelcome = false }

    /// Asks for the microphone at a moment the user chose, with the reason on screen (P0.4).
    func requestMicrophone() {
        Task {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
            micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
            Log.write("microphone permission: \(micStatus.rawValue)")
        }
    }

    func openPrivacySettings() {
        if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") { NSWorkspace.shared.open(u) }
    }

    var latestReport: URL? {
        (job == .nam ? namResult?.folder : result?.folder)?.appendingPathComponent("report.json")
            ?? result?.folder.appendingPathComponent("report.json") ?? namResult?.folder.appendingPathComponent("report.json")
    }

    func contactSupport() { Support.contact(interface: device?.name, latestReport: latestReport) }

    // ---------------------------------------------------------------- devices
    var duplexDevices: [AudioDevice] { devices.filter(\.isDuplex) }
    var device: AudioDevice? { devices.first { $0.uid == deviceUID && $0.isDuplex } }
    var deviceRates: [Int] { device?.sampleRates.isEmpty == false ? device!.sampleRates : CoreAudioHelper.captureRates }
    /// The rate captures run at.
    var captureRate: Int {
        if rateChoice != 0, deviceRates.contains(rateChoice) { return rateChoice }
        return device.map(CoreAudioHelper.bestRate) ?? 96000
    }
    /// The sweep level captures and the level check use.
    var cabLevel: Double { levelChoice == 0 ? autoLevel : levelChoice }

    func refreshDevices(hotPlug: Bool = false) {
        let before = Set(devices.map(\.uid))
        devices = CoreAudioHelper.devices()
        if hotPlug {
            let added = devices.filter { !before.contains($0.uid) }.map(\.name)
            let removed = before.subtracting(devices.map(\.uid))
            Log.write("interfaces changed: added \(added), removed \(removed.count)")
        }
        // Don't switch interfaces under a running job; catch up when it ends.
        if audioActive { pendingRefresh = true; return }
        pendingRefresh = false
        if device == nil, let first = duplexDevices.first(where: { $0.inputChannels > 2 }) ?? duplexDevices.first {
            deviceUID = first.uid
        } else if signature(device) != deviceSignature {
            deviceChanged()                 // only when the chosen interface itself appeared, went away or changed
        }
    }

    /// True while anything is using the interface or processing.
    var audioActive: Bool { busy != nil || levelRunning || namLevelRunning }

    private func signature(_ d: AudioDevice?) -> String { d.map { "\($0.uid)|\($0.inputChannels)|\($0.outputChannels)" } ?? "" }

    private func deviceChanged() {
        deviceSignature = signature(device)
        guard let dev = device else { inputs = []; namRows = []; return }
        Log.write("interface: \(dev.name), \(dev.inputChannels) in / \(dev.outputChannels) out, rates \(dev.sampleRates)")
        if outChannel >= dev.outputChannels { outChannel = 0 }
        if namOutChannel >= dev.outputChannels { namOutChannel = 0 }
        var savedNAM: [NAMRow] = []
        if let data = defaults.data(forKey: "naminputs." + dev.uid), let rows = try? JSONDecoder().decode([NAMRow].self, from: data) { savedNAM = rows }
        namRows = (0..<dev.inputChannels).map { ch in
            savedNAM.first { $0.id == ch } ?? NAMRow(id: ch, use: ch == 0, name: "Input\(ch + 1)")
        }
        var saved: [InputRow] = []
        if let data = defaults.data(forKey: "inputs." + dev.uid), let rows = try? JSONDecoder().decode([InputRow].self, from: data) { saved = rows }
        inputs = (0..<dev.inputChannels).map { ch in
            saved.first { $0.id == ch } ?? InputRow(id: ch, role: ch == 0 ? .mic : .off, name: ch == 0 ? "SM57" : "Input\(ch + 1)")
        }
        if refSource == .none { for i in inputs.indices where inputs[i].role == .ref { inputs[i].role = .off } }
        levelReadings = []; idleSignals = []; noise = [:]; refCandidate = nil
    }

    private func saveNAMRows() {
        guard !simulateIO, let dev = device, let data = try? JSONEncoder().encode(namRows) else { return }
        defaults.set(data, forKey: "naminputs." + dev.uid)
    }

    private func saveInputs() {
        guard let dev = device, let data = try? JSONEncoder().encode(inputs) else { return }
        defaults.set(data, forKey: "inputs." + dev.uid)
    }

    func setRole(_ role: Role, for id: Int) {
        if role == .ref { for i in inputs.indices where inputs[i].role == .ref { inputs[i].role = .off } }
        if let i = inputs.firstIndex(where: { $0.id == id }) {
            inputs[i].role = role
            if role == .mic && inputs[i].name.hasPrefix("Input") { inputs[i].name = suggestedMicName() }
        }
        if role == .ref && refSource == .none { refSource = .tap }
        idleSignals.removeAll { $0.channel == id }
    }

    /// The reference input (0-based), if one is marked.
    var refInput: Int? { inputs.first { $0.role == .ref }?.id }

    func setRefInput(_ ch: Int?) {
        for i in inputs.indices where inputs[i].role == .ref { inputs[i].role = .off }
        if let ch { setRole(.ref, for: ch) }
    }

    private func suggestedMicName() -> String {
        let used = Set(inputs.filter { $0.role == .mic }.map { $0.name.lowercased() })
        return commonMicNames.first { !used.contains($0.lowercased()) } ?? "Mic"
    }

    func label(for ch: Int) -> String {
        guard let r = inputs.first(where: { $0.id == ch }) else { return "Input \(ch + 1)" }
        switch r.role {
        case .ref: return "Reference"
        case .mic: return r.name.isEmpty ? "Input \(ch + 1)" : r.name
        case .off: return "Input \(ch + 1)"
        }
    }

    // ---------------------------------------------------------------- sample rate ownership
    /// Remembers the interface's own rate the first time a job changes it.
    private func takeRate(_ dev: AudioDevice) {
        if savedRate == nil || savedRate!.id != dev.id { savedRate = (dev.id, CoreAudioHelper.nominalRate(dev.id)) }
    }
    /// Called when any job ends. Once nothing is using the interface, puts its rate back (waiting until the
    /// interface has really switched, so the next job starts from a known rate) and catches up on hot-plug.
    private func jobEnded() {
        guard !audioActive else { return }
        if pendingRefresh { refreshDevices() }
        guard let s = savedRate else { return }
        savedRate = nil
        let before = audioChain
        audioChain = Task.detached { await before?.value; CoreAudioHelper.restoreRate(s.id, s.rate) }
    }

    /// Stops both level checks. Their tasks finish in the background; the next audio job waits for them.
    func stopLevelChecks() {
        if levelRunning || levelTask != nil { levelTask?.cancel(); levelTask = nil; levelGen += 1; levelRunning = false; levelPhase = nil }
        if namLevelRunning || namLevelTask != nil { namLevelTask?.cancel(); namLevelTask = nil; namGen += 1; namLevelRunning = false }
    }
    private func restoreRateNow() {
        guard let s = savedRate else { return }
        savedRate = nil
        CoreAudioHelper.restoreRate(s.id, s.rate)
    }

    // ---------------------------------------------------------------- settings
    func spec(fs: Int, level lv: Double) throws -> SweepSpec {
        try SweepSpec(fs: fs, duration: duration, nSweeps: nSweeps, discard: discard, gap: gap, levelDBFS: lv)
    }
    var signalSeconds: Double { 1 + Double(nSweeps) * (duration + gap) + 0.5 }

    /// The Custom matrix (Advanced).
    func exportOptions() -> ExportOptions {
        var e = ExportOptions()
        e.rates = CoreAudioHelper.captureRates.filter { exportRates.contains($0) }
        e.lengths = ["full", "1024", "2048", "4096"].filter { lengths.contains($0) }.compactMap { IRLength($0) }
        e.bits = BitDepth.allCases.filter { bits.contains($0.rawValue) }
        e.trim = TrimMode.allCases.filter { trims.contains($0.rawValue) }
        e.fullMs = max(50, min(1000, fullMs))
        return e
    }

    var chosenTargets: [ExportTarget] { ExportTarget.all.filter { targets.contains($0.id) } }
    func layout() -> OutputLayout { .targets(chosenTargets, custom: customOn ? exportOptions() : nil) }

    var outputProblem: String? {
        if chosenTargets.isEmpty && !customOn { return "Choose at least one set of files to make under Files." }
        if customOn {
            let e = exportOptions()
            if e.rates.isEmpty || e.lengths.isEmpty || e.bits.isEmpty || e.trim.isEmpty {
                return "Custom files: choose at least one sample rate, length, bit depth and trimming option, or turn Custom off."
            }
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

    // ---------------------------------------------------------------- pre-flight (P0.7)
    var mics: [InputRow] { inputs.filter { $0.role == .mic } }

    func noiseNote(_ ch: Int) -> String? {
        guard let n = noise[ch] else { return nil }
        let peak = levelReadings.first { $0.channel == ch }?.peakDBFS
        if n > -55 { return "\(label(for: ch)) is noisy (room noise at \(Int(n.rounded())) dBFS). Fridge, air conditioning, fans or the studio monitors on?" }
        if let p = peak, p - n < 40 { return "\(label(for: ch)) is only \(Int((p - n).rounded())) dB above the room noise. Turn that preamp up, or quieten the room." }
        return nil
    }

    var preflight: [PreflightItem] {
        var out: [PreflightItem] = []
        guard let dev = device else { return [PreflightItem(level: .block, text: "Choose an audio interface in Connect.")] }
        if let p = AppModel.namesProblem(mics.map(\.name)) { out.append(PreflightItem(level: .block, text: p)) }
        else { out.append(PreflightItem(level: .ok, text: "\(mics.count) mic\(mics.count == 1 ? "" : "s") (\(mics.map(\.name).joined(separator: ", ")))")) }
        if refSource == .none { out.append(PreflightItem(level: .ok, text: "Reference: none")) }
        else if let r = refInput { out.append(PreflightItem(level: .ok, text: "Reference: Input \(r + 1)")) }
        else { out.append(PreflightItem(level: .block, text: "Choose which input the reference is plugged into, or set the reference to None.")) }
        out.append(PreflightItem(level: .ok, text: "\(rateTag(captureRate).dropLast()) kHz on \(dev.name)"))
        let used = levelReadings.filter { r in inputs.contains { $0.id == r.channel && $0.role != .off } }
        if used.isEmpty {
            out.append(PreflightItem(level: .warn, text: "Levels haven't been checked yet. Click Check levels first."))
        } else {
            let clipped = used.filter(\.clipped)
            if !clipped.isEmpty {
                out.append(PreflightItem(level: .block, text: "\(clipped.map(\.label).joined(separator: ", ")) clipped in the level check. Turn \(clipped.count == 1 ? "it" : "them") down and check levels again."))
            } else {
                let off = used.filter { abs($0.changeDB) > 3 && $0.label != "Reference" }
                if off.isEmpty { out.append(PreflightItem(level: .ok, text: "Levels OK")) }
                else { out.append(PreflightItem(level: .warn, text: off.map { "\($0.label) \($0.changeDB > 0 ? "is low" : "is hot") by \(Int(abs($0.changeDB).rounded())) dB" }.joined(separator: "; ") + ".")) }
            }
            let hot = used.filter { $0.label != "Reference" && max($0.h2, $0.h3) > -30 }
            if !hot.isEmpty { out.append(PreflightItem(level: .warn, text: "Distortion is high on \(hot.map(\.label).joined(separator: ", ")). Lower the amp volume\(levelChoice == 0 ? "" : " or the sweep level").")) }
        }
        if !noise.isEmpty {
            let noisy = inputs.filter { $0.role != .off }.compactMap { noiseNote($0.id) }
            if noisy.isEmpty { out.append(PreflightItem(level: .ok, text: "Room quiet")) }
            else { out += noisy.map { PreflightItem(level: .warn, text: $0) } }
        }
        if let p = outputProblem { out.append(PreflightItem(level: .block, text: p)) }
        return out
    }

    var captureProblem: String? { preflight.first { $0.level == .block }?.text }

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
        let ok: Bool
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: ok = true
        case .notDetermined: ok = await AVCaptureDevice.requestAccess(for: .audio)
        default: ok = false
        }
        micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if !ok { Log.write("microphone permission denied") }
        return ok
    }
    let micDenied = "IR Capture isn't allowed to record. Open System Settings › Privacy & Security › Microphone, turn on IR Capture, then quit and reopen the app."

    static func rmsDB(_ x: [Float], from a: Int) -> Double {
        guard x.count > a else { return -120 }
        var s = 0.0
        for i in a..<x.count { s += Double(x[i]) * Double(x[i]) }
        return 10 * log10(max(s / Double(x.count - a), 1e-24))
    }

    // ---------------------------------------------------------------- level check (with auto sweep level and noise check)
    func toggleLevelCheck() {
        if levelRunning { stopLevelChecks(); return }
        guard let dev = device else { levelError = "Choose an audio interface first."; return }
        guard busy == nil else { return }
        guard inputs.contains(where: { $0.role != .off }) else { levelError = "Mark at least one input as a mic."; return }
        levelError = nil; levelReadings = []; idleSignals = []; refCandidate = nil; noise = [:]; levelRunning = true
        let fs = captureRate, out = outChannel, all = Array(0..<dev.inputChannels), auto = levelChoice == 0
        if auto { autoLevel = -18; autoLevelSettled = false; autoSteppedDown = false }
        stopLevelChecks()                 // the NAM one, if it's running
        levelRunning = true
        levelGen += 1
        let gen = levelGen, wait = audioChain
        Log.write("level check start: \(dev.name) at \(fs) Hz, output \(out + 1), sweep \(auto ? "auto" : "\(levelChoice) dBFS")")
        let t = Task {
            defer {
                if gen == levelGen { levelRunning = false; levelPhase = nil; levelTask = nil }
                jobEnded()
            }
            await wait?.value
            if Task.isCancelled { return }
            takeRate(dev)
            guard await microphoneAllowed() else { levelError = micDenied; return }
            do {
                try await Task.detached { try CoreAudioHelper.setNominalRate(dev.id, fs) }.value
                // Noise check: 2 s with the output silent, every input.
                levelPhase = "Listening to the room for 2 seconds. Keep it quiet."
                let silence = [Float](repeating: 0, count: 2 * fs)
                let nrec = try await DuplexIO.run(device: dev, fs: fs, outChannel: out, inputs: all, signal: silence,
                                                  extraSeconds: 0.1, cancelled: { Task.isCancelled })
                var nz: [Int: Double] = [:]
                for (ch, x) in zip(all, nrec) { nz[ch] = AppModel.rmsDB(x, from: fs / 2) }
                noise = nz
                Log.write("room noise (dBFS RMS): " + all.map { "\($0 + 1): \(Int(nz[$0]!.rounded()))" }.joined(separator: ", "))
                var lvl = cabLevel
                let first = lvl
                var check = try await Task.detached { try LevelCheck(fs: fs, levelDBFS: first) }.value
                while !Task.isCancelled {
                    if cabLevel != lvl { lvl = cabLevel; let l = lvl; check = try await Task.detached { try LevelCheck(fs: fs, levelDBFS: l) }.value }
                    levelPhase = auto && !autoLevelSettled ? "Finding the sweep level…" : "Playing short sweeps…"
                    let rec = try await DuplexIO.run(device: dev, fs: fs, outChannel: out, inputs: all,
                                                     signal: check.signal, extraSeconds: 0.4, cancelled: { Task.isCancelled })
                    let rows = inputs
                    let c = check
                    // Read the inputs in use, plus any unused input that shows signal.
                    let wanted: [(ch: Int, label: String)] = all.compactMap { ch -> (ch: Int, label: String)? in
                        let role = rows.first { $0.id == ch }?.role ?? .off
                        let peak = rec[ch].reduce(Float(0)) { max($0, abs($1)) }
                        if role == .off && peak < 0.01 { return nil }                    // -40 dBFS
                        return (ch, role == .off ? "Input \(ch + 1)" : self.label(for: ch))
                    }
                    let readings = await Task.detached { () -> [LevelReading] in
                        var r = c.read(wanted.map { rec[$0.ch].map(Double.init) }, labels: wanted.map(\.label), target: -6)
                        for i in r.indices { r[i].channel = wanted[i].ch }
                        return r
                    }.value
                    if Task.isCancelled { break }
                    let used = readings.filter { r in rows.contains { $0.id == r.channel && $0.role != .off } }
                    levelReadings = used
                    idleSignals = readings.filter { r in rows.contains { $0.id == r.channel && $0.role == .off } }
                    refCandidate = refInput == nil ? check.referenceCandidate(readings)?.channel : nil
                    if auto { stepAutoLevel(used.filter { r in rows.contains { $0.id == r.channel && $0.role == .mic } }) }
                }
            } catch is CancellationError {
            } catch {
                Log.write("level check error: \(error.localizedDescription)")
                if gen == levelGen { levelError = error.localizedDescription }
            }
        }
        levelTask = t
        audioChain = t
    }

    /// Auto sweep level: start at −18 dBFS, step up 6 dB while the mics' distortion stays below −40 dB,
    /// back off 6 dB if it rises above −30 dB, and never step up again after backing off (so it can't
    /// oscillate). Never above −6 dBFS or below −30 dBFS.
    private func stepAutoLevel(_ mics: [LevelReading]) {
        guard !mics.isEmpty else { return }
        let worst = mics.map { max($0.h2, $0.h3) }.max()!
        let clipped = mics.contains(where: \.clipped)
        let before = autoLevel
        if worst > -30 && autoLevel > -30 { autoLevel -= 6; autoLevelSettled = false; autoSteppedDown = true }
        else if !autoSteppedDown && worst < -40 && autoLevel < -6 && !clipped && mics.allSatisfy({ $0.peakDBFS < -9 }) { autoLevel += 6; autoLevelSettled = false }
        else { autoLevelSettled = true }
        if before != autoLevel { Log.write("auto sweep level \(Int(before)) → \(Int(autoLevel)) dBFS (worst harmonic \(Int(worst.rounded())) dB)") }
    }

    // ---------------------------------------------------------------- capture
    func startCapture() {
        if let p = captureProblem { errorText = p; return }
        guard let dev = device, busy == nil else { return }
        stopLevelChecks()
        errorText = nil
        let mics = inputs.filter { $0.role == .mic }
        let ref: InputRow? = refSource == .none ? nil : inputs.first(where: { $0.role == .ref })
        let names = mics.map { safeName($0.name) }
        let channelList = mics.map(\.id) + (ref.map { [$0.id] } ?? [])
        let refIndex: Int? = ref == nil ? nil : mics.count
        let fs = captureRate, lv = cabLevel, out = outChannel, lay = layout(), keep = keepPolarity, outDir = outputFolder, noteText = notes
        let capture = uniqueCaptureName(safeName(captureName.isEmpty ? "Cab" : captureName))
        let refKind = refSource
        Log.write("capture \(capture): \(dev.name) at \(fs) Hz, output \(out + 1), sweep \(lv) dBFS, mics \(zip(names, mics.map { $0.id + 1 }).map { "\($0.0)=\($0.1)" }), reference \(ref.map { "\($0.id + 1)" } ?? "none")")
        busy = .preparing("Getting ready")
        let wait = audioChain
        let t = Task {
            defer { busy = nil; captureTask = nil; jobEnded() }
            await wait?.value
            if Task.isCancelled { errorText = "Capture stopped. Nothing was saved."; return }
            takeRate(dev)
            guard await microphoneAllowed() else { errorText = micDenied; return }
            let t0 = Date()
            do {
                let spec = try self.spec(fs: fs, level: lv)
                busy = .preparing("Setting the interface to \(rateTag(fs).dropLast()) kHz")
                try await Task.detached { try CoreAudioHelper.setNominalRate(dev.id, fs) }.value
                let signal = await Task.detached { makeTestSignal(spec) }.value
                busy = .recording(0)
                let io = Box<DuplexIO.Report>()
                let rec = try await DuplexIO.run(device: dev, fs: fs, outChannel: out, inputs: channelList, signal: signal,
                                                 extraSeconds: 1.0, cancelled: { Task.isCancelled },
                                                 progress: { p in Task { @MainActor in if case .recording = self.busy { self.busy = .recording(p) } } },
                                                 report: { io.value = $0 })
                Log.write(String(format: "recorded %.1f s in %.1f s", Double(rec.first?.count ?? 0) / Double(fs), Date().timeIntervalSince(t0)))
                busy = .processing("Saving the raw recording")
                let dropWarning = io.value?.dropoutWarning
                var extra: [(String, JSON)] = [
                    ("channels", .object([
                        ("interface", .string(dev.name)),
                        ("output", .int(out + 1)),
                        ("mics", .object(zip(names, mics).map { ($0.0, JSON.int($0.1.id + 1)) })),
                        ("reference", ref.map { JSON.int($0.id + 1) } ?? JSON.null),
                        ("reference_source", .string(refKind.rawValue))])),
                    ("notes", .string(noteText)),
                    ("app", .string("\(Product.name) (Mac) \(Product.fullVersion)")),
                    ("recorded_with", .string("direct")),
                ]
                if let r = io.value { extra.append(("io", r.json)) }
                let report = { (t: String) in Task { @MainActor in self.busy = .processing(t) } }
                let take = RawTake(capture: capture, names: names, refIndex: refIndex, spec: spec, recordedWith: "direct", notes: noteText)
                let processed = try await Task.detached(priority: .userInitiated) { () -> ProcessedCapture in
                    try take.save(rec, captureFolder: outDir.appendingPathComponent(capture))
                    return try processAndWrite(rec: rec.map { $0.map(Double.init) }, spec: spec, names: names, refIndex: refIndex,
                                               capture: capture, outDir: outDir, layout: lay, keepPolarity: keep, extra: extra,
                                               extraWarnings: dropWarning.map { [$0] } ?? [], progress: { report($0) })
                }.value
                Log.write("capture \(capture) done in \(String(format: "%.1f", Date().timeIntervalSince(t0))) s: \(processed.fileCount) files, \(processed.result.warnings.count) warnings")
                show(processed, title: capture, droppedOut: dropWarning != nil)
            } catch is CancellationError {
                errorText = "Capture stopped. Nothing was saved."
            } catch {
                Log.write("capture error: \(error.localizedDescription)")
                errorText = error.localizedDescription
            }
        }
        captureTask = t
        audioChain = t
    }

    func cancelCapture() { captureTask?.cancel() }

    private func show(_ p: ProcessedCapture, title: String, droppedOut: Bool = false) {
        result = ResultSummary(title: title, names: p.result.names, diagnostics: p.result.diagnostics, warnings: p.result.warnings,
                               referenced: p.result.referenced, curves: p.curves, folder: p.folder, fileCount: p.fileCount,
                               polarityNotes: p.polarityNotes, topFiles: p.files.filter { !$0.contains("/") }, droppedOut: droppedOut)
    }

    func revealResult() {
        guard let r = result else { return }
        let top = r.topFiles.map { r.folder.appendingPathComponent($0) }
        NSWorkspace.shared.activateFileViewerSelecting(top.isEmpty ? [r.folder] : top)
    }

    // ---------------------------------------------------------------- re-export (P0.8)
    /// Opens the re-export sheet for a past capture chosen in Finder.
    func chooseReexportFolder() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false
        p.message = "Choose a capture folder (it has a Raw take folder inside)"
        p.prompt = "Re-export"
        p.directoryURL = outputFolder
        if p.runModal() == .OK, let u = p.url { reexportMessage = nil; reexportFolder = u }
    }

    /// Makes the chosen file sets again from the folder's raw take, without recording again.
    func reexport(_ folder: URL) {
        if let p = outputProblem { reexportMessage = p; return }
        let lay = layout(), keep = keepPolarity
        let capture = folder.lastPathComponent, outDir = folder.deletingLastPathComponent()
        reexportMessage = nil
        busy = .processing("Reading the raw take")
        captureTask = Task {
            defer { busy = nil; captureTask = nil; jobEnded() }
            let report = { (t: String) in Task { @MainActor in self.busy = .processing(t) } }
            do {
                let processed = try await Task.detached(priority: .userInitiated) { () -> ProcessedCapture in
                    let (take, rec) = try RawTake.load(captureFolder: folder)
                    // Old generated files go to the Trash, not away for good; Raw take and report history stay.
                    let fm = FileManager.default
                    let more = folder.appendingPathComponent("More formats")
                    if fm.fileExists(atPath: more.path) { try? fm.trashItem(at: more, resultingItemURL: nil) }
                    for f in (try? fm.contentsOfDirectory(atPath: folder.path)) ?? [] where f.hasSuffix(".wav") && f.hasPrefix(capture + "_") {
                        try? fm.trashItem(at: folder.appendingPathComponent(f), resultingItemURL: nil)
                    }
                    let extra: [(String, JSON)] = [("recorded_with", .string(take.recordedWith)), ("notes", .string(take.notes)),
                                                   ("reexported", .bool(true)), ("app", .string("\(Product.name) (Mac) \(Product.fullVersion)"))]
                    return try processAndWrite(rec: rec, spec: take.spec, names: take.names, refIndex: take.refIndex, capture: capture,
                                               outDir: outDir, layout: lay, keepPolarity: keep, extra: extra, progress: { report($0) })
                }.value
                Log.write("re-exported \(capture): \(processed.fileCount) files")
                reexportFolder = nil
                show(processed, title: capture)
            } catch {
                Log.write("re-export error: \(error.localizedDescription)")
                reexportMessage = error.localizedDescription
            }
        }
    }

    // ---------------------------------------------------------------- Import DAW recordings: test signal
    func saveTestSignal() {
        signalMessage = nil
        let spec: SweepSpec
        do { spec = try self.spec(fs: logicRate, level: level) } catch { signalMessage = error.localizedDescription; return }
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

        Put \(base).wav at the very start of a \(tag) project in your DAW (Logic, Reaper, Ableton, Pro Tools, GarageBand…),
        record the mics while it plays, export each track as a WAV, then add them in IR Capture
        (Cab IR › Import DAW recordings) with the same settings. The .json file records these settings.

        """
        do {
            try writeWavFloat([x], rate: spec.fs).write(to: dir.appendingPathComponent(base + ".wav"))
            try spec.json.serialized().write(to: dir.appendingPathComponent(base + ".json"), atomically: true, encoding: .utf8)
            try howto.write(to: dir.appendingPathComponent("How to use.txt"), atomically: true, encoding: .utf8)
            signalMessage = "Saved \(base).wav in \(dir.lastPathComponent). Keep these settings for step 3."
            NSWorkspace.shared.activateFileViewerSelecting([dir.appendingPathComponent(base + ".wav")])
        } catch {
            signalMessage = error.localizedDescription + " Choose another folder and try again."
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

    // ---------------------------------------------------------------- Import DAW recordings: files
    func chooseLogicFiles() {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = true; p.allowedContentTypes = [.wav]
        p.message = "Select the mic and reference WAV files your DAW exported"
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
                logicMessage = "\(u.lastPathComponent): \(error.localizedDescription). Export WAV files from your DAW (16, 24 or 32-bit) and add them again."
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
        let fs = logicRate, lv = level, lay = layout(), keep = keepPolarity, outDir = outputFolder, noteText = notes
        let capture = uniqueCaptureName(safeName(captureName.isEmpty ? "Cab" : captureName))
        Log.write("import \(capture): \(used.count) channels at \(fs) Hz")
        busy = .processing("Reading the recordings")
        captureTask = Task {
            defer { busy = nil; captureTask = nil; jobEnded() }
            do {
                let spec = try self.spec(fs: fs, level: lv)
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
                        ("app", .string("\(Product.name) (Mac) \(Product.fullVersion)")),
                    ]
                    // Keep a raw take too, so this capture can be re-exported later without the DAW files.
                    try RawTake(capture: capture, names: names, refIndex: refIndex, spec: spec, recordedWith: "logic", notes: noteText)
                        .save(rec.map { $0.map(Float.init) }, captureFolder: outDir.appendingPathComponent(capture))
                    return try processAndWrite(rec: rec, spec: spec, names: names, refIndex: refIndex, capture: capture,
                                               outDir: outDir, layout: lay, keepPolarity: keep, extra: extra, progress: { report($0) })
                }.value
                show(processed, title: capture)
            } catch {
                Log.write("import error: \(error.localizedDescription)")
                errorText = error.localizedDescription
            }
        }
    }

    // ---------------------------------------------------------------- NAM: files
    func chooseNAMFiles() {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = true; p.allowedContentTypes = [.wav]
        p.message = "Select the WAV files your DAW exported (load box line out or mics)"
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
                namMessage = "\(u.lastPathComponent): \(error.localizedDescription). Export WAV files from your DAW (16, 24 or 32-bit) and add them again."
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
        Log.write("NAM import \(capture): \(used.count) channels, \(kind.rawValue)")
        busy = .processing("Reading the recordings")
        captureTask = Task {
            defer { busy = nil; captureTask = nil; jobEnded() }
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
                        ("app", .string("\(Product.name) (Mac) \(Product.fullVersion)")),
                    ]
                    return (res, try NAMPrep.write(res, capture: capture, outDir: outDir, extra: extra))
                }.value
                namResult = NAMSummary(title: capture, kind: res.kind, names: res.names, diagnostics: res.diagnostics, warnings: res.warnings,
                                       notes: res.notes, folder: folder, files: res.names.map { NAMPrep.fileName(capture, $0) })
            } catch {
                Log.write("NAM import error: \(error.localizedDescription)")
                namError = error.localizedDescription
            }
        }
    }

    // ---------------------------------------------------------------- NAM: record with the app
    func chooseNAMSignal() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.wav]
        p.message = "Choose T3K-sweep-v3.wav, the sweep file downloaded from TONE3000"
        p.directoryURL = namSignalPath.isEmpty ? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                                               : URL(fileURLWithPath: namSignalPath).deletingLastPathComponent()
        if p.runModal() == .OK, let u = p.url { loadNAMSignal(u) }
    }

    /// Looks for TONE3000's sweep file in ~/Music (and ~/Downloads when asked; macOS may ask permission for that).
    @discardableResult
    func findNAMSignal(inDownloads: Bool) -> Bool {
        let fm = FileManager.default
        var dirs: [URL] = []
        if inDownloads, let d = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first { dirs.append(d) }
        if let m = fm.urls(for: .musicDirectory, in: .userDomainMask).first { dirs.append(m) }
        func match(_ n: String) -> Bool { n.lowercased().hasPrefix("t3k-sweep-v3") && n.lowercased().hasSuffix(".wav") }
        for d in dirs {
            let top = (try? fm.contentsOfDirectory(at: d, includingPropertiesForKeys: nil)) ?? []
            if let f = top.first(where: { match($0.lastPathComponent) }) { loadNAMSignal(f); return true }
            for sub in top where (try? sub.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                if let f = ((try? fm.contentsOfDirectory(at: sub, includingPropertiesForKeys: nil)) ?? []).first(where: { match($0.lastPathComponent) }) {
                    loadNAMSignal(f); return true
                }
            }
        }
        if inDownloads { namSignalStatus = "T3K-sweep-v3.wav isn't in Downloads or Music. Download it from TONE3000 (button above), then try again, or choose it yourself." }
        return false
    }

    /// Reads and checks the sweep file. The app remembers where it is for next time.
    @discardableResult
    func loadNAMSignal(_ u: URL) -> Task<Void, Never> {
        namSignalStatus = "Checking \(u.lastPathComponent)…"
        namSignal = nil
        return Task {
            do {
                let x = try await Task.detached(priority: .userInitiated) { () -> [Float] in
                    let info = try WavInfo(Data(contentsOf: u, options: .mappedIfSafe))
                    let d = try info.channel(0)
                    try NAMPrep.checkSignalFile(d, fs: info.fs)
                    return d.map { Float($0) }
                }.value
                namSignal = x
                namSignalPath = u.path
                namSignalStatus = nil
                Log.write("NAM signal OK: \(u.path)")
            } catch {
                namSignalStatus = "\(u.lastPathComponent): \(error.localizedDescription)"
            }
        }
    }

    var namSignalName: String { URL(fileURLWithPath: namSignalPath).lastPathComponent }

    var namDirectProblem: String? {
        guard namSignal != nil else { return "Choose TONE3000's sweep file in step 1." }
        if simulateIO { return nil }
        guard let dev = device else { return "Choose an audio interface in step 2." }
        if !dev.sampleRates.isEmpty && !dev.sampleRates.contains(NAMPrep.fs) {
            return "\(dev.name) can't run at 48 kHz, which the training signal needs. Choose another interface."
        }
        let used = namRows.filter(\.use)
        guard !used.isEmpty else { return "Choose Use for at least one input in step 2." }
        var seen = Set<String>()
        for r in used {
            let k = NAMPrep.safe(r.name).lowercased()
            if seen.contains(k) { return "Two inputs are both named “\(r.name)”. Give each a different name." }
            seen.insert(k)
        }
        return nil
    }

    private func pushNAMMeters(_ rows: [NAMRow], _ peaks: [Float]) {
        let keep = 140                                  // about 7 s of 50 ms readings
        var out: [NAMMeter] = []
        for (r, p) in zip(rows, peaks) {
            var h = namMeterHistory[r.id] ?? []
            h.append(p); if h.count > keep { h.removeFirst(h.count - keep) }
            namMeterHistory[r.id] = h
            if p >= 0.999 { namClipped.insert(r.id) }
            let pk = h.max() ?? 0
            out.append(NAMMeter(id: r.id, label: r.name, peakDB: pk > 0 ? 20 * log10(Double(pk)) : -120, clipped: namClipped.contains(r.id)))
        }
        namMeters = out
    }

    private func resetNAMMeters() { namMeterHistory = [:]; namClipped = []; namMeters = [] }

    func toggleNAMLevelCheck() {
        if namLevelRunning { stopLevelChecks(); return }
        if let p = namDirectProblem { namLevelError = p; return }
        guard let sig = namSignal, let dev = device, busy == nil else { return }
        stopLevelChecks()                 // the cab one, if it's running
        namLevelError = nil; resetNAMMeters(); namLevelRunning = true
        namGen += 1
        let gen = namGen, wait = audioChain
        let (a, n) = NAMPrep.levelSection(sig)
        let section = Array(sig[a..<(a + n)])
        let out = namOutChannel
        Log.write("NAM level check start: \(dev.name), output \(out + 1)")
        let t = Task {
            defer {
                if gen == namGen { namLevelRunning = false; namLevelTask = nil }
                jobEnded()
            }
            await wait?.value
            if Task.isCancelled { return }
            takeRate(dev)
            guard await microphoneAllowed() else { namLevelError = micDenied; return }
            do {
                try await Task.detached { try CoreAudioHelper.setNominalRate(dev.id, NAMPrep.fs) }.value
                while !Task.isCancelled {
                    let rows = namRows.filter(\.use)
                    if rows.isEmpty { namLevelError = "Choose Use for at least one input."; return }
                    _ = try await DuplexIO.run(device: dev, fs: NAMPrep.fs, outChannel: out, inputs: rows.map(\.id), signal: section,
                                               extraSeconds: 0.2, cancelled: { Task.isCancelled },
                                               meter: { p in Task { @MainActor in if self.namLevelRunning { self.pushNAMMeters(rows, p) } } })
                }
            } catch is CancellationError {
            } catch {
                Log.write("NAM level check error: \(error.localizedDescription)")
                if gen == namGen { namLevelError = error.localizedDescription }
            }
        }
        namLevelTask = t
        audioChain = t
    }

    /// Simulated interface for CI: input k hears the signal after 1234 + 150·k samples, at gain 0.5 or −0.3.
    private nonisolated static func simulatedRecording(_ signal: [Float], inputs: Int, extraSeconds: Double) -> [[Float]] {
        let total = signal.count + Int(extraSeconds * Double(NAMPrep.fs))
        return (0..<inputs).map { k in
            let lat = 1234 + 150 * k, g: Float = k == 0 ? 0.5 : -0.3
            var y = [Float](repeating: 0, count: total)
            for i in 0..<signal.count where i + lat < total { y[i + lat] = g * signal[i] }
            return y
        }
    }

    func startNAMCapture() {
        if let p = namDirectProblem { namError = p; return }
        guard let sig = namSignal else { return }
        guard busy == nil else { return }
        stopLevelChecks()
        namError = nil
        let rows = simulateIO ? namRows : namRows.filter(\.use)
        let names = rows.map { NAMPrep.safe($0.name) }
        let dev = device, out = namOutChannel, kind = namKind, outDir = outputFolder, sim = simulateIO
        let capture = uniqueCaptureName(NAMPrep.safe(namName.isEmpty ? "Amp" : namName))
        let rawDir = outDir.appendingPathComponent(capture).appendingPathComponent("raw recording")
        resetNAMMeters()
        Log.write("NAM record \(capture): \(sim ? "simulated" : dev?.name ?? "?"), output \(out + 1), inputs \(zip(names, rows.map { $0.id + 1 }).map { "\($0.0)=\($0.1)" })")
        busy = .preparing("Getting ready")
        let wait = audioChain
        let t = Task {
            defer { busy = nil; captureTask = nil; jobEnded() }
            await wait?.value
            if Task.isCancelled { namError = "Recording stopped. Nothing was saved."; return }
            if let dev, !sim { takeRate(dev) }
            var rawSaved = false
            do {
                let rec: [[Float]]
                let io = Box<DuplexIO.Report>()
                if sim {
                    busy = .namRecording(0)
                    let nIn = rows.count
                    rec = await Task.detached { AppModel.simulatedRecording(sig, inputs: nIn, extraSeconds: 2.0) }.value
                } else {
                    guard let dev else { return }
                    guard await microphoneAllowed() else { namError = micDenied; return }
                    busy = .preparing("Setting the interface to 48 kHz")
                    try await Task.detached { try CoreAudioHelper.setNominalRate(dev.id, NAMPrep.fs) }.value
                    busy = .namRecording(0)
                    rec = try await DuplexIO.run(device: dev, fs: NAMPrep.fs, outChannel: out, inputs: rows.map(\.id), signal: sig,
                                                 extraSeconds: 2.0, cancelled: { Task.isCancelled },
                                                 progress: { p in Task { @MainActor in if case .namRecording = self.busy { self.busy = .namRecording(p) } } },
                                                 meter: { p in Task { @MainActor in self.pushNAMMeters(rows, p) } },
                                                 report: { io.value = $0 })
                }
                busy = .processing("Saving the raw recording")
                try await Task.detached {
                    try FileManager.default.createDirectory(at: rawDir, withIntermediateDirectories: true)
                    for (n, x) in zip(names, rec) {
                        try NAMPrep.wav24(x.map(Double.init)).write(to: rawDir.appendingPathComponent("\(capture)_\(n)_raw.wav"))
                    }
                }.value
                rawSaved = true
                let report: (String) -> Void = { t in Task { @MainActor in self.busy = .processing(t) } }
                var extra: [(String, JSON)] = [
                    ("recorded_with", .string(sim ? "simulated" : "direct")),
                    ("channels", .object([
                        ("interface", .string(sim ? "simulated" : dev?.name ?? "")),
                        ("output", .int(out + 1)),
                        ("inputs", .object(zip(names, rows).map { ($0.0, JSON.int($0.1.id + 1)) }))])),
                    ("app", .string("\(Product.name) (Mac) \(Product.fullVersion)")),
                ]
                if let r = io.value { extra.append(("io", r.json)) }
                try await finishNAM(channels: zip(names, rec).map { ($0.0, $0.1.map(Double.init), NAMPrep.fs) },
                                    kind: kind, capture: capture, outDir: outDir, extra: extra,
                                    dropout: io.value?.dropoutWarning, report: report)
            } catch is CancellationError {
                namError = "Recording stopped. Nothing was saved."
            } catch {
                Log.write("NAM record error: \(error.localizedDescription)")
                namError = error.localizedDescription
                    + (rawSaved ? " The raw recording is saved in “\(capture)/raw recording”. You can drop those files into Import DAW recordings to try again." : "")
            }
        }
        captureTask = t
        audioChain = t
    }

    /// Lines up, checks and writes the prepared files (shared by both NAM routes).
    private func finishNAM(channels: [(String, [Double], Int)], kind: NAMKind, capture: String, outDir: URL,
                           extra: [(String, JSON)], dropout: String? = nil, report: @escaping (String) -> Void) async throws {
        let (res, folder) = try await Task.detached(priority: .userInitiated) { () -> (NAMResult, URL) in
            var done: [(name: String, result: NAMChannelResult)] = []
            for (name, x, fs) in channels {
                done.append((name, try NAMPrep.prepareChannel(x, fs: fs, label: name, progress: { report($0) })))
            }
            var res = NAMPrep.finish(kind: kind, channels: done)
            if let dropout { res.warnings.insert(dropout + " A dropout misaligns the training data, so a model from this take won't be accurate.", at: 0) }
            report("Saving files")
            return (res, try NAMPrep.write(res, capture: capture, outDir: outDir, extra: extra))
        }.value
        namResult = NAMSummary(title: capture, kind: res.kind, names: res.names, diagnostics: res.diagnostics, warnings: res.warnings,
                               notes: res.notes, folder: folder, files: res.names.map { NAMPrep.fileName(capture, $0) }, droppedOut: dropout != nil)
    }

    /// CI smoke test: record through the simulated interface using the stand-in sweep file in `dir`.
    func runNAMDirectDemo(_ dir: URL) {
        simulateIO = true
        job = .nam
        namMode = "app"
        outputFolder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("IRCaptureDemo")
        namName = "namdirect"
        namKind = .full
        namRows = [NAMRow(id: 0, use: true, name: "Suhr"), NAMRow(id: 1, use: true, name: "SM57")]
        let t = loadNAMSignal(dir.appendingPathComponent("standin_signal.wav"))
        Task { await t.value; if namSignal != nil { startNAMCapture() } else { namError = namSignalStatus } }
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
