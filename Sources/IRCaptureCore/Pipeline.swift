import Foundation

// ---------------------------------------------------------------- level check
// Port of cmd_level in ircapture.py: short sweeps, per-input peak and H2/H3.

public struct LevelReading: Identifiable {
    public var id: String { label }
    public let label: String
    public let peakDBFS: Double
    public let target: Double
    public let h2: Double
    public let h3: Double
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
            return LevelReading(label: lab, peakDBFS: pk, target: target, h2: db10(energy(c2) / e1), h3: db10(energy(c3) / e1))
        }
    }
}

// ---------------------------------------------------------------- whole job
public struct ProcessedCapture {
    public var result: AnalysisResult
    public var fileCount: Int
    public var folder: URL
    public var curves: (fc: [Double], curves: [String: [Double]])
}

/// Analyse, export every IR into `outDir/<capture>/...`, and write report.json.
public func processAndWrite(rec: [[Double]], spec: SweepSpec, names: [String], refIndex: Int?, capture: String,
                            outDir: URL, export: ExportOptions = ExportOptions(), process: ProcessOptions? = nil,
                            extra: [(String, JSON)] = [], progress: Progress = { _ in }) throws -> ProcessedCapture {
    let popt = process ?? ProcessOptions(irMax: max(1.0, export.fullMs / 1000 + 0.05))
    var res = try analyse(rec, spec, names: names, refIndex: refIndex, options: popt, progress: progress)
    let files = exportFiles(&res, capture: capture, options: export, progress: progress)
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
    let g = res.gains["set"]?[names[0]] ?? res.gains["individual"]?[names[0]] ?? 1
    return ProcessedCapture(result: res, fileCount: files.count, folder: folder, curves: responseCurves(res, gain: g))
}
