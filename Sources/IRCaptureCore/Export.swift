import Foundation

// Multi-rate, multi-length IR export. Port of exportFiles() in dsp.js.

public enum IRLength: Hashable, CustomStringConvertible {
    case full
    case samples(Int)
    public var description: String { if case .samples(let n) = self { return String(n) }; return "full" }
    public init?(_ s: String) {
        if s == "full" { self = .full } else if let n = Int(s), n > 0 { self = .samples(n) } else { return nil }
    }
}

public enum BitDepth: String, CaseIterable { case b16 = "16", b24 = "24", f32 = "32f" }
public enum TrimMode: String, CaseIterable { case set, individual }

public struct ExportOptions {
    public var rates: [Int] = [44100, 48000, 88200, 96000]
    public var lengths: [IRLength] = [.full, .samples(1024), .samples(2048), .samples(4096)]
    public var fullMs: Double = 500
    public var bits: [BitDepth] = [.b24]
    public var trim: [TrimMode] = [.set]
    public var prerollMs: Double = 0.25
    public var fadeFrac: Double = 0.10
    public var peakDBFS: Double = -1
    public init() {}
}

public struct ExportFile {
    public let path: String      // relative: <capture>/<mode>/<rate>/<file>.wav
    public let data: Data
}

public func safeName(_ s: String) -> String {
    var out = "", lastUnderscore = false
    for ch in s.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars {
        let ok = (ch.value < 128) && (CharacterSet.alphanumerics.contains(ch) || ch == "." || ch == "_" || ch == "-")
        if ok { out.unicodeScalars.append(ch); lastUnderscore = false }
        else if !lastUnderscore { out += "_"; lastUnderscore = true }
    }
    while out.hasPrefix("_") { out.removeFirst() }
    while out.hasSuffix("_") { out.removeLast() }
    return out.isEmpty ? "ir" : out
}

public func rateTag(_ r: Int) -> String {
    let v = Double(r) / 1000
    return (v == v.rounded() ? String(Int(v)) : String(v)) + "k"
}

// ------------------------------------------------------------------ resampling
private let KAISER_BETA = 8.6, ZC = 32.0, KT = 8192
private func besselI0(_ x: Double) -> Double {
    var s = 1.0, t = 1.0
    for k in 1..<60 { t *= (x / (2 * Double(k))) * (x / (2 * Double(k))); s += t; if t < 1e-17 * s { break } }
    return s
}
private let kaiserTab: [Double] = {
    let i0 = besselI0(KAISER_BETA)
    return (0...(KT + 1)).map { i in let v = min(1, Double(i) / Double(KT)); return besselI0(KAISER_BETA * (1 - v * v).squareRoot()) / i0 }
}()
@inline(__always) private func kaiserAt(_ u: Double, _ tab: UnsafeBufferPointer<Double>) -> Double {
    let p = u * Double(KT), i = Int(p), f = p - Double(i)
    return tab[i] * (1 - f) + tab[i + 1] * f
}

/// Band-limited windowed-sinc resampler: zero phase, preserves sample amplitude.
public func resampleTo(_ x: [Double], _ fs: Int, _ rate: Int) -> [Double] {
    if rate == fs { return x }
    let ratio = Double(rate) / Double(fs), c = min(1, ratio) * 0.97, halfW = ZC / c
    let n = iround(Double(x.count) * ratio)
    var y = [Double](repeating: 0, count: n)
    kaiserTab.withUnsafeBufferPointer { tab in
        x.withUnsafeBufferPointer { xp in
            for m in 0..<n {
                let t = Double(m) / ratio
                let lo = max(0, Int((t - halfW).rounded(.up))), hi = min(x.count - 1, Int((t + halfW).rounded(.down)))
                var acc = 0.0
                if lo <= hi {
                    for k in lo...hi {
                        let d = t - Double(k), a = c * d
                        let sinc = a == 0 ? 1 : sin(Double.pi * a) / (Double.pi * a)
                        acc += xp[k] * c * sinc * kaiserAt(abs(d) / halfW, tab)
                    }
                }
                y[m] = acc
            }
        }
    }
    return y
}

func cut(_ h: [Double], _ start: Int, _ n: Int, _ nIn: Int, _ fadeFrac: Double) -> [Double] {
    var out = [Double](repeating: 0, count: n)
    let s0 = max(start, 0), s1 = min(start + n, h.count)
    if s0 < s1 { for i in s0..<s1 { out[i - start] = h[i] } }
    if nIn > 0 { let w = halfHann(nIn, rising: true); for i in 0..<min(nIn, n) { out[i] *= w[i] } }
    let nf = max(Int((fadeFrac * Double(n)).rounded(.down)), 2)
    let w = halfHann(nf, rising: false)
    for i in 0..<nf { out[n - nf + i] *= w[i] }
    return out
}

/// Writes every requested rate x length x bit depth x trim mode. Also fills result.gains.
public func exportFiles(_ res: inout AnalysisResult, capture: String, options opt: ExportOptions = ExportOptions(),
                        progress: Progress = { _ in }) -> [ExportFile] {
    let fs = res.fs, names = res.names, onsets = res.onsets
    let preFs = opt.prerollMs / 1000 * Double(fs)
    var files: [ExportFile] = []
    var resampled: [String: [Double]] = [:]
    for rate in opt.rates {
        progress("Resampling to \(rateTag(rate))")
        for m in names {
            let g = Double(fs) / Double(rate)       // keep convolution gain equal across rates
            resampled["\(m)@\(rate)"] = resampleTo(res.irs[m]!, fs, rate).map { $0 * g }
        }
    }
    let firstOn = names.map { onsets[$0]! }.min()!
    for mode in opt.trim {
        var vars: [(mic: String, rate: Int, len: IRLength, x: [Double])] = []
        for rate in opt.rates {
            let setStart = iround((Double(firstOn) - preFs) * Double(rate) / Double(fs))
            let nIn = iround(opt.prerollMs / 1000 * Double(rate))
            for m in names {
                let hr = resampled["\(m)@\(rate)"]!
                let start = mode == .set ? setStart : iround((Double(onsets[m]!) - preFs) * Double(rate) / Double(fs))
                for ln in opt.lengths {
                    let n: Int
                    switch ln { case .full: n = iround(opt.fullMs / 1000 * Double(rate)); case .samples(let k): n = k }
                    vars.append((m, rate, ln, cut(hr, start, n, nIn, opt.fadeFrac)))
                }
            }
        }
        let target = pow(10, opt.peakDBFS / 20)
        var gains: [String: Double] = [:]
        if mode == .set {
            let g = target / vars.map { absMax($0.x) }.max()!
            for m in names { gains[m] = g }
        } else {
            for m in names { gains[m] = target / vars.filter { $0.mic == m }.map { absMax($0.x) }.max()! }
        }
        res.gains[mode.rawValue] = gains
        progress("Writing \(mode.rawValue)-trimmed files")
        for v in vars {
            let gg = gains[v.mic]!
            let y = v.x.map { $0 * gg }
            for b in opt.bits {
                let tag = rateTag(v.rate)
                let path = "\(capture)/\(mode.rawValue)/\(tag)/\(capture)_\(safeName(v.mic))_\(tag)_\(b.rawValue)_\(v.len).wav"
                files.append(ExportFile(path: path, data: writeWav(y, rate: v.rate, bits: b)))
            }
        }
    }
    return files
}

/// 1/6-octave smoothed magnitude of each mic IR (dB), for plotting.
public func responseCurves(_ res: AnalysisResult, gain: Double = 1) -> (fc: [Double], curves: [String: [Double]]) {
    let fc = (0..<160).map { 20 * pow(1000, Double($0) / 159) }
    var curves: [String: [Double]] = [:]
    let fs = Double(res.fs)
    for m in res.names {
        let h = res.irs[m]!, start = max(0, res.onsets[m]! - iround(0.00025 * fs))
        let n = min(h.count - start, iround(0.5 * fs))
        let nfft = nextPow2(max(n, 1 << 16))
        var re = [Double](repeating: 0, count: nfft), im = re
        for i in 0..<n { re[i] = h[start + i] * gain }
        fft(&re, &im, inverse: false)
        var P = [Double](repeating: 0, count: nfft / 2 + 1)
        for i in 0...(nfft / 2) { P[i] = re[i] * re[i] + im[i] * im[i] }
        var cs = [Double](repeating: 0, count: P.count + 1)
        for i in 0..<P.count { cs[i + 1] = cs[i] + P[i] }
        curves[m] = fc.map { c in
            let lo = max(1, Int((c * pow(2, -1.0 / 12) * Double(nfft) / fs).rounded(.down)))
            var hi = max(lo + 1, Int((c * pow(2, 1.0 / 12) * Double(nfft) / fs).rounded(.up)))
            hi = min(hi, P.count)
            return roundTo(db10((cs[hi] - cs[lo]) / Double(hi - lo)), 2)
        }
    }
    return (fc, curves)
}

/// report.json, same fields and order as the page's.
public func reportJSON(_ res: AnalysisResult, spec: SweepSpec, capture: String, extra: [(String, JSON)] = []) -> String {
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    var o: [(String, JSON)] = [
        ("capture", .string(capture)), ("created", .string(iso.string(from: Date()))),
        ("ircapture_version", .string(IRCaptureVersion)), ("sweep", spec.json),
        ("mode", .string(res.mode)), ("sweeps_used", .int(res.sweepsUsed)),
        ("timing_jitter_samples", .int(res.timingJitterSamples)), ("analysis_window_s", .number(res.analysisWindowS)),
        ("diagnostics", .object(res.diagnostics.map { ($0.label, $0.diag.json) })),
        ("warnings", .array(res.warnings.map { .string($0) })),
    ]
    if let mode = res.polarityMode {
        o.append(("polarity", .object([("mode", .string(mode)), ("mics", .object(res.names.compactMap { m in
            res.polarity[m].map { p in (m, JSON.object([("main_peak", .string(p.mainPeakNegative ? "negative" : "positive")), ("flipped", .bool(p.flipped))])) }
        }))])))
    }
    o += extra
    return JSON.object(o).serialized()
}

/// Plain-text summary, like summary_text() in ircapture.py.
public func summaryText(_ res: AnalysisResult) -> String {
    var lines = ["mode: \(res.mode)-referenced, \(res.sweepsUsed) sweeps averaged, timing jitter \(res.timingJitterSamples) samples"]
    for (name, d) in res.diagnostics {
        let hd = d.harmonics.enumerated().map { "H\($0.offset + 2) " + ($0.element.map { String(format: "%.0f", $0) } ?? "<noise") }.joined(separator: ", ")
        var parts = [String(format: "peak %.1f dBFS", d.recordingPeakDBFS)]
        if let nf = d.noiseFloorDB {
            parts += [String(format: "noise %.0f dB", nf), String(format: "tail %.0f ms", d.tailAboveNoiseMs ?? 0),
                      String(format: "sweep spread %.2f dB", d.sweepLevelSpreadDB ?? 0)]
        }
        if let a = d.arrivalMs { parts.append(String(format: "arrival %.2f ms", a)) }
        lines.append("  " + name.padding(toLength: max(12, name.count), withPad: " ", startingAt: 0) + " " + parts.joined(separator: " | ") + " | " + hd)
    }
    for w in res.warnings { lines.append("  ! " + w) }
    return lines.joined(separator: "\n")
}
