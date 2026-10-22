import XCTest
@testable import IRCaptureCore

final class CoreTests: XCTestCase {
    func testFFTMatchesDFT() {
        let n = 64
        var re = (0..<n).map { sin(Double($0) * 0.37) + 0.1 * Double($0 % 5) }, im = [Double](repeating: 0, count: n)
        let x = re
        fft(&re, &im, inverse: false)
        for k in [0, 1, 7, 31, 32, 63] {
            var r = 0.0, i = 0.0
            for t in 0..<n { let a = -2 * Double.pi * Double(k * t) / Double(n); r += x[t] * cos(a); i += x[t] * sin(a) }
            XCTAssertEqual(re[k], r, accuracy: 1e-9); XCTAssertEqual(im[k], i, accuracy: 1e-9)
        }
        fft(&re, &im, inverse: true)
        for t in 0..<n { XCTAssertEqual(re[t], x[t], accuracy: 1e-12) }
    }

    func testWavRoundTrip() throws {
        let x = (0..<1000).map { 0.9 * sin(Double($0) * 0.05) }
        for b in BitDepth.allCases {
            let info = try WavInfo(writeWav(x, rate: 48000, bits: b))
            XCTAssertEqual(info.fs, 48000); XCTAssertEqual(info.frames, 1000)
            let y = try info.channel(0)
            let tol = b == .b16 ? 1e-4 : b == .b24 ? 2e-7 : 1e-7
            for i in 0..<1000 { XCTAssertEqual(y[i], x[i], accuracy: tol) }
        }
        let multi = try WavInfo(writeWavFloat([[0.5, 0.25], [-0.5, -0.25], [0.125, 0]], rate: 96000))
        XCTAssertEqual(multi.channels, 3)
        XCTAssertEqual(try multi.channel(1), [-0.5, -0.25])
    }

    func testNames() {
        XCTAssertEqual(rateTag(44100), "44.1k"); XCTAssertEqual(rateTag(96000), "96k"); XCTAssertEqual(rateTag(88200), "88.2k")
        XCTAssertEqual(safeName("  SM57 / 1in  off cap "), "SM57_1in_off_cap")
        XCTAssertEqual(safeName("!!"), "ir")
    }

    func testSpecMatchesReference() throws {
        let s = try SweepSpec(fs: 44100)
        XCTAssertEqual(s.f2, 0.45 * 44100)
        XCTAssertThrowsError(try SweepSpec(nSweeps: 1, discard: 1))
        let back = try SweepSpec.load(jsonData: Data(s.json.serialized().utf8))
        XCTAssertEqual(back, s)
    }

    /// Level check on a fake rig: gain, a little delay, and some 2nd-harmonic distortion.
    func testLevelCheck() throws {
        let lc = try LevelCheck(fs: 48000, levelDBFS: -12)
        func rig(_ g: Double, _ d2: Double) -> [Double] {
            var y = [Double](repeating: 0, count: lc.signal.count)
            for i in 100..<y.count { let u = Double(lc.signal[i - 100]) * 4; y[i] = g * (u + d2 * u * u) }
            return y
        }
        let r = lc.read([rig(0.5, 0), rig(0.5, 0.1)], labels: ["clean", "dirty"], target: -6)
        XCTAssertEqual(r[0].peakDBFS, -12 + 20 * log10(2), accuracy: 0.1)
        XCTAssertEqual(r[0].changeDB, -6 - r[0].peakDBFS, accuracy: 1e-9)
        XCTAssertLessThan(r[0].h2, -60)
        XCTAssertGreaterThan(r[1].h2, -40)
        XCTAssertGreaterThan(r[1].h2, r[0].h2 + 20)
    }

    func testReportIsValidJSON() throws {
        let j = JSON.object([("a", .number(1.5)), ("b", .null), ("c", .string("q\"x\n")), ("d", .array([.int(1)]))]).serialized()
        let o = try JSONSerialization.jsonObject(with: Data(j.utf8)) as! [String: Any]
        XCTAssertEqual(o["c"] as? String, "q\"x\n")
        XCTAssertTrue(o["b"] is NSNull)
    }

    func testNAMWavAndResample() throws {
        let x = (0..<2000).map { Double(Int(0.7 * sin(Double($0) * 0.01) * 8388608)) / 8388608 }
        let info = try WavInfo(NAMPrep.wav24(x))
        XCTAssertEqual(info.fs, 48000); XCTAssertEqual(info.bits, 24); XCTAssertEqual(info.channels, 1)
        XCTAssertEqual(try info.channel(0), x)              // 24-bit values pass through bit for bit
        XCTAssertEqual(NAMPrep.resample(x, 48000, 48000), x)
        let up = NAMPrep.resample(x, 48000, 96000), back = NAMPrep.resample(up, 96000, 48000)
        XCTAssertEqual(up.count, 4000); XCTAssertEqual(back.count, 2000)
        for i in 200..<1800 { XCTAssertEqual(back[i], x[i], accuracy: 1e-3) }
        XCTAssertEqual(NAMPrep.fileName("JCM800 ch2", "SM57 / cap"), "JCM800_ch2_SM57_cap.wav")
        XCTAssertEqual(NAMPrep.safe("!!"), "capture")
    }

    func testNAMRefusesNoise() {
        var g = SystemRandomNumberGenerator()
        let noise = (0..<(48000 * 195)).map { _ in Double.random(in: -0.1...0.1, using: &g) }
        XCTAssertThrowsError(try NAMPrep.prepareChannel(noise, fs: 48000, label: "noise")) { e in
            XCTAssertTrue("\(e)".contains("couldn't find the training signal"))
        }
    }

    /// A small fake capture: two mics (the second inverted), one reference, through the real analysis.
    private func fakeCapture() throws -> (rec: [[Double]], spec: SweepSpec) {
        let spec = try SweepSpec(fs: 48000, duration: 2, nSweeps: 3, discard: 1, gap: 1)
        let x = makeTestSignal(spec).map(Double.init)
        func rig(_ delay: Int, _ g: Double) -> [Double] {
            var y = [Double](repeating: 0, count: x.count + 4800)
            for i in 0..<x.count { y[i + delay] += g * x[i]; y[i + delay + 30] += 0.3 * g * x[i] }
            return y
        }
        return ([rig(200, 0.5), rig(260, -0.4), rig(190, 0.3)], spec)
    }

    func testPolarityFlipsTheInvertedMic() throws {
        let (rec, spec) = try fakeCapture()
        var res = try analyse(rec, spec, names: ["Front", "Back"], refIndex: 2)
        let backPeak = res.irs["Back"]!.map(abs).max()!
        let notes = normalizePolarity(&res)
        XCTAssertEqual(notes, ["Back was inverted relative to Front and has been flipped."])
        XCTAssertEqual(res.polarity["Back"], PolarityInfo(mainPeakNegative: true, flipped: true))
        XCTAssertEqual(res.polarity["Front"], PolarityInfo(mainPeakNegative: false, flipped: false))
        XCTAssertEqual(res.irs["Back"]!.max()!, backPeak, accuracy: 1e-12)
        var kept = try analyse(rec, spec, names: ["Front", "Back"], refIndex: 2)
        let keptNotes = normalizePolarity(&kept, keep: true)
        XCTAssertEqual(kept.polarity["Back"]?.flipped, false)
        XCTAssertEqual(keptNotes.count, 1)
        let report = reportJSON(res, spec: spec, capture: "t")
        XCTAssertTrue(report.contains("\"flipped\": true"))
    }

    func testTargetsLayoutAndRawTake() throws {
        let (rec, spec) = try fakeCapture()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ircapture-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let take = RawTake(capture: "cap", names: ["Front", "Back"], refIndex: 2, spec: spec, recordedWith: "test")
        try take.save(rec.map { $0.map(Float.init) }, captureFolder: dir.appendingPathComponent("cap"))
        let out = try processAndWrite(rec: rec, spec: spec, names: ["Front", "Back"], refIndex: 2, capture: "cap", outDir: dir,
                                      layout: .targets([.universal, .helix, .iridium, .everything], custom: nil))
        XCTAssertEqual(Set(out.files.filter { !$0.contains("/") }), ["cap_Front.wav", "cap_Back.wav"])
        XCTAssertTrue(out.files.contains("More formats/Line 6 Helix/cap_Front_Helix.wav"))
        XCTAssertTrue(out.files.contains("More formats/Strymon Iridium/cap_Back_Iridium.wav"))
        XCTAssertEqual(out.files.filter { $0.hasPrefix("More formats/Everything/") }.count, 32)
        let u = try WavInfo(Data(contentsOf: dir.appendingPathComponent("cap/cap_Front.wav")))
        XCTAssertEqual(u.fs, 48000); XCTAssertEqual(u.bits, 24); XCTAssertEqual(u.frames, 24000)
        let hx = try WavInfo(Data(contentsOf: dir.appendingPathComponent("cap/More formats/Line 6 Helix/cap_Front_Helix.wav")))
        XCTAssertEqual(hx.fs, 48000); XCTAssertEqual(hx.frames, 2048)
        let ir = try WavInfo(Data(contentsOf: dir.appendingPathComponent("cap/More formats/Strymon Iridium/cap_Front_Iridium.wav")))
        XCTAssertEqual(ir.fs, 96000); XCTAssertEqual(ir.frames, 48000); XCTAssertEqual(ir.bits, 24)
        // Universal and Everything's 48k 500 ms file are the same file, level included
        let a = try u.channel(0)
        let b = try WavInfo(Data(contentsOf: dir.appendingPathComponent("cap/More formats/Everything/48k/cap_Front_48k_24_full.wav"))).channel(0)
        XCTAssertEqual(a, b)
        // the level doesn't depend on which targets were chosen
        let dir2 = dir.appendingPathComponent("only")
        _ = try processAndWrite(rec: rec, spec: spec, names: ["Front", "Back"], refIndex: 2, capture: "cap", outDir: dir2,
                                layout: .targets([.universal], custom: nil))
        XCTAssertEqual(try WavInfo(Data(contentsOf: dir2.appendingPathComponent("cap/cap_Front.wav"))).channel(0), a)
        XCTAssertTrue(try String(contentsOf: dir.appendingPathComponent("cap/README.txt")).contains("cap_Front.wav"))
        // raw take round trip
        let (t2, r2) = try RawTake.load(captureFolder: dir.appendingPathComponent("cap"))
        XCTAssertEqual(t2.names, ["Front", "Back"]); XCTAssertEqual(t2.refIndex, 2); XCTAssertEqual(t2.spec, spec)
        XCTAssertEqual(r2.count, 3); XCTAssertEqual(r2[0].count, rec[0].count)
        XCTAssertThrowsError(try RawTake.load(captureFolder: dir2.appendingPathComponent("cap")))
    }

    func testReferenceCandidate() throws {
        let lc = try LevelCheck(fs: 48000, levelDBFS: -12)
        func rig(_ delay: Int, _ tail: Bool) -> [Double] {
            var y = [Double](repeating: 0, count: lc.signal.count + 9600)
            for i in 0..<lc.signal.count {
                let u = Double(lc.signal[i]) * 2
                y[i + delay] += u
                if tail { for (k, g) in [(480, 0.5), (900, -0.4), (1500, 0.3)] { y[i + delay + k] += g * u } }
            }
            return y
        }
        var r = lc.read([rig(110, true), rig(100, false), rig(130, true)], labels: ["SM57", "Input 2", "Room"])
        for i in r.indices { r[i].channel = i }
        XCTAssertLessThan(r[1].tailDB, -30)
        XCTAssertGreaterThan(r[0].tailDB, -20)
        XCTAssertEqual(lc.referenceCandidate(r)?.channel, 1)
        var r2 = lc.read([rig(110, true), rig(130, true)], labels: ["a", "b"])
        for i in r2.indices { r2[i].channel = i }
        XCTAssertNil(lc.referenceCandidate(r2))
    }
}
