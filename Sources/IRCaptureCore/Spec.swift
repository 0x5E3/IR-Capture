import Foundation

public let IRCaptureVersion = "0.1-swift"

let H_MAX = 5            // highest harmonic measured / guarded against
let LIN_PRE_S = 0.020    // seconds kept before the anchor impulse
let DIST_WIN_S = 0.050   // window for harmonic-vs-linear energy

public struct IRCaptureError: Error, LocalizedError, CustomStringConvertible {
    public let message: String
    public init(_ m: String) { message = m }
    public var errorDescription: String? { message }
    public var description: String { message }
}

/// JavaScript's Math.round (half rounds toward +infinity). Used everywhere the
/// reference implementation rounds, so indices match exactly.
@inline(__always) func jsRound(_ x: Double) -> Double { (x + 0.5).rounded(.down) }
@inline(__always) func iround(_ x: Double) -> Int { Int(jsRound(x)) }

/// Log-sweep test signal settings. Mirrors SweepSpec in ircapture.py and makeSpec in dsp.js.
public struct SweepSpec: Equatable {
    public var fs: Int = 96000
    public var f1: Double = 20
    public var f2: Double = 22000
    public var duration: Double = 6
    public var nSweeps: Int = 5
    public var discard: Int = 1
    public var gap: Double = 2
    public var lead: Double = 1
    public var levelDBFS: Double = -12
    public var fadeIn: Double = 0.1
    public var fadeOut: Double = 0.005

    public init(fs: Int = 96000, f1: Double = 20, f2: Double = 22000, duration: Double = 6,
                nSweeps: Int = 5, discard: Int = 1, gap: Double = 2, lead: Double = 1,
                levelDBFS: Double = -12, fadeIn: Double = 0.1, fadeOut: Double = 0.005) throws {
        self.fs = fs; self.f1 = f1; self.f2 = f2; self.duration = duration; self.nSweeps = nSweeps
        self.discard = discard; self.gap = gap; self.lead = lead; self.levelDBFS = levelDBFS
        self.fadeIn = fadeIn; self.fadeOut = fadeOut
        try validate()
    }

    public mutating func validate() throws {
        f2 = min(f2, 0.45 * Double(fs))
        guard f1 > 0 && f1 < f2 else { throw IRCaptureError("Sweep range is invalid.") }
        guard nSweeps - discard >= 1 else { throw IRCaptureError("Use more sweeps than you discard.") }
    }

    public var L: Double { duration / log(f2 / f1) }
    public var nSweep: Int { iround(duration * Double(fs)) }
    public var nGap: Int { iround(gap * Double(fs)) }
    public var nLead: Int { iround(lead * Double(fs)) }
    public var period: Int { nSweep + nGap }
    public func harmonicAdvance(_ n: Double) -> Double { L * log(n) }
    public var maxIRSeconds: Double { gap + duration - harmonicAdvance(10) - 0.05 }
    /// Length of the full test signal in samples.
    public var signalLength: Int { nLead + nSweeps * period + Int((0.5 * Double(fs)).rounded(.down)) }

    public var json: JSON {
        .object([("fs", .int(fs)), ("f1", .number(f1)), ("f2", .number(f2)), ("duration", .number(duration)),
                 ("n_sweeps", .int(nSweeps)), ("discard", .int(discard)), ("gap", .number(gap)),
                 ("lead", .number(lead)), ("level_dbfs", .number(levelDBFS)), ("fade_in", .number(fadeIn)),
                 ("fade_out", .number(fadeOut)), ("ircapture_version", .string(IRCaptureVersion))])
    }

    /// Reads the .json written next to a test signal (by the page, the Python tool or this app).
    public static func load(jsonData: Data) throws -> SweepSpec {
        guard let d = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw IRCaptureError("The sweep settings file isn't valid.")
        }
        func num(_ k: String) -> Double? { (d[k] as? NSNumber)?.doubleValue }
        var s = try SweepSpec()
        if let v = num("fs") { s.fs = Int(v) }
        if let v = num("f1") { s.f1 = v }
        if let v = num("f2") { s.f2 = v }
        if let v = num("duration") { s.duration = v }
        if let v = num("n_sweeps") { s.nSweeps = Int(v) }
        if let v = num("discard") { s.discard = Int(v) }
        if let v = num("gap") { s.gap = v }
        if let v = num("lead") { s.lead = v }
        if let v = num("level_dbfs") { s.levelDBFS = v }
        if let v = num("fade_in") { s.fadeIn = v }
        if let v = num("fade_out") { s.fadeOut = v }
        try s.validate()
        return s
    }
}

func halfHann(_ n: Int, rising: Bool) -> [Double] {
    var w = [Double](repeating: 0, count: n)
    for i in 0..<n {
        let v = 0.5 - 0.5 * cos(Double.pi * (Double(i) + 0.5) / Double(n))
        w[rising ? i : n - 1 - i] = v
    }
    return w
}

/// Unit-amplitude exponential sine sweep.
public func makeSweep(_ s: SweepSpec) -> [Double] {
    let n = s.nSweep, L = s.L, k = 2 * Double.pi * s.f1 * L, fs = Double(s.fs)
    var x = [Double](repeating: 0, count: n)
    for i in 0..<n { x[i] = sin(k * (exp(Double(i) / fs / L) - 1)) }
    let fi = Int((s.fadeIn * fs).rounded(.down)), fo = Int((s.fadeOut * fs).rounded(.down))
    if fi > 0 { let w = halfHann(fi, rising: true); for j in 0..<fi { x[j] *= w[j] } }
    if fo > 0 { let w = halfHann(fo, rising: false); for j in 0..<fo { x[n - fo + j] *= w[j] } }
    return x
}

/// The full playback signal: lead silence, then n sweeps separated by gaps, then a short tail.
public func makeTestSignal(_ s: SweepSpec) -> [Float] {
    let sw = makeSweep(s), g = pow(10, s.levelDBFS / 20)
    var out = [Float](repeating: 0, count: s.signalLength)
    for k in 0..<s.nSweeps {
        let o = s.nLead + k * s.period
        for i in 0..<s.nSweep { out[o + i] = Float(sw[i] * g) }
    }
    return out
}

/// Time-reversed sweep with +6 dB/oct envelope, scaled for unity in-band gain.
public func inverseFilter(_ sweep: [Double], _ s: SweepSpec) -> [Double] {
    let n = sweep.count, fs = Double(s.fs)
    var inv = [Double](repeating: 0, count: n)
    for i in 0..<n { inv[i] = sweep[n - 1 - i] * exp(-(Double(i) / fs) / s.L) }
    let nfft = nextPow2(2 * n - 1)
    let A = KernelSpectrum(sweep, nfft), B = KernelSpectrum(inv, nfft)
    let lo = max(200, 4 * s.f1), hi = min(8000, s.f2 / 2)
    var vals: [Double] = []
    for i in 0...(nfft / 2) {
        let f = Double(i) * fs / Double(nfft)
        if f >= lo && f <= hi {
            let r = A.re[i] * B.re[i] - A.im[i] * B.im[i], m = A.re[i] * B.im[i] + A.im[i] * B.re[i]
            vals.append((r * r + m * m).squareRoot())
        }
    }
    vals.sort()
    let c = vals.count
    let med = c % 2 == 1 ? vals[(c - 1) / 2] : 0.5 * (vals[c / 2 - 1] + vals[c / 2])
    for i in 0..<n { inv[i] /= med }
    return inv
}
