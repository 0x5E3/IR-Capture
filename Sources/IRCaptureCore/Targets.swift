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
        detail: "48 kHz, 24-bit, 500 ms, one file per mic at the top of the folder. Loads in any IR loader, DAW plug-in or modeler (it is also exactly the Boss IR-200's 48 kHz / 500 ms format).",
        folder: "", kind: .single(rate: 48000, length: .full, suffix: ""),
        source: "https://support.roland.com/hc/en-us/articles/4407995586459-IR-200-IR-data-types-formats-that-can-be-used")
    public static let everything = ExportTarget(
        id: "everything", title: "Everything",
        detail: "44.1, 48, 88.2 and 96 kHz, each at 500 ms, 1024, 2048 and 4096 samples (24-bit), in More formats › Everything.",
        folder: "More formats/Everything", kind: .everything, source: nil)
    public static let helix = ExportTarget(
        id: "helix", title: "Line 6 Helix / HX",
        detail: "48 kHz, 2048 samples, mono. Helix Edit converts every IR to this when it imports, so this file goes in unchanged.",
        folder: "More formats/Line 6 Helix", kind: .single(rate: 48000, length: .samples(2048), suffix: "_Helix"),
        source: "https://kb.line6.com/impulse-response-irs")
    public static let iridium = ExportTarget(
        id: "iridium", title: "Strymon Iridium",
        detail: "96 kHz, 24-bit, 500 ms, mono, for Strymon Impulse Manager.",
        folder: "More formats/Strymon Iridium", kind: .single(rate: 96000, length: .full, suffix: "_Iridium"),
        source: "https://www.strymon.net/faq/using-strymon-impulse-manager-with-iridium/")

    /// IRLoader3 runs 4096 taps; set its sample rate here once it's confirmed, and the target appears.
    public static let irloader3Rate: Int? = nil
    public static var irloader3: ExportTarget? {
        irloader3Rate.map { r in
            ExportTarget(id: "irloader3", title: "Swell IRLoader3",
                         detail: "4096 taps at \(rateTag(r).dropLast()) kHz, 24-bit.",
                         folder: "More formats/IRLoader3", kind: .single(rate: r, length: .samples(4096), suffix: "_IRLoader3"), source: nil)
        }
    }

    public static var all: [ExportTarget] { [.universal, .everything, .helix, .iridium] + (irloader3.map { [$0] } ?? []) }
    public static func named(_ id: String) -> ExportTarget? { all.first { $0.id == id } }
}

public let standardRates = [44100, 48000, 88200, 96000]
public let standardLengths: [IRLength] = [.full, .samples(1024), .samples(2048), .samples(4096)]
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
        case .everything:
            for rate in standardRates {
                let tag = rateTag(rate)
                for len in standardLengths {
                    for m in names {
                        jobs.append(Job(key: Key(mic: m, rate: rate, n: count(len, rate, targetFullMs), trim: .set), bits: .b24,
                                        path: folder + "\(tag)/\(capture)_\(safeName(m))_\(tag)_24_\(len).wav"))
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
    return files
}

/// README.txt for a capture folder made with targets.
public func captureReadme(capture: String, names: [String], targets: [ExportTarget], custom: Bool,
                          referenced: Bool, polarityNotes: [String], warnings: [String]) -> String {
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
    }
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
