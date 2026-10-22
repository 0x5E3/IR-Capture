import Foundation

// Deconvolution, sweep location, averaging, diagnostics and reference division.
// A port of analyse() in dsp.js (itself a port of ircapture.py). Keep them in step.

public struct ChannelDiagnostics {
    public var recordingPeakDBFS: Double
    public var noiseFloorDB: Double?
    public var tailAboveNoiseMs: Double?
    public var sweepLevelSpreadDB: Double?
    public var sweepMinCorrelation: Double?
    /// H2...H5 relative to the linear response, dB; nil when below the noise.
    public var harmonics: [Double?] = []
    public var arrivalMs: Double?
    public var delayVsFirstMicMs: Double?

    /// Loudest measured harmonic and its number, if any rose above the noise.
    public var worstHarmonic: (n: Int, db: Double)? {
        var best: (Int, Double)?
        for (i, v) in harmonics.enumerated() { if let v = v, best == nil || v > best!.1 { best = (i + 2, v) } }
        return best
    }

    var json: JSON {
        var o: [(String, JSON)] = [("recording_peak_dbfs", .number(recordingPeakDBFS))]
        if let v = noiseFloorDB { o.append(("noise_floor_db", .number(v))) }
        if let v = tailAboveNoiseMs { o.append(("tail_above_noise_ms", .number(v))) }
        if let v = sweepLevelSpreadDB { o.append(("sweep_level_spread_db", .number(v))) }
        if let v = sweepMinCorrelation { o.append(("sweep_min_correlation", .number(v))) }
        o.append(("harmonics_db", .object(harmonics.enumerated().map { ("H\($0.offset + 2)", JSON.opt($0.element)) })))
        if let v = arrivalMs { o.append(("arrival_ms", .number(v))) }
        if let v = delayVsFirstMicMs { o.append(("delay_vs_first_mic_ms", .number(v))) }
        return .object(o)
    }
}

public struct AnalysisResult {
    public var names: [String]
    public var irs: [String: [Double]]
    public var fs: Int
    public var t0: Int
    public var onsets: [String: Int]
    public var referenced: Bool
    public var sweepsUsed: Int
    public var timingJitterSamples: Int
    public var analysisWindowS: Double
    /// In channel order; the reference tap is labelled "reference".
    public var diagnostics: [(label: String, diag: ChannelDiagnostics)]
    public var warnings: [String]
    public var gains: [String: [String: Double]] = [:]
    /// Set by normalizePolarity(); nil until then.
    public var polarity: [String: PolarityInfo] = [:]
    public var polarityMode: String? = nil
    /// Set by the extras export (minimum phase, room mics, mixes); nil when none were asked for.
    public var extras: JSON? = nil
    /// Plain-language notes from the export (room mics and the like), for the results and README.
    public var exportNotes: [String] = []

    public var mode: String { referenced ? "reference" : "sweep" }
    public func diag(_ label: String) -> ChannelDiagnostics? { diagnostics.first { $0.label == label }?.diag }
}

public struct ProcessOptions {
    public var irMax = 1.0
    public var regDB = 40.0
    public var onsetDB = 20.0
    public init(irMax: Double = 1.0, regDB: Double = 40.0, onsetDB: Double = 20.0) {
        self.irMax = irMax; self.regDB = regDB; self.onsetDB = onsetDB
    }
}

public typealias Progress = (String) -> Void

func absMax<C: RandomAccessCollection>(_ a: C, _ s0: Int = 0, _ s1: Int? = nil) -> Double where C.Element: BinaryFloatingPoint, C.Index == Int {
    var m = 0.0
    let e = s1 ?? a.count
    var i = s0
    while i < e { let v = abs(Double(a[i])); if v > m { m = v }; i += 1 }
    return m
}

func argAbsMax<C: RandomAccessCollection>(_ a: C, _ s0: Int, _ s1: Int) -> Int where C.Element: BinaryFloatingPoint, C.Index == Int {
    var m = -1.0, k = s0, i = s0
    while i < s1 { let v = abs(Double(a[i])); if v > m { m = v; k = i }; i += 1 }
    return k
}

func locateImpulses(_ h: [Float], _ s: SweepSpec, tol: Int = 4) -> (expected: [Int], jitter: Int) {
    let P = s.period, g = argAbsMax(h, 0, h.count), gv = abs(Double(h[g]))
    func peakNear(_ i: Int) -> Int? {
        let lo = max(0, i - tol), hi = min(h.count, i + tol + 1)
        if lo >= hi { return nil }
        let j = argAbsMax(h, lo, hi)
        return abs(Double(h[j])) > 0.5 * gv ? j : nil
    }
    var first = g
    while let j = peakNear(first - P) { first = j }
    var found = [first]
    while let j = peakNear(found.last! + P) { found.append(j) }
    var expected: [Int] = [], jitter = 0
    for k in 0..<found.count {
        expected.append(first + k * P)
        jitter = max(jitter, abs(found[k] - expected[k]))
    }
    return (expected, jitter)
}

func bandWeight(_ f: Double, _ f1: Double, _ f2: Double, _ nyq: Double) -> Double {
    let loA = f1 / 2, loB = f1 * 1.5, hiA = f2 * 0.8, hiB = min(f2 * 1.25, nyq)
    let lf = log2(max(f, 1e-3))
    func ramp(_ x0: Double, _ x1: Double) -> Double { min(1, max(0, (lf - log2(x0)) / (log2(x1) - log2(x0)))) }
    let lo = 1 - ramp(loA, loB), hi = ramp(hiA, hiB)
    let e = 6 * max(0.5 - 0.5 * cos(Double.pi * lo), 0.5 - 0.5 * cos(Double.pi * hi))
    return pow(10, e)
}

func divideByReference(_ hm: [Double], _ hr: [Double], _ s: SweepSpec, _ npre: Int, _ regDB: Double) -> [Double] {
    let W = hm.count, nfft = nextPow2(2 * W), fs = Double(s.fs)
    var mr = [Double](repeating: 0, count: nfft), mi = mr, rr = mr, ri = mr
    for i in 0..<W { mr[i] = hm[i]; rr[i] = hr[i] }
    fft(&mr, &mi, inverse: false); fft(&rr, &ri, inverse: false)
    var pmax = 0.0, pr = [Double](repeating: 0, count: nfft)
    for i in 0..<nfft { pr[i] = rr[i] * rr[i] + ri[i] * ri[i]; if pr[i] > pmax { pmax = pr[i] } }
    let base = pmax * pow(10, -regDB / 10)
    for i in 0..<nfft {
        let bin = i <= nfft / 2 ? i : nfft - i
        let eps = base * bandWeight(Double(bin) * fs / Double(nfft), s.f1, s.f2, fs / 2)
        let den = pr[i] + eps
        let a = mr[i], b = mi[i], c = rr[i], d = -ri[i]
        mr[i] = (a * c - b * d) / den; mi[i] = (a * d + b * c) / den
    }
    fft(&mr, &mi, inverse: true)
    var out = [Double](repeating: 0, count: W)
    for i in 0..<npre { out[i] = mr[nfft - npre + i] }
    for i in npre..<W { out[i] = mr[i - npre] }
    return out
}

public func onsetIndex(_ h: [Double], _ thrDB: Double) -> Int {
    let pk = absMax(h), thr = pk * pow(10, -thrDB / 20)
    for i in 0..<h.count where abs(h[i]) > thr { return i }
    return 0
}

func db10(_ x: Double) -> Double { 10 * log10(max(x, 1e-30)) }
func roundTo(_ x: Double, _ d: Int) -> Double { let p = pow(10.0, Double(d)); return jsRound(x * p) / p }
func f1(_ x: Double) -> String { String(format: "%.1f", x) }

/// rec: one array per recorded channel at s.fs. names: one per non-reference channel, in order.
public func analyse(_ rec: [[Double]], _ s: SweepSpec, names: [String], refIndex: Int?,
                    options opt: ProcessOptions = ProcessOptions(), progress: Progress = { _ in }) throws -> AnalysisResult {
    let fs = s.fs, fsd = Double(fs), C = rec.count
    let micRows = (0..<C).filter { $0 != refIndex }
    guard names.count == micRows.count else { throw IRCaptureError("\(micRows.count) mic channels but \(names.count) names") }
    let labels = (0..<C).map { $0 == refIndex ? "reference" : names[micRows.firstIndex(of: $0)!] }
    var warnings: [String] = []
    let recPeaks = rec.map { 20 * log10(max(absMax($0), 1e-12)) }
    for (i, p) in recPeaks.enumerated() {
        if p > -0.3 { warnings.append("\(labels[i]): the recording peaks at \(f1(p)) dBFS and has probably clipped. Lower that input's gain and record again.") }
        else if p < -30 { warnings.append("\(labels[i]): the recording peaks at only \(f1(p)) dBFS. Raise that input's gain.") }
    }

    progress("Building the inverse sweep")
    let inv = inverseFilter(makeSweep(s), s)
    var h: [[Float]] = []
    do {
        let K = KernelSpectrum(inv, nextPow2(2 * inv.count))
        for i in 0..<C {
            progress("Deconvolving \(labels[i]) (\(i + 1) of \(C))")
            h.append(convolveOLA(rec[i], K))
        }
    }

    var anchor = refIndex ?? 0
    if refIndex == nil {
        var best = -1.0
        for i in 0..<C { let m = absMax(h[i]); if m > best { best = m; anchor = i } }
    }
    progress("Finding the sweeps")
    let loc = locateImpulses(h[anchor], s)
    if loc.expected.count != s.nSweeps {
        warnings.append("Found \(loc.expected.count) sweeps but the test signal has \(s.nSweeps). Check that the sweep settings match the test signal you recorded, and that the whole pass was recorded.")
    }
    if loc.jitter > 1 {
        warnings.append("The sweeps drift by up to \(loc.jitter) samples. Playback and recording may not be on the same interface clock.")
    }

    let pre = iround((s.harmonicAdvance(Double(H_MAX) + 0.5) + 0.02) * fsd)
    let seglen = s.period
    var used: [Int] = []
    for (k, p) in loc.expected.enumerated() where k >= s.discard {
        if p - pre >= 0 && p - pre + seglen <= h[anchor].count { used.append(p) }
    }
    if used.isEmpty { throw IRCaptureError("No complete sweeps were found. Check that the sweep settings match the test signal you recorded.") }
    if used.count < 2 { warnings.append("Only one usable sweep, so the noise floor can't be measured.") }

    let irMax = min(opt.irMax, s.maxIRSeconds, Double(seglen - pre) / fsd - 0.05)
    if irMax < opt.irMax - 1e-9 {
        warnings.append("The analysis window was shortened to \(String(format: "%.2f", irMax)) s by the sweep timing. Use a longer gap for longer room tails.")
    }
    let npre = iround(LIN_PRE_S * fsd), nlin = npre + iround(irMax * fsd)
    let a0 = pre - npre, keep = pre + nlin, Kn = used.count

    var avg: [[Double]] = [], linK: [[[Double]]] = [], lin: [[Double]] = []
    for i in 0..<C {
        var A = [Double](repeating: 0, count: keep)
        var LK: [[Double]] = []
        h[i].withUnsafeBufferPointer { hi in
            for k in 0..<Kn {
                let o = used[k] - pre
                for n in 0..<keep { A[n] += Double(hi[o + n]) }
                LK.append((0..<nlin).map { Double(hi[o + a0 + $0]) })
            }
        }
        for n in 0..<keep { A[n] /= Double(Kn) }
        avg.append(A); linK.append(LK); lin.append(Array(A[a0..<(a0 + nlin)]))
    }
    h = []

    progress("Measuring noise and distortion")
    var diags: [(String, ChannelDiagnostics)] = []
    let L = s.L, w = iround(DIST_WIN_S * fsd), g1 = iround(0.001 * fsd)
    for i in 0..<C {
        let x = lin[i], peak = absMax(x)
        var d = ChannelDiagnostics(recordingPeakDBFS: roundTo(recPeaks[i], 1))
        var noiseRms = 0.0
        if Kn >= 2 {
            var acc = 0.0
            for n in 0..<nlin {
                var ss = 0.0
                for k in 0..<Kn { let r = linK[i][k][n] - x[n]; ss += r * r }
                acc += ss
            }
            noiseRms = (acc / Double(nlin) / Double(Kn - 1) / Double(Kn)).squareRoot()
            d.noiseFloorDB = roundTo(20 * log10(max(noiseRms, 1e-30) / peak), 1)
            let wl = iround(0.01 * fsd), half = wl / 2
            var cs = [Double](repeating: 0, count: nlin + 1)
            for n in 0..<nlin { cs[n + 1] = cs[n] + x[n] * x[n] }
            var last = -1
            for n in 0..<nlin {
                let s0 = max(0, n - half), s1 = min(nlin, n - half + wl)
                let env = (max(0, cs[s1] - cs[s0]) / Double(wl)).squareRoot()
                if env > 2 * noiseRms { last = n }
            }
            let q = argAbsMax(x, 0, nlin)
            d.tailAboveNoiseMs = last >= 0 ? roundTo(Double(last - q) / fsd * 1000, 1) : 0
            var rmsX = 0.0; for n in 0..<nlin { rmsX += x[n] * x[n] }
            var lv: [Double] = [], cc: [Double] = []
            let nx = rmsX.squareRoot()
            for k in 0..<Kn {
                var e2 = 0.0, dot = 0.0
                let y = linK[i][k]
                for n in 0..<nlin { e2 += y[n] * y[n]; dot += y[n] * x[n] }
                lv.append(10 * log10(e2 / rmsX)); cc.append(dot / (e2.squareRoot() * nx))
            }
            d.sweepLevelSpreadDB = roundTo(lv.max()! - lv.min()!, 2)
            d.sweepMinCorrelation = roundTo(cc.min()!, 5)
        }
        let q = a0 + argAbsMax(x, 0, nlin)
        var eLin = 0.0
        for n in (q - g1)..<(q + w) { eLin += avg[i][n] * avg[i][n] }
        let eNoise = noiseRms * noiseRms * Double(w + g1)
        var hd: [Double?] = [], worst: Double? = nil
        for hn in 2...H_MAX {
            let c = q - iround(L * log(Double(hn)) * fsd)
            var e = 0.0
            for n in (c - g1)..<(c + w) where n >= 0 { e += avg[i][n] * avg[i][n] }
            let v: Double? = (Kn >= 2 && e < 2 * eNoise) ? nil : roundTo(db10(e / eLin), 1)
            hd.append(v)
            if let v = v, worst == nil || v > worst! { worst = v }
        }
        d.harmonics = hd
        if let wv = worst, wv > -30, i != refIndex {
            warnings.append("\(labels[i]): harmonic distortion is \(Int(jsRound(wv))) dB below the linear response. The speaker is being driven hard; an IR can't capture that, so try about 6 dB less level.")
        }
        diags.append((labels[i], d))
    }

    progress("Computing the impulse responses")
    var irs: [String: [Double]] = [:], onsets: [String: Int] = [:]
    for (j, nm) in names.enumerated() {
        let r = micRows[j]
        irs[nm] = refIndex != nil ? divideByReference(lin[r], lin[refIndex!], s, npre, opt.regDB) : lin[r]
        onsets[nm] = onsetIndex(irs[nm]!, opt.onsetDB)
    }
    let firstOn = names.map { onsets[$0]! }.min()!
    for k in 0..<diags.count {
        let nm = diags[k].0
        guard let on = onsets[nm], nm != "reference" || refIndex == nil else { continue }
        diags[k].1.arrivalMs = roundTo(Double(on - npre) / fsd * 1000, 3)
        diags[k].1.delayVsFirstMicMs = roundTo(Double(on - firstOn) / fsd * 1000, 3)
    }
    return AnalysisResult(names: names, irs: irs, fs: fs, t0: npre, onsets: onsets, referenced: refIndex != nil,
                          sweepsUsed: Kn, timingJitterSamples: loc.jitter, analysisWindowS: roundTo(irMax, 3),
                          diagnostics: diags.map { (label: $0.0, diag: $0.1) }, warnings: warnings)
}
