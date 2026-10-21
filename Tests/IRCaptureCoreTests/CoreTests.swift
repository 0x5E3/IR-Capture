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
}
