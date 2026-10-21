import Foundation

// NAM capture prep. Line-for-line port of reference/namprep.py (and nam.js):
// lines a recording of NAM's v3 training signal up to the sample, cuts it to
// the exact length, and checks drift, consistency, level, clipping, noise and hum.

public enum NAMKind: String, CaseIterable { case amp, full }

public struct NAMChannelInfo {
    public var recordedRate: Int
    public var resampled = false
    public var match = 0.0
    public var clickAgreement: Int?
    public var offsetSamples = 0
    public var offsetMs = 0.0
    public var polarityInverted = false
    public var paddedSamples: Int?
    public var driftSamples = 0
    public var startEndCorrelation = 0.0
    public var replicateESR = 0.0
    public var peakDBFS = 0.0
    public var clippedSamples = 0
    public var noiseDBFS = 0.0
    public var noiseBelowPeakDB: Double?
    public var humHz: Int?
    public var humShare = 0.0
    public var delayVsFirstMs = 0.0

    var json: JSON {
        var o: [(String, JSON)] = [("recorded_rate", .int(recordedRate))]
        if resampled { o.append(("resampled_to_48k", .bool(true))) }
        o += [("match", .number(match)), ("click_agreement_samples", clickAgreement.map { JSON.int($0) } ?? .null),
              ("offset_samples", .int(offsetSamples)), ("offset_ms", .number(offsetMs)),
              ("polarity", .string(polarityInverted ? "inverted" : "normal"))]
        if let p = paddedSamples { o.append(("padded_samples", .int(p))) }
        o += [("drift_samples", .int(driftSamples)), ("start_end_correlation", .number(startEndCorrelation)),
              ("replicate_esr", .number(replicateESR)), ("peak_dbfs", .number(peakDBFS)), ("clipped_samples", .int(clippedSamples)),
              ("noise_dbfs", .number(noiseDBFS)), ("noise_below_peak_db", .opt(noiseBelowPeakDB)),
              ("hum_hz", humHz.map { JSON.int($0) } ?? .null), ("hum_share", .number(humShare)),
              ("delay_vs_first_ms", .number(delayVsFirstMs))]
        return .object(o)
    }
}

public struct NAMChannelResult {
    public var output: [Double]
    public var info: NAMChannelInfo
    public var warnings: [String]
}

public struct NAMResult {
    public var kind: NAMKind
    public var names: [String]
    public var outputs: [String: [Double]]
    public var diagnostics: [String: NAMChannelInfo]
    public var warnings: [String]
    public var notes: [String]
}

public enum NAMPrep {
    public static let version = "0.1-mac"
    public static let fs = 48000
    public static let length = NAMLayout.length
    public static let signalName = NAMLayout.name
    static let N = NAMLayout.length, VAL = NAMLayout.validationLength, EB = NAMLayout.envBlock
    static let FIRST = NAMLayout.firstSound, LAST = NAMLayout.lastSound
    static let NOISE = (420000, 498000)
    static let CLICK_WIN = 960, DRIFT_SEG = (24000, 360000), DRIFT_MAX = 48, MIN_ENV_CORR = 0.6

    // ------------------------------------------------------------ resampling
    private static let KB = 8.6, ZC = 32.0, KT = 8192
    private static func besselI0(_ x: Double) -> Double {
        var s = 1.0, t = 1.0
        for k in 1..<60 { t *= (x / (2 * Double(k))) * (x / (2 * Double(k))); s += t; if t < 1e-17 * s { break } }
        return s
    }
    private static let ktab: [Double] = {
        let i0 = besselI0(KB)
        return (0...(KT + 1)).map { i in let v = min(1, Double(i) / Double(KT)); return besselI0(KB * (1 - v * v).squareRoot()) / i0 }
    }()
    static func kernel(_ d: Double, _ c: Double, _ halfW: Double) -> Double {
        let a = c * d
        let sinc = a == 0 ? 1 : Foundation.sin(Double.pi * a) / (Double.pi * a)
        let p = abs(d) / halfW * Double(KT)
        let i = min(KT, max(0, Int(p.rounded(.down))))
        let f = p - Double(i)
        return c * sinc * (ktab[i] * (1 - f) + ktab[i + 1] * f)
    }
    private static func gcd(_ a: Int, _ b: Int) -> Int { var a = a, b = b; while b != 0 { (a, b) = (b, a % b) }; return a }

    /// Polyphase windowed-sinc resampler; same samples as namprep.resample_to.
    public static func resample(_ x: [Double], _ fs: Int, _ rate: Int) -> [Double] {
        if rate == fs { return x }
        let g = gcd(fs, rate), P = rate / g, Q = fs / g
        let ratio = Double(rate) / Double(fs), c = min(1, ratio) * 0.97, halfW = ZC / c
        let n = Int((Double(x.count) * ratio + 0.5).rounded(.down)), L = x.count
        var y = [Double](repeating: 0, count: n)
        x.withUnsafeBufferPointer { xp in
            y.withUnsafeMutableBufferPointer { yp in
                for r in 0..<min(P, n) {
                    let cnt = (n - 1 - r) / P + 1, t = Double(r) / ratio
                    let lo = Int((t - halfW).rounded(.up)), hi = Int((t + halfW).rounded(.down))
                    let w = (lo...hi).map { kernel(t - Double($0), c, halfW) }
                    for u in 0..<cnt {
                        let base = Q * u + lo
                        var acc = 0.0
                        for j in 0..<w.count {
                            let k = base + j
                            acc += w[j] * (k >= 0 && k < L ? xp[k] : 0)
                        }
                        yp[r + P * u] = acc
                    }
                }
            }
        }
        return y
    }

    // ------------------------------------------------------------ helpers
    static func db(_ x: Double) -> Double { x > 0 ? 20 * log10(x) : -200 }
    static func rnd(_ x: Double, _ d: Int) -> Double { let p = pow(10.0, Double(d)); return (x * p + 0.5).rounded(.down) / p }
    static func absMax(_ a: UnsafeBufferPointer<Double>, _ s0: Int, _ s1: Int) -> Double {
        var m = 0.0; if s0 < s1 { for i in s0..<s1 { let v = abs(a[i]); if v > m { m = v } } }; return m
    }
    static func take(_ x: [Double], _ d: Int, _ n: Int) -> [Double] {
        var out = [Double](repeating: 0, count: n)
        let s0 = max(0, d), s1 = min(x.count, d + n)
        if s1 > s0 { for i in s0..<s1 { out[i - d] = x[i] } }
        return out
    }
    static func f(_ v: Double, _ d: Int) -> String { String(format: "%.\(d)f", v) }

    static func envelopeDB(_ x: [Double]) -> [Double] {
        let nb = x.count / EB
        var e = [Double](repeating: 0, count: nb)
        x.withUnsafeBufferPointer { xp in
            for b in 0..<nb {
                var s = 0.0, o = b * EB
                for _ in 0..<EB { s += xp[o] * xp[o]; o += 1 }
                e[b] = 20 * log10(max((s / Double(EB)).squareRoot(), 1e-5))
            }
        }
        return e
    }

    static func coarseOffset(_ x: [Double]) throws -> (Int, Double) {
        let env = envelopeDB(x), T0 = NAMLayout.envDB, L = T0.count
        var mean = 0.0; for v in T0 { mean += v }; mean /= Double(L)
        let T = T0.map { $0 - mean }
        var tn = 0.0; for v in T { tn += v * v }; tn = tn.squareRoot()
        let kmin = -(FIRST / EB), pad = -kmin
        var e = [Double](repeating: -100, count: pad + env.count + L)
        for i in 0..<env.count { e[pad + i] = env[i] }
        let kmax = env.count - L / 2
        var cs = [Double](repeating: 0, count: e.count + 1), cs2 = cs
        for i in 0..<e.count { cs[i + 1] = cs[i] + e[i]; cs2[i + 1] = cs2[i] + e[i] * e[i] }
        var best = -2.0, bk: Int? = nil
        let kend = max(kmin + 1, kmax)
        e.withUnsafeBufferPointer { ep in
            T.withUnsafeBufferPointer { tp in
                var k = kmin
                while k < kend {
                    let s = k + pad
                    if s + L > ep.count { break }
                    let sm = cs[s + L] - cs[s], ss = cs2[s + L] - cs2[s] - sm * sm / Double(L)
                    if ss > 1e-9 {
                        var dot = 0.0
                        for i in 0..<L { dot += ep[s + i] * tp[i] }
                        let r = dot / (ss.squareRoot() * tn)
                        if r > best + 1e-12 { best = r; bk = k }
                    }
                    k += 1
                }
            }
        }
        guard let k = bk else { throw IRCaptureError("the recording is too short to contain the training signal") }
        return (k * EB, best)
    }

    static func clickOnset(_ x: [Double], _ centre: Int, _ noisePeak: Double) -> (Int, Double, Int)? {
        let lo = max(0, centre - CLICK_WIN), hi = min(x.count, centre + CLICK_WIN)
        if hi - lo < 10 { return nil }
        return x.withUnsafeBufferPointer { xp -> (Int, Double, Int)? in
            let p = absMax(xp, lo, hi)
            if p < 4 * noisePeak || p <= 0 { return nil }
            let thr = max(0.1 * p, 2 * noisePeak)
            var first = -1, j = lo
            for i in lo..<hi {
                if first < 0 && abs(xp[i]) >= thr { first = i }
                if abs(xp[i]) > abs(xp[j]) { j = i }
            }
            return (first, p, xp[j] > 0 ? 1 : -1)
        }
    }

    static func humCheck(_ noise: [Double]) -> (Int?, Double) {
        let n = noise.count, nfft = 1 << 17
        var re = [Double](repeating: 0, count: nfft), im = re
        for i in 0..<n { re[i] = noise[i] * (0.5 - 0.5 * cos(2 * Double.pi * (Double(i) + 0.5) / Double(n))) }
        fft(&re, &im, inverse: false)
        let nb = nfft / 2 + 1
        var P = [Double](repeating: 0, count: nb), tot = 0.0
        for i in 0..<nb {
            P[i] = re[i] * re[i] + im[i] * im[i]
            let fr = Double(i) * Double(fs) / Double(nfft)
            if fr >= 20 && fr <= 2000 { tot += P[i] }
        }
        var best: (Int?, Double) = (nil, 0)
        for f0 in [50, 60] {
            var s = 0.0
            for b in 0..<nb {
                let fr = Double(b) * Double(fs) / Double(nfft)
                var hit = false
                for k in 1...8 where abs(fr - Double(k * f0)) <= 3 { hit = true; break }
                if hit { s += P[b] }
            }
            let share = tot > 0 ? s / tot : 0
            if share > best.1 { best = (f0, share) }
        }
        return best
    }

    // ------------------------------------------------------------ one channel
    public static func prepareChannel(_ xIn: [Double], fs inRate: Int, label: String,
                                      progress: (String) -> Void = { _ in }) throws -> NAMChannelResult {
        var warn: [String] = []
        var info = NAMChannelInfo(recordedRate: inRate)
        var x = xIn
        if inRate != fs {
            progress("\(label): converting \(rateTag(inRate).dropLast()) kHz to 48 kHz")
            x = resample(x, inRate, fs); info.resampled = true
        }
        if x.count < (LAST - FIRST) / 2 {
            throw IRCaptureError("\(label): the recording is only \(f(Double(x.count) / Double(fs), 0)) s long; the training signal is \(f(Double(N) / Double(fs), 0)) s. Record the whole file.")
        }
        progress("\(label): finding the training signal")
        let (d0, r) = try coarseOffset(x)
        info.match = rnd(r, 3)
        if r < MIN_ENV_CORR {
            throw IRCaptureError("\(label): couldn't find the training signal in this recording (match \(f(r, 2))). Check that the TONE3000 sweep file is what played, and that this is the right track.")
        }
        let nzw = take(x, d0 + NOISE.0, NOISE.1 - NOISE.0)
        let noisePeak = nzw.withUnsafeBufferPointer { absMax($0, 0, $0.count) }
        let clicks = NAMLayout.blips.map { clickOnset(x, $0 + d0, noisePeak) }
        if clicks[0] == nil && clicks[1] == nil {
            throw IRCaptureError("\(label): found the signal but not its two alignment clicks at 10.5 s and 11.5 s. A noise gate or a very low level can hide them: turn gates off and record again.")
        }
        var ds: [Int] = []
        for (k, c) in clicks.enumerated() { if let c { ds.append(c.0 - NAMLayout.blips[k]) } }
        var d = ds[0]
        if ds.count < 2 {
            warn.append("\(label): only one of the two alignment clicks was found; alignment is less certain")
            info.clickAgreement = nil
        } else {
            info.clickAgreement = abs(ds[1] - ds[0])
            if abs(ds[1] - ds[0]) > 1 {
                warn.append("\(label): the two alignment clicks disagree by \(abs(ds[1] - ds[0])) samples; something in the chain smears clicks (a gate, a long room tail)")
            }
            d = min(ds[0], ds[1])
        }
        let sign = (clicks[0] ?? clicks[1]!).2
        info.offsetSamples = d; info.offsetMs = rnd(Double(d) / Double(fs) * 1000, 3); info.polarityInverted = sign < 0
        if d + LAST >= x.count {
            throw IRCaptureError("\(label): the recording stops \(f(Double(d + LAST - x.count + 1) / Double(fs), 1)) s before the training signal ends. Record (or export) a little past the end.")
        }
        if d + FIRST < 0 {
            throw IRCaptureError("\(label): the recording starts \(f(Double(-(d + FIRST)) / Double(fs), 2)) s after the training signal began. Start recording before playback.")
        }
        if d < 0 || d + N > x.count { info.paddedSamples = max(0, -d) + max(0, d + N - x.count) }
        let y = take(x, d, N)

        progress("\(label): checking the take")
        let SL = DRIFT_SEG.1 - DRIFT_SEG.0
        let ext = take(x, d + N - VAL + DRIFT_SEG.0 - DRIFT_MAX, SL + 2 * DRIFT_MAX)
        var bestK = 0, bestC = -2.0
        y.withUnsafeBufferPointer { yp in
            ext.withUnsafeBufferPointer { ep in
                var na = 0.0
                for i in 0..<SL { let v = yp[DRIFT_SEG.0 + i]; na += v * v }
                na = na.squareRoot()
                for k in -DRIFT_MAX...DRIFT_MAX {
                    let o = k + DRIFT_MAX
                    var dot = 0.0, nb = 0.0
                    for i in 0..<SL { let bv = ep[o + i]; dot += yp[DRIFT_SEG.0 + i] * bv; nb += bv * bv }
                    nb = nb.squareRoot()
                    let c = na > 0 && nb > 0 ? dot / (na * nb) : 0
                    if c > bestC + 1e-12 { bestC = c; bestK = k }
                }
            }
        }
        info.driftSamples = bestK; info.startEndCorrelation = rnd(bestC, 5)
        if bestC < 0.9 {
            warn.append("\(label): the closing 9 s don't match the opening 9 s (correlation \(f(bestC, 2))). The amp changed a lot during the take, or playback and recording ran at different speeds. Use one interface for both, with the project at 48 kHz.")
        } else if abs(bestK) > 1 {
            warn.append("\(label): the end of the take has drifted \(bestK) samples against the start. Playback and recording don't share a clock: use one interface for both (not separate input and output devices).")
        }
        var num = 0.0, den = 0.0
        for i in 0..<VAL { let v1 = y[N - VAL + i], df = y[i] - v1; num += df * df; den += v1 * v1 }
        let esr = den > 0 ? num / den : Double.nan
        info.replicateESR = Double(String(format: "%.3g", esr)) ?? esr
        if esr > 0.005 {
            warn.append("\(label): the amp sounded different at the end than at the start (replicate ESR \(String(format: "%.3g", esr))). Warm the amp up for 20 minutes, keep levels steady, and record again. A model can't be much more accurate than this.")
        }

        var pk = 0.0, clip = 0, flat = 0
        for i in 0..<N {
            let av = abs(y[i])
            if av > pk { pk = av }
            if av >= 0.999 { clip += 1 }
            if i > 0 && av > 0.5 && y[i] == y[i - 1] { flat += 1 }
        }
        info.peakDBFS = rnd(db(pk), 1); info.clippedSamples = clip
        if clip > 0 {
            warn.append("\(label): \(clip) samples at full scale, so the recording clipped. Lower the interface input gain about 6 dB and record again.")
        } else if flat > 20 {
            warn.append("\(label): the waveform has flat tops (\(flat) repeated samples near the peak). Something before the interface may be clipping (a pad, a line out, a preamp).")
        } else if pk > pow(10, -3.0 / 20) {
            warn.append("\(label): peaks at \(f(db(pk), 1)) dBFS, close to clipping. TONE3000 suggests peaks around -8 dBFS: lower the input gain a few dB.")
        } else if pk < pow(10, -24.0 / 20) {
            warn.append("\(label): peaks at only \(f(db(pk), 1)) dBFS. Raise the input gain so peaks land around -8 dBFS.")
        }

        let nz = Array(y[NOISE.0..<NOISE.1])
        var ns = 0.0; for v in nz { ns += v * v }
        let nrms = (ns / Double(nz.count)).squareRoot()
        info.noiseDBFS = rnd(db(nrms), 1)
        info.noiseBelowPeakDB = nrms > 0 ? rnd(db(pk) - db(nrms), 1) : nil
        let hc: (Int?, Double) = nrms > 0 ? humCheck(nz) : (nil, 0)
        info.humHz = (hc.1 > 0.5 && nrms > pow(10, -90.0 / 20)) ? hc.0 : nil
        info.humShare = rnd(hc.1, 2)
        if nrms > 0 && db(pk) - db(nrms) < 40 {
            warn.append("\(label): the noise floor is only \(f(db(pk) - db(nrms), 0)) dB below the peaks. Noise ends up in the model: check cables, gain staging and noisy gear.")
        }
        if let h = info.humHz {
            warn.append("\(label): the noise is mostly \(h) Hz hum. Try the ground lift on the reamp box or load box, and keep audio cables away from power cables.")
        }
        return NAMChannelResult(output: y, info: info, warnings: warn)
    }

    // ------------------------------------------------------------ whole set
    public static func finish(kind: NAMKind, channels: [(name: String, result: NAMChannelResult)]) -> NAMResult {
        let names = channels.map(\.name)
        var diag: [String: NAMChannelInfo] = [:], outs: [String: [Double]] = [:], warns: [String] = []
        for c in channels { diag[c.name] = c.result.info; outs[c.name] = c.result.output; warns += c.result.warnings }
        let first = names.compactMap { diag[$0]?.offsetSamples }.min() ?? 0
        for n in names { diag[n]!.delayVsFirstMs = rnd(Double(diag[n]!.offsetSamples - first) / Double(fs) * 1000, 3) }
        var notes: [String] = []
        if kind == .amp {
            notes.append("Amp-only model: pair it with cab IRs captured with the speaker-terminal reference (reference mode). Sweep-referenced IRs would add the speaker's impedance bump twice.")
        } else {
            notes.append("Full-chain model: each mic is its own model. Close mics work best; NAM only models a short stretch of time, so room sound won't carry over well.")
            if names.count > 1 { notes.append("Each file is lined up on its own. To blend two of these models like the real mics, delay each by its delay_vs_first_ms in the DAW.") }
        }
        return NAMResult(kind: kind, names: names, outputs: outs, diagnostics: diag, warnings: warns, notes: notes)
    }

    public static func prepare(_ channels: [(name: String, x: [Double], fs: Int)], kind: NAMKind,
                               progress: (String) -> Void = { _ in }) throws -> NAMResult {
        var out: [(name: String, result: NAMChannelResult)] = []
        for c in channels { out.append((c.name, try prepareChannel(c.x, fs: c.fs, label: c.name, progress: progress))) }
        return finish(kind: kind, channels: out)
    }

    // ------------------------------------------------------------ output
    /// Mono 24-bit PCM at 48 kHz; scale 2^23 so a 24-bit recording passes through bit for bit.
    public static func wav24(_ x: [Double]) -> Data {
        let n = x.count, dataLen = n * 3, pad = dataLen & 1
        var bytes = [UInt8](repeating: 0, count: 44 + dataLen + pad)
        func str(_ o: Int, _ s: String) { for (j, c) in s.utf8.enumerated() { bytes[o + j] = c } }
        func u32(_ o: Int, _ v: Int) { for k in 0..<4 { bytes[o + k] = UInt8((v >> (8 * k)) & 255) } }
        func u16(_ o: Int, _ v: Int) { bytes[o] = UInt8(v & 255); bytes[o + 1] = UInt8((v >> 8) & 255) }
        str(0, "RIFF"); u32(4, 36 + dataLen + pad); str(8, "WAVE")
        str(12, "fmt "); u32(16, 16); u16(20, 1); u16(22, 1); u32(24, fs); u32(28, fs * 3); u16(32, 3); u16(34, 24)
        str(36, "data"); u32(40, dataLen)
        var o = 44
        for v in x {
            var q = Int((v * 8388608 + 0.5).rounded(.down))
            q = max(-8388608, min(8388607, q))
            bytes[o] = UInt8(q & 255); bytes[o + 1] = UInt8((q >> 8) & 255); bytes[o + 2] = UInt8((q >> 16) & 255); o += 3
        }
        return Data(bytes)
    }

    public static func safe(_ s: String) -> String {
        let r = safeName(s)
        return r == "ir" && s.trimmingCharacters(in: .whitespacesAndNewlines) != "ir" ? "capture" : r
    }
    public static func fileName(_ capture: String, _ name: String) -> String { safe(capture) + "_" + safe(name) + ".wav" }

    public static func uploadNotes(_ r: NAMResult, capture: String) -> String {
        var L = ["NAM capture: \(capture)", "", "How to train it at TONE3000", "",
                 "1. Go to tone3000.com and log in.",
                 "2. Choose Create Tone, then Capture.",
                 "3. Upload the file(s) in this folder (one model per file).",
                 "4. Settings: Model Standard, Best Fit on, 400 max epochs (TONE3000's suggestion).",
                 "5. Name each model with the amp, the knob settings and, for mics, the mic and its position.",
                 "6. Leave it private unless you mean to share it.",
                 "7. When it's done, check the ESR: under 0.01 is great; 0.3 or more means something went wrong.", ""]
        for n in r.notes { L.append("Note: " + n) }
        L.append("")
        for n in r.names {
            let d = r.diagnostics[n]!
            L.append("\(fileName(capture, n)): peak \(f(d.peakDBFS, 1)) dBFS, noise \(f(d.noiseDBFS, 1)) dBFS, replicate ESR \(f(d.replicateESR, 5))")
        }
        if !r.warnings.isEmpty { L += ["", "Warnings:"] + r.warnings.map { "- " + $0 } }
        return L.joined(separator: "\n") + "\n"
    }

    public static func report(_ r: NAMResult, capture: String, extra: [(String, JSON)] = []) -> String {
        let iso = ISO8601DateFormatter()
        var o: [(String, JSON)] = [("capture", .string(capture)), ("kind", .string(r.kind.rawValue)),
                                   ("created", .string(iso.string(from: Date()))), ("namprep_version", .string(version)),
                                   ("signal", .string(signalName)),
                                   ("diagnostics", .object(r.names.map { ($0, r.diagnostics[$0]!.json) })),
                                   ("warnings", .array(r.warnings.map { .string($0) })), ("notes", .array(r.notes.map { .string($0) }))]
        o += extra
        return JSON.object(o).serialized()
    }

    /// Writes `<outDir>/<capture>/<capture>_<name>.wav` per channel, report.json and UPLOAD-STEPS.txt.
    @discardableResult
    public static func write(_ r: NAMResult, capture: String, outDir: URL, extra: [(String, JSON)] = []) throws -> URL {
        let folder = outDir.appendingPathComponent(safe(capture))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for n in r.names { try wav24(r.outputs[n]!).write(to: folder.appendingPathComponent(fileName(capture, n))) }
        try report(r, capture: capture, extra: extra).write(to: folder.appendingPathComponent("report.json"), atomically: true, encoding: .utf8)
        try uploadNotes(r, capture: capture).write(to: folder.appendingPathComponent("UPLOAD-STEPS.txt"), atomically: true, encoding: .utf8)
        return folder
    }
}
