import Foundation

// Consumer output: polarity, export targets, the readable capture folder, and the raw take.
// The DSP is unchanged; these only decide signs, file sets and where files go.

// ------------------------------------------------------------------ polarity
public struct PolarityInfo: Equatable {
    public var mainPeakNegative: Bool
    public var flipped: Bool
}

/// Makes each IR's main peak positive, so mics sum without cancelling (commercial IR packs do this).
/// With `keep` nothing is flipped but the detection is still recorded. Port of normalize_polarity()
/// in ircapture.py and normalizePolarity() in dsp.js. Returns plain-language notes for the results.
@discardableResult
public func normalizePolarity(_ res: inout AnalysisResult, keep: Bool = false) -> [String] {
    var info: [String: PolarityInfo] = [:]
    for m in res.names {
        guard var h = res.irs[m], !h.isEmpty else { continue }
        let k = argAbsMax(h, 0, h.count)
        let neg = h[k] < 0, flip = neg && !keep
        if flip {
            for i in h.indices { h[i] = -h[i] }
            res.irs[m] = h
        }
        info[m] = PolarityInfo(mainPeakNegative: neg, flipped: flip)
    }
    res.polarity = info
    res.polarityMode = keep ? "keep" : "positive"
    var notes: [String] = []
    let flipped = res.names.filter { info[$0]?.flipped == true }
    let kept = res.names.filter { info[$0]?.flipped != true }
    for m in flipped {
        notes.append(kept.isEmpty ? "\(m) came out inverted (main peak negative) and has been flipped."
                                  : "\(m) was inverted relative to \(kept[0]) and has been flipped.")
    }
    if keep {
        for m in res.names where info[m]?.mainPeakNegative == true {
            notes.append("\(m) is inverted (main peak negative). It was kept as recorded.")
        }
    }
    return notes
}

// ------------------------------------------------------------------ export targets
public enum TargetKind: Hashable {
    /// One file per mic at one rate and length, 24-bit, "Keep mic timing" trim.
    case single(rate: Int, length: IRLength, suffix: String)
    /// Every standard rate at every standard length.
    case everything
    /// Minimum-phase versions of the close mics (and close-only mixes) for every single-file target chosen.
    case minimumPhase
    /// Automatic two-mic mixes for every single-file target chosen.
    case mixes
}

/// A set of files made for one destination. Hardware specs are only listed here once they've been
/// checked against the manufacturer's own documentation (`source`). Anything else uses Universal.
public struct ExportTarget: Identifiable, Hashable {
    public let id: String
    public let title: String
    public let detail: String
    /// Folder inside the capture folder; "" is the top level.
    public let folder: String
    public let kind: TargetKind
    public let source: String?

    public static let universal = ExportTarget(
        id: "universal", title: "Universal",
        detail: "48 kHz, 24-bit, 500 ms. One file per mic, at the top of the capture folder. For IR loaders, DAW plug-ins, modelers and Mirror IR. Matches the Boss IR-200 48 kHz / 500 ms format. Devices that use shorter IRs (for example Line 6 Helix, 2048 samples) shorten the file on import.",
        folder: "", kind: .single(rate: 48000, length: .full, suffix: ""),
        source: "https://support.roland.com/hc/en-us/articles/4407995586459-IR-200-IR-data-types-formats-that-can-be-used")
    public static let everything = ExportTarget(
        id: "everything", title: "All sample rates",
        detail: "44.1, 48, 88.2 and 96 kHz, each at 500 ms and 200 ms, 24-bit. Folder: More formats › All sample rates.",
        folder: "More formats/All sample rates", kind: .everything, source: nil)
    public static let iridium = ExportTarget(
        id: "iridium", title: "Strymon Iridium",
        detail: "96 kHz, 24-bit, 500 ms, mono. Format required by Strymon Impulse Manager.",
        folder: "More formats/Strymon Iridium", kind: .single(rate: 96000, length: .full, suffix: "_Iridium"),
        source: "https://www.strymon.net/faq/using-strymon-impulse-manager-with-iridium/")

    public static let minimumPhase = ExportTarget(
        id: "minphase", title: "Minimum-phase versions",
        detail: "The same tone with the timing removed (the sound starts on the first sample), for each close mic, in More formats › Minimum phase. Room mics don't get one.",
        folder: "More formats/Minimum phase", kind: .minimumPhase, source: nil)
    public static let mixes = ExportTarget(
        id: "mixes", title: "Mixes of two mics",
        detail: "Ready-made blends with the mics' timing kept, all at the same loudness: two close mics 50/50, 70/30 and 30/70; a close mic with a room mic 80/20 and 60/40. In More formats › Mixes.",
        folder: "More formats/Mixes", kind: .mixes, source: nil)

    /// Where the files go (destinations), and what else is made for them (extras).
    public static var destinations: [ExportTarget] { [.universal, .everything, .iridium] }
    public static var extras: [ExportTarget] { [.minimumPhase, .mixes] }
    public static var all: [ExportTarget] { destinations + extras }
    public var isExtra: Bool { kind == .minimumPhase || kind == .mixes }
    public static func named(_ id: String) -> ExportTarget? { all.first { $0.id == id } }
}

public let standardRates = [44100, 48000, 88200, 96000]
/// Lengths in "All sample rates", in ms. Most packs ship 500 ms and 200 ms; devices shorten longer files themselves.
public let everythingLengthsMs = [500.0, 200.0]
/// "full" length for the named targets; Custom uses its own.
public let targetFullMs = 500.0

/// Writes the chosen targets (and the Custom matrix, if given) into `<capture>/...`, with one gain per
/// trim mode shared by every file. The gain is also computed over every standard rate at 500 ms, so the
/// files' levels don't change with which targets were chosen. Fills result.gains.
public func exportTargets(_ res: inout AnalysisResult, capture: String, targets: [ExportTarget], custom: ExportOptions? = nil,
                          progress: Progress = { _ in }) -> [ExportFile] {
    struct Key: Hashable { let mic: String; let rate: Int; let n: Int; let trim: TrimMode }
    struct Job { let key: Key; let bits: BitDepth; let path: String }
    let base = ExportOptions()
    let fs = res.fs, names = res.names, onsets = res.onsets
    func count(_ len: IRLength, _ rate: Int, _ fullMs: Double) -> Int {
        switch len { case .full: return iround(fullMs / 1000 * Double(rate)); case .samples(let k): return k }
    }
    let root = capture + "/"
    var jobs: [Job] = []
    for t in targets {
        let folder = t.folder.isEmpty ? root : root + t.folder + "/"
        switch t.kind {
        case .single(let rate, let len, let suffix):
            for m in names {
                jobs.append(Job(key: Key(mic: m, rate: rate, n: count(len, rate, targetFullMs), trim: .set), bits: .b24,
                                path: folder + "\(capture)_\(safeName(m))\(suffix).wav"))
            }
        case .minimumPhase, .mixes:
            continue
        case .everything:
            for rate in standardRates {
                let tag = rateTag(rate)
                for ms in everythingLengthsMs {
                    for m in names {
                        jobs.append(Job(key: Key(mic: m, rate: rate, n: count(.full, rate, ms), trim: .set), bits: .b24,
                                        path: folder + "\(tag)/\(capture)_\(safeName(m))_\(tag)_\(Int(ms))ms.wav"))
                    }
                }
            }
        }
    }
    if let c = custom {
        for trim in c.trim {
            for rate in c.rates {
                let tag = rateTag(rate)
                for len in c.lengths {
                    for m in names {
                        for b in c.bits {
                            jobs.append(Job(key: Key(mic: m, rate: rate, n: count(len, rate, c.fullMs), trim: trim), bits: b,
                                            path: root + "More formats/Custom/\(trim.rawValue)/\(tag)/\(capture)_\(safeName(m))_\(tag)_\(b.rawValue)_\(len).wav"))
                        }
                    }
                }
            }
        }
    }

    // Every variant needed: the jobs plus the fixed "level" set for each trim mode in use.
    var modes: [TrimMode] = []
    for j in jobs where !modes.contains(j.key.trim) { modes.append(j.key.trim) }
    var keys: [Key] = []
    var seen = Set<Key>()
    func need(_ k: Key) { if !seen.contains(k) { seen.insert(k); keys.append(k) } }
    for mode in modes {
        for rate in standardRates { for m in names { need(Key(mic: m, rate: rate, n: count(.full, rate, targetFullMs), trim: mode)) } }
    }
    for j in jobs { need(j.key) }

    var resampled: [String: [Double]] = [:]
    var rates: [Int] = []
    for k in keys where !rates.contains(k.rate) { rates.append(k.rate) }
    for rate in rates {
        progress("Resampling to \(rateTag(rate))")
        for m in names {
            let g = Double(fs) / Double(rate)        // keep convolution gain equal across rates
            resampled["\(m)@\(rate)"] = resampleTo(res.irs[m]!, fs, rate).map { $0 * g }
        }
    }
    let preFs = base.prerollMs / 1000 * Double(fs)
    let firstOn = names.map { onsets[$0]! }.min()!
    var cuts: [Key: [Double]] = [:]
    for k in keys {
        let start = k.trim == .set ? iround((Double(firstOn) - preFs) * Double(k.rate) / Double(fs))
                                   : iround((Double(onsets[k.mic]!) - preFs) * Double(k.rate) / Double(fs))
        let nIn = iround(base.prerollMs / 1000 * Double(k.rate))
        cuts[k] = cut(resampled["\(k.mic)@\(k.rate)"]!, start, k.n, nIn, base.fadeFrac)
    }
    let target = pow(10, base.peakDBFS / 20)
    var gains: [TrimMode: [String: Double]] = [:]
    for mode in modes {
        let mk = keys.filter { $0.trim == mode }
        var g: [String: Double] = [:]
        if mode == .set {
            let v = target / mk.map { absMax(cuts[$0]!) }.max()!
            for m in names { g[m] = v }
        } else {
            for m in names { g[m] = target / mk.filter { $0.mic == m }.map { absMax(cuts[$0]!) }.max()! }
        }
        gains[mode] = g
        res.gains[mode.rawValue] = g
    }
    progress("Writing files")
    var files: [ExportFile] = []
    var written = Set<String>()
    for j in jobs where !written.contains(j.path) {
        written.insert(j.path)
        let gg = gains[j.key.trim]![j.key.mic]!
        files.append(ExportFile(path: j.path, data: writeWav(cuts[j.key]!.map { $0 * gg }, rate: j.key.rate, bits: j.bits)))
    }
    let wantMP = targets.contains { $0.kind == .minimumPhase }, wantMix = targets.contains { $0.kind == .mixes }
    var lengthsMs: [(String, Double)] = []
    for j in jobs {
        let ms = Double(j.key.n) / Double(j.key.rate) * 1000
        lengthsMs.append((abs(ms - targetFullMs) < 0.01 ? "500 ms" : "\(j.key.n)-sample", ms))
    }
    if wantMP || wantMix {
        progress("Making minimum-phase versions and mixes")
        var singles: [(rate: Int, n: Int, suffix: String)] = []
        for t in targets { if case .single(let rate, let len, let suffix) = t.kind { singles.append((rate, count(len, rate, targetFullMs), suffix)) } }
        files += exportExtras(&res, capture: capture, singles: singles, minimumPhase: wantMP, mixes: wantMix,
                              resampled: resampled, lengthsMs: lengthsMs)
    }
    return files
}

// ------------------------------------------------------------------ extras (P1.3a)
// Port of is_room_mic(), minimum_phase(), make_mixes() and export_extras() in ircapture.py.

/// Room mics: a word in the name starts with "room" or "amb" (Room, Room L, Amb, Ambient).
public func isRoomMic(_ name: String) -> Bool {
    var words: [String] = [], cur = ""
    for ch in name.lowercased().unicodeScalars {
        if (ch >= "a" && ch <= "z") || (ch >= "0" && ch <= "9") { cur.unicodeScalars.append(ch) }
        else if !cur.isEmpty { words.append(cur); cur = "" }
    }
    if !cur.isEmpty { words.append(cur) }
    return words.contains { $0.hasPrefix("room") || $0.hasPrefix("amb") }
}

let ROOM_SHORT_MS = 100.0
let CLOSE_CLOSE_RATIOS = [(50, 50), (70, 30), (30, 70)]
let CLOSE_ROOM_RATIOS = [(80, 20), (60, 40)]

/// Same magnitude response, phase rebuilt by the cepstral (homomorphic) method. Same length as x; the
/// main peak keeps x's main-peak sign; the end gets the export fade-out again.
public func minimumPhase(_ x: [Double], fadeFrac: Double = 0.10) -> [Double] {
    let n = x.count
    var N = 1
    while N < max(8 * n, 16384) { N *= 2 }
    var re = [Double](repeating: 0, count: N), im = re
    for i in 0..<n { re[i] = x[i] }
    fft(&re, &im, inverse: false)
    var mx = 0.0
    for i in 0..<N { re[i] = (re[i] * re[i] + im[i] * im[i]).squareRoot(); mx = max(mx, re[i]) }
    let floor = mx * 1e-8
    for i in 0..<N { re[i] = log(max(re[i], floor)); im[i] = 0 }
    fft(&re, &im, inverse: true)                       // real cepstrum (real part)
    for i in 0..<N { im[i] = 0 }
    for i in 1..<(N / 2) { re[i] *= 2 }
    for i in (N / 2 + 1)..<N { re[i] = 0 }
    fft(&re, &im, inverse: false)
    for i in 0..<N { let m = exp(re[i]); re[i] = m * cos(im[i]); im[i] = m * sin(im[i]) }
    fft(&re, &im, inverse: true)
    var y = Array(re[0..<n])
    if (y[argAbsMax(y, 0, n)] < 0) != (x[argAbsMax(x, 0, n)] < 0) { for i in 0..<n { y[i] = -y[i] } }
    let nf = max(Int((fadeFrac * Double(n)).rounded(.down)), 2)
    let w = halfHann(nf, rising: false)
    for i in 0..<nf { y[n - nf + i] *= w[i] }
    return y
}

public struct MicMix {
    public let label: String       // "SM57+R121 70/30"
    public let file: String        // "SM57+R121_70-30"
    public let mics: [String]
    public let weights: [Int]
    public let room: Bool
    public let ir: [Double]
}

/// Two-mic blends at the capture rate, from the polarity-normalized IRs with their timing kept. Each mic is
/// scaled to the same energy over the exported window, then weighted; every mix is scaled to the energy of
/// the loudest single mic, so all mixes play at the same loudness.
public func makeMixes(_ res: AnalysisResult, prerollMs: Double = 0.25, fullMs: Double = targetFullMs) -> [MicMix] {
    let names = res.names, fs = Double(res.fs)
    guard names.count >= 2 else { return [] }
    let s0 = iround(Double(names.map { res.onsets[$0]! }.min()!) - prerollMs / 1000 * fs)
    let n = iround(fullMs / 1000 * fs)
    let a = max(s0, 0), b = max(s0 + n, 0)
    func energy(_ h: [Double]) -> Double {
        var e = 0.0
        let e1 = min(b, h.count)
        if a < e1 { for i in a..<e1 { e += h[i] * h[i] } }
        return e
    }
    var en: [String: Double] = [:]
    for m in names { en[m] = energy(res.irs[m]!) }
    let eRef = en.values.max()!
    var out: [MicMix] = []
    for i in 0..<names.count {
        for j in (i + 1)..<names.count {
            var A = names[i], B = names[j]
            let ra = isRoomMic(A), rb = isRoomMic(B)
            if ra && rb { continue }
            if ra { swap(&A, &B) }
            let hA = res.irs[A]!, hB = res.irs[B]!, sA = 1 / en[A]!.squareRoot(), sB = 1 / en[B]!.squareRoot()
            for (wa, wb) in (ra || rb) ? CLOSE_ROOM_RATIOS : CLOSE_CLOSE_RATIOS {
                var h = [Double](repeating: 0, count: max(hA.count, hB.count))
                for k in 0..<hA.count { h[k] += Double(wa) / 100 * hA[k] * sA }
                for k in 0..<hB.count { h[k] += Double(wb) / 100 * hB[k] * sB }
                let g = (eRef / energy(h)).squareRoot()
                for k in h.indices { h[k] *= g }
                out.append(MicMix(label: "\(A)+\(B) \(wa)/\(wb)", file: "\(safeName(A))+\(safeName(B))_\(wa)-\(wb)",
                                  mics: [A, B], weights: [wa, wb], room: ra || rb, ir: h))
            }
        }
    }
    return out
}

/// Notes for room mics; lengthsMs is (label, ms) for every file length being written.
public func extrasNotes(names: [String], lengthsMs: [(String, Double)]) -> [String] {
    var notes: [String] = []
    for m in names where isRoomMic(m) {
        notes.append("\(m) is treated as a room mic: no minimum-phase version (it would smear the room).")
        let short = Array(Set(lengthsMs.filter { $0.1 < ROOM_SHORT_MS }.map { $0.0 })).sorted()
        if !short.isEmpty {
            notes.append("\(m): the \(short.joined(separator: ", ")) files are shorter than \(Int(ROOM_SHORT_MS)) ms and cut off most of the room. Use the 500 ms files.")
        }
    }
    return notes
}

/// Minimum-phase singles and mixes for each single-file target, into More formats/Minimum phase and
/// More formats/Mixes. Gains follow export_extras() in ircapture.py: each family has one gain, computed over
/// every standard rate at 500 ms (so it doesn't depend on what's chosen) and never louder than the singles.
func exportExtras(_ res: inout AnalysisResult, capture: String, singles: [(rate: Int, n: Int, suffix: String)],
                  minimumPhase mpOn: Bool, mixes mixOn: Bool, resampled: [String: [Double]], lengthsMs: [(String, Double)]) -> [ExportFile] {
    let base = ExportOptions(), fs = res.fs, names = res.names
    let mixes = mixOn ? makeMixes(res, prerollMs: base.prerollMs) : []
    var chans: [String: [Double]] = [:]
    for m in names { chans[m] = res.irs[m]! }
    for x in mixes { chans[x.file] = x.ir }
    let close = names.filter { !isRoomMic($0) }
    let mpMix = mixes.filter { !$0.room }.map(\.file)
    let preFs = base.prerollMs / 1000 * Double(fs)
    let firstOn = Double(names.map { res.onsets[$0]! }.min()!)
    var cache: [String: [Double]] = resampled
    func variant(_ ch: String, _ rate: Int, _ n: Int) -> [Double] {
        let key = "\(ch)@\(rate)"
        if cache[key] == nil { let g = Double(fs) / Double(rate); cache[key] = resampleTo(chans[ch]!, fs, rate).map { $0 * g } }
        let start = iround((firstOn - preFs) * Double(rate) / Double(fs))
        return cut(cache[key]!, start, n, iround(base.prerollMs / 1000 * Double(rate)), base.fadeFrac)
    }
    var lvl: [String: [Double]] = [:]
    for rate in standardRates {
        let n = iround(targetFullMs / 1000 * Double(rate))
        for ch in chans.keys { lvl["\(ch)@\(rate)"] = variant(ch, rate, n) }
    }
    func peak(_ chs: [String], mp: Bool = false) -> Double {
        var p = 0.0
        for c in chs { for r in standardRates { let v = lvl["\(c)@\(r)"]!; p = max(p, absMax(mp ? minimumPhase(v, fadeFrac: base.fadeFrac) : v)) } }
        return p
    }
    let target = pow(10, base.peakDBFS / 20)
    let gSingle = target / peak(names)
    var gains: [(String, Double)] = []
    var gMP = gSingle, gMix = gSingle, gMixMP = gSingle
    if mpOn && !close.isEmpty { gMP = min(gSingle, target / peak(close, mp: true)); gains.append(("mp", gMP)) }
    if !mixes.isEmpty {
        gMix = min(gSingle, target / peak(mixes.map(\.file))); gains.append(("mix", gMix))
        if mpOn && !mpMix.isEmpty { gMixMP = min(gMix, target / peak(mpMix, mp: true)); gains.append(("mix_mp", gMixMP)) }
    }
    var notes = extrasNotes(names: names, lengthsMs: lengthsMs)
    if singles.isEmpty { notes.append("Minimum-phase versions and mixes are made for the single-file sets (Universal, Strymon Iridium). None of those was chosen, so none were made.") }
    if mixOn && names.count < 2 { notes.append("Mixes need two mics; this capture has one.") }
    res.extras = JSON.object([
        ("minimum_phase", .bool(mpOn)), ("room_mics", .array(names.filter(isRoomMic).map { .string($0) })),
        ("mixes", .array(mixes.map { x in JSON.object([("name", .string(x.label)), ("mics", .array(x.mics.map { .string($0) })),
                                                       ("weights", .array(x.weights.map { .int($0) }))]) })),
        ("gains_db", .object(gains.map { ($0.0, JSON.number(20 * log10($0.1))) })),
        ("notes", .array(notes.map { .string($0) })),
    ])
    res.exportNotes = notes
    var files: [ExportFile] = []
    var written = Set<String>()
    func add(_ path: String, _ v: [Double], _ g: Double, _ rate: Int) {
        guard !written.contains(path) else { return }
        written.insert(path)
        files.append(ExportFile(path: path, data: writeWav(v.map { $0 * g }, rate: rate, bits: .b24)))
    }
    let mpDir = capture + "/" + ExportTarget.minimumPhase.folder + "/", mixDir = capture + "/" + ExportTarget.mixes.folder + "/"
    for s in singles {
        if mpOn {
            for m in close { add(mpDir + "\(capture)_\(safeName(m))\(s.suffix)_MP.wav", minimumPhase(variant(m, s.rate, s.n), fadeFrac: base.fadeFrac), gMP, s.rate) }
        }
        for x in mixes {
            let v = variant(x.file, s.rate, s.n)
            add(mixDir + "\(capture)_\(x.file)\(s.suffix).wav", v, gMix, s.rate)
            if mpOn && !x.room { add(mixDir + "\(capture)_\(x.file)\(s.suffix)_MP.wav", minimumPhase(v, fadeFrac: base.fadeFrac), gMixMP, s.rate) }
        }
    }
    return files
}

/// README.txt for a capture folder made with targets.
public func captureReadme(capture: String, names: [String], targets: [ExportTarget], custom: Bool,
                          referenced: Bool, polarityNotes: [String], warnings: [String], notes: [String] = []) -> String {
    var t = """
    \(capture) — cab impulse responses made with IR Capture

    START HERE
    """
    if targets.contains(where: { $0.id == "universal" }) {
        t += "\n  These files load in any IR loader, DAW plug-in or modeler (48 kHz, 24-bit, 500 ms):\n"
        for m in names { t += "    \(capture)_\(safeName(m)).wav   (\(m))\n" }
    } else {
        t += "\n  The files are in the More formats folder.\n"
    }
    t += "\n  The mics were trimmed together (\"Keep mic timing\"), so blending two of these files sums the way the real mics did.\n"
    t += referenced
        ? "  A reference tap was used: each IR is speaker, mic and room only, whatever amp drives it.\n"
        : "  No reference tap was used: each IR also includes the power amp's own response, like most commercial IRs.\n"
    for n in polarityNotes { t += "  Polarity: \(n)\n" }
    let others = targets.filter { $0.id != "universal" }
    if !others.isEmpty || custom {
        t += "\nMORE FORMATS\n"
        for o in others { t += "  \(o.folder.replacingOccurrences(of: "More formats/", with: "")): \(o.detail)\n" }
        if custom { t += "  Custom: the rates, lengths, bit depths and trimming chosen under Advanced, in Custom/<trim>/<rate>.\n" }
        t += "  Every file has the same level for the same mic, whatever its rate or length.\n"
        if others.contains(where: \.isExtra) {
            t += "  Minimum-phase files and mixes play at the same loudness as the singles, unless that would clip; then each set is turned down as a whole.\n"
        }
    }
    for n in notes { t += "  Note: \(n)\n" }
    t += """

    OTHER FILES
      report.json  the measurements (levels, noise floor, distortion, arrival times) and any warnings.
      Raw take     the untouched recording and the sweep settings. IR Capture can re-export new formats from it
                   without recording again (Re-export in the results).

    """
    if !warnings.isEmpty {
        t += "THINGS TO CHECK\n"
        for w in warnings { t += "  - \(w)\n" }
    }
    return t
}

// ------------------------------------------------------------------ raw take
/// The untouched recording plus what's needed to process it again: written before processing, so a take
/// is never lost, and read back by Re-export.
public struct RawTake {
    public static let folderName = "Raw take"
    public var capture: String
    public var names: [String]
    public var refIndex: Int?
    public var spec: SweepSpec
    public var recordedWith: String
    public var notes: String

    public init(capture: String, names: [String], refIndex: Int?, spec: SweepSpec, recordedWith: String, notes: String = "") {
        self.capture = capture; self.names = names; self.refIndex = refIndex; self.spec = spec
        self.recordedWith = recordedWith; self.notes = notes
    }

    public static func folder(_ captureFolder: URL) -> URL { captureFolder.appendingPathComponent(folderName) }

    /// rec: one array per channel, mics and reference in the order `names`/`refIndex` describe.
    public func save(_ rec: [[Float]], captureFolder: URL) throws {
        let dir = RawTake.folder(captureFolder)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try writeWavFloat(rec, rate: spec.fs).write(to: dir.appendingPathComponent("\(capture)_recording.wav"))
        try spec.json.serialized().write(to: dir.appendingPathComponent("\(capture)_signal.json"), atomically: true, encoding: .utf8)
        let j = JSON.object([
            ("capture", .string(capture)),
            ("names", .array(names.map { .string($0) })),
            ("ref_index", refIndex.map { JSON.int($0) } ?? .null),
            ("channels", .int(rec.count)),
            ("recorded_with", .string(recordedWith)),
            ("notes", .string(notes)),
            ("ircapture_version", .string(IRCaptureVersion)),
        ])
        try j.serialized().write(to: dir.appendingPathComponent("take.json"), atomically: true, encoding: .utf8)
    }

    /// Reads a raw take back. Throws a plain message for captures made before re-export existed.
    public static func load(captureFolder: URL) throws -> (take: RawTake, rec: [[Double]]) {
        let dir = folder(captureFolder)
        let takeURL = dir.appendingPathComponent("take.json")
        guard FileManager.default.fileExists(atPath: takeURL.path) else {
            throw IRCaptureError("This folder has no raw take that IR Capture can re-export (captures made before version 1.0 don't). Record it again, or choose a capture folder made by this version.")
        }
        guard let d = try JSONSerialization.jsonObject(with: Data(contentsOf: takeURL)) as? [String: Any],
              let capture = d["capture"] as? String, let names = d["names"] as? [String] else {
            throw IRCaptureError("The raw take's take.json can't be read. Record the capture again.")
        }
        let spec = try SweepSpec.load(jsonData: Data(contentsOf: dir.appendingPathComponent("\(capture)_signal.json")))
        let info = try WavInfo(Data(contentsOf: dir.appendingPathComponent("\(capture)_recording.wav"), options: .mappedIfSafe))
        var rec: [[Double]] = []
        for c in 0..<info.channels { rec.append(try info.channel(c)) }
        let ref = (d["ref_index"] as? NSNumber)?.intValue
        guard rec.count == names.count + (ref == nil ? 0 : 1) else {
            throw IRCaptureError("The raw take has \(rec.count) channels but take.json lists \(names.count) mics\(ref == nil ? "" : " and a reference"). Record the capture again.")
        }
        let take = RawTake(capture: capture, names: names, refIndex: ref, spec: spec,
                           recordedWith: d["recorded_with"] as? String ?? "", notes: d["notes"] as? String ?? "")
        return (take, rec)
    }
}
