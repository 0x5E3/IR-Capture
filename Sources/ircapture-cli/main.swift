import Foundation
import IRCaptureCore

// Command-line front end for the Swift DSP. Mirrors `ircapture.py make-signal` and
// `ircapture.py process`, so CI can check the Swift port against the Python reference.
//
//   ircapture-cli make-signal --out sweeps.wav [--fs 96000] [--level -12]
//   ircapture-cli process --signal sweeps.json --rec a.wav b.wav ref.wav --ref 3
//                         --names Close,Room --name logic --outdir out
//                         [--rates 44100,48000,88200,96000] [--lengths full,1024,2048,4096]
//                         [--bits 24,32f] [--trim set,individual] [--full-ms 500]
//                         [--targets universal,everything,iridium[,custom]] [--keep-polarity] [--raw-take]
//   ircapture-cli reexport --folder <capture folder> --targets iridium,... [--keep-polarity]
//   ircapture-cli nam-prep --rec Suhr.wav SM57.wav --names Suhr,SM57 --kind amp|full --name cap --outdir out

func fail(_ m: String) -> Never { FileHandle.standardError.write((m + "\n").data(using: .utf8)!); exit(2) }

var args = Array(CommandLine.arguments.dropFirst())
guard let cmd = args.first else { fail("usage: ircapture-cli make-signal|process|nam-prep ...") }
args.removeFirst()
var opts: [String: [String]] = [:]
var key: String? = nil
for a in args {
    if a.hasPrefix("--") { key = String(a.dropFirst(2)); opts[key!] = [] } else if let k = key { opts[k]!.append(a) }
}
/// --targets a,b,c → the target layout; "custom" adds the --rates/--lengths/--bits/--trim matrix.
func layoutFrom(_ ids: [String]?, custom: ExportOptions) throws -> OutputLayout {
    guard let ids else { return .matrix }
    var t: [ExportTarget] = []
    for id in ids where id != "custom" {
        guard let x = ExportTarget.named(id) else { throw IRCaptureError("unknown target \(id)") }
        t.append(x)
    }
    return .targets(t, custom: ids.contains("custom") ? custom : nil)
}
func one(_ k: String) -> String? { opts[k]?.first }
func list(_ k: String) -> [String]? { one(k).map { $0.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) } } }

do {
    switch cmd {
    case "make-signal":
        let out = URL(fileURLWithPath: one("out") ?? "sweeps.wav")
        let spec = try SweepSpec(fs: Int(one("fs") ?? "96000")!, levelDBFS: Double(one("level") ?? "-12")!)
        let x = makeTestSignal(spec)
        try writeWavFloat([x], rate: spec.fs).write(to: out)
        try spec.json.serialized().write(to: out.deletingPathExtension().appendingPathExtension("json"), atomically: true, encoding: .utf8)
        print("wrote \(out.path) (\(String(format: "%.1f", Double(x.count) / Double(spec.fs))) s)")

    case "process":
        guard let sig = one("signal"), let recs = opts["rec"], !recs.isEmpty, let name = one("name") else {
            fail("process needs --signal, --rec and --name")
        }
        let spec = try SweepSpec.load(jsonData: Data(contentsOf: URL(fileURLWithPath: sig)))
        var rec: [[Double]] = []
        for p in recs {
            let info = try WavInfo(Data(contentsOf: URL(fileURLWithPath: p)))
            if info.fs != spec.fs { fail("\(p) is \(info.fs) Hz but the test signal was made at \(spec.fs) Hz") }
            for c in 0..<info.channels { rec.append(try info.channel(c)) }
        }
        let n = rec.map(\.count).min()!
        rec = rec.map { Array($0.prefix(n)) }
        let ref = one("ref").flatMap { Int($0) }.map { $0 - 1 }
        let nMics = rec.count - (ref == nil ? 0 : 1)
        let names = list("names") ?? (1...nMics).map { "mic\($0)" }
        var eo = ExportOptions()
        if let r = list("rates") { eo.rates = r.compactMap { Int($0) } }
        if let l = list("lengths") { eo.lengths = l.compactMap { IRLength($0) } }
        if let b = list("bits") { eo.bits = b.compactMap { BitDepth(rawValue: $0) } }
        if let t = list("trim") { eo.trim = t.compactMap { TrimMode(rawValue: $0) } }
        if let f = one("full-ms").flatMap(Double.init) { eo.fullMs = f }
        let t0 = Date()
        let outDir = URL(fileURLWithPath: one("outdir") ?? "ir_out")
        let layout = try layoutFrom(list("targets"), custom: eo)
        if opts["raw-take"] != nil {
            try RawTake(capture: name, names: names, refIndex: ref, spec: spec, recordedWith: "cli")
                .save(rec.map { $0.map(Float.init) }, captureFolder: outDir.appendingPathComponent(name))
        }
        let out = try processAndWrite(rec: rec, spec: spec, names: names, refIndex: ref, capture: name,
                                      outDir: outDir, export: eo, layout: layout, keepPolarity: opts["keep-polarity"] != nil,
                                      process: one("ir-max").map { ProcessOptions(irMax: Double($0)!) },
                                      progress: { if opts["verbose"] != nil { print("  . " + $0) } })
        print(summaryText(out.result))
        for n in out.polarityNotes { print("  * " + n) }
        print("wrote \(out.fileCount) IR files and \(out.folder.appendingPathComponent("report.json").path) in \(String(format: "%.1f", Date().timeIntervalSince(t0))) s")

    case "reexport":
        guard let f = one("folder") else { fail("reexport needs --folder") }
        let folder = URL(fileURLWithPath: f)
        let (take, rec) = try RawTake.load(captureFolder: folder)
        let out = try processAndWrite(rec: rec, spec: take.spec, names: take.names, refIndex: take.refIndex, capture: take.capture,
                                      outDir: folder.deletingLastPathComponent(), layout: try layoutFrom(list("targets") ?? ["universal"], custom: ExportOptions()),
                                      keepPolarity: opts["keep-polarity"] != nil, extra: [("recorded_with", .string(take.recordedWith))])
        print("re-exported \(out.fileCount) IR files into \(out.folder.path)")

    case "nam-prep":
        guard let recs = opts["rec"], !recs.isEmpty, let name = one("name") else { fail("nam-prep needs --rec and --name") }
        guard let kind = NAMKind(rawValue: one("kind") ?? "amp") else { fail("--kind must be amp or full") }
        var chans: [(name: String, x: [Double], fs: Int)] = []
        for p in recs {
            let info = try WavInfo(Data(contentsOf: URL(fileURLWithPath: p)))
            for c in 0..<info.channels { chans.append(("", try info.channel(c), info.fs)) }
        }
        let names = list("names") ?? (chans.count == recs.count ? recs.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent }
                                                                 : (1...chans.count).map { "ch\($0)" })
        if names.count != chans.count { fail("\(chans.count) channels but \(names.count) names") }
        for i in chans.indices { chans[i].name = names[i] }
        let t0 = Date()
        let res = try NAMPrep.prepare(chans, kind: kind, progress: { if opts["verbose"] != nil { print("  . " + $0) } })
        let folder = try NAMPrep.write(res, capture: name, outDir: URL(fileURLWithPath: one("outdir") ?? "nam_out"))
        for w in res.warnings { print("! " + w) }
        print("wrote \(res.names.count) files to \(folder.path) in \(String(format: "%.1f", Date().timeIntervalSince(t0))) s")

    default:
        fail("unknown command \(cmd)")
    }
} catch {
    fail("error: \(error)")
}
