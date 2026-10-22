import Foundation

// ---------------------------------------------------------------- level check
// Port of cmd_level in ircapture.py: short sweeps, per-input peak and H2/H3.

public struct LevelReading: Identifiable {
    public var id: String { label }
    public var label: String
    public let peakDBFS: Double
    public let target: Double
    public let h2: Double
    public let h3: Double
    /// Energy more than 5 ms after the main peak, relative to the whole response (dB). A reference tap
    /// (a near-perfect impulse) sits far below a mic, which always has some cabinet and room tail.
    public var tailDB: Double = 0
    /// Arrival of the response, in samples from the start of the deconvolved recording. Only compare
    /// it between inputs recorded in the same pass.
    public var onset: Int = 0
    /// Interface input (0-based); set by the caller.
    public var channel: Int = 0
    public var clipped: Bool { peakDBFS > -0.3 }
    /// dB to change the preamp by to reach the target.
    public var changeDB: Double { target - peakDBFS }
}

public final class LevelCheck {
    public let spec: SweepSpec
    public let signal: [Float]
    private let invK: KernelSpectrum

    public init(fs: Int, levelDBFS: Double) throws {
        spec = try SweepSpec(fs: fs, duration: 1.5, nSweeps: 1, discard: 0, gap: 1.0, lead: 0.2, levelDBFS: levelDBFS)
        signal = makeTestSignal(spec)
        let inv = inverseFilter(makeSweep(spec), spec)
        invK = KernelSpectrum(inv, nextPow2(2 * inv.count))
    }

    public func read(_ rec: [[Double]], labels: [String], target: Double = -6) -> [LevelReading] {
        let fs = Double(spec.fs), w = Int(DIST_WIN_S * fs)
        return zip(labels, rec).map { (lab, row) in
            let pk = 20 * log10(max(absMax(row), 1e-9))
            let h = convolveOLA(row, invK)
            let q = argAbsMax(h, 0, h.count)
            func energy(_ c: Int) -> Double {
                var e = 0.0
                for n in max(0, c - 50)..<min(h.count, max(0, c + w)) { e += Double(h[n]) * Double(h[n]) }
                return e
            }
            let e1 = energy(q)
            let c2 = q - iround(spec.harmonicAdvance(2) * fs), c3 = q - iround(spec.harmonicAdvance(3) * fs)
            let f5 = iround(0.005 * fs), f1ms = iround(0.001 * fs)
            var late = 0.0, all = 0.0
            for n in max(0, q - f1ms)..<min(h.count, q + w) {
                let e = Double(h[n]) * Double(h[n])
                all += e
                if n >= q + f5 { late += e }
            }
            let thr = abs(Double(h[q])) * 0.1                // 20 dB below the peak
            var on = q
            var n = q
            while n > max(0, q - 2 * f1ms) { n -= 1; if abs(Double(h[n])) > thr { on = n } }
            return LevelReading(label: lab, peakDBFS: pk, target: target, h2: db10(energy(c2) / e1), h3: db10(energy(c3) / e1),
                                tailDB: db10(late / max(all, 1e-30)), onset: on)
        }
    }

    /// The input that looks like a reference tap: it arrives first by at least 0.05 ms among inputs with
    /// signal, and its response has almost no tail. A suggestion only; nil when nothing clearly fits.
    public func referenceCandidate(_ readings: [LevelReading]) -> LevelReading? {
        let live = readings.filter { $0.peakDBFS > -40 }
        guard live.count >= 2, let first = live.min(by: { $0.onset < $1.onset }) else { return nil }
        let lead = Double(live.filter { $0.channel != first.channel }.map(\.onset).min()! - first.onset) / Double(spec.fs) * 1000
        return lead >= 0.05 && first.tailDB < -30 ? first : nil
    }
}

// ---------------------------------------------------------------- whole job
public struct ProcessedCapture {
    public var result: AnalysisResult
    public var fileCount: Int
    public var folder: URL
    public var curves: (fc: [Double], curves: [String: [Double]])
    public var polarityNotes: [String] = []
    /// Room-mic and extras notes from the export.
    public var exportNotes: [String] = []
    /// Paths of the files written, relative to the capture folder.
    public var files: [String] = []
}

/// How the IR files are laid out in the capture folder.
public enum OutputLayout {
    /// The original matrix: <capture>/<trim>/<rate>/<capture>_<mic>_<rate>_<bits>_<length>.wav (matches the page and Python).
    case matrix
    /// Export targets: Universal files at the top, the rest under More formats, plus README.txt.
    case targets([ExportTarget], custom: ExportOptions?)
}

/// Analyse, export every IR into `outDir/<capture>/...`, and write report.json.
public func processAndWrite(rec: [[Double]], spec: SweepSpec, names: [String], refIndex: Int?, capture: String,
                            outDir: URL, export: ExportOptions = ExportOptions(), layout: OutputLayout = .matrix,
                            keepPolarity: Bool = false, process: ProcessOptions? = nil,
                            extra: [(String, JSON)] = [], extraWarnings: [String] = [],
                            progress: Progress = { _ in }) throws -> ProcessedCapture {
    var fullMs = export.fullMs
    if case .targets(_, let c) = layout { fullMs = max(targetFullMs, c?.fullMs ?? 0) }
    let popt = process ?? ProcessOptions(irMax: max(1.0, fullMs / 1000 + 0.05))
    var res = try analyse(rec, spec, names: names, refIndex: refIndex, options: popt, progress: progress)
    res.warnings = extraWarnings + res.warnings
    let notes = normalizePolarity(&res, keep: keepPolarity)
    let files: [ExportFile]
    switch layout {
    case .matrix: files = exportFiles(&res, capture: capture, options: export, progress: progress)
    case .targets(let t, let c): files = exportTargets(&res, capture: capture, targets: t, custom: c, progress: progress)
    }
    progress("Saving files")
    let fm = FileManager.default
    for f in files {
        let url = outDir.appendingPathComponent(f.path)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try f.data.write(to: url)
    }
    let folder = outDir.appendingPathComponent(capture)
    try fm.createDirectory(at: folder, withIntermediateDirectories: true)
    try reportJSON(res, spec: spec, capture: capture, extra: extra).write(to: folder.appendingPathComponent("report.json"), atomically: true, encoding: .utf8)
    if case .targets(let t, let c) = layout {
        try captureReadme(capture: capture, names: names, targets: t, custom: c != nil, referenced: res.referenced,
                          polarityNotes: notes, warnings: res.warnings, notes: res.exportNotes)
            .write(to: folder.appendingPathComponent("README.txt"), atomically: true, encoding: .utf8)
    }
    let g = res.gains["set"]?[names[0]] ?? res.gains["individual"]?[names[0]] ?? 1
    let prefix = capture + "/"
    return ProcessedCapture(result: res, fileCount: files.count, folder: folder, curves: responseCurves(res, gain: g),
                            polarityNotes: notes, exportNotes: res.exportNotes, files: files.map { $0.path.hasPrefix(prefix) ? String($0.path.dropFirst(prefix.count)) : $0.path })
}
