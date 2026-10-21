import Foundation

// WAV read/write matching dsp.js: 16-bit (TPDF dither), 24-bit, 32-bit float.

private extension Data {
    mutating func le16(_ v: UInt16) { append(UInt8(v & 0xff)); append(UInt8(v >> 8)) }
    mutating func le32(_ v: UInt32) { for s in stride(from: 0, to: 32, by: 8) { append(UInt8((v >> UInt32(s)) & 0xff)) } }
    mutating func ascii(_ s: String) { append(contentsOf: Array(s.utf8)) }
}

public func writeWav(_ x: [Double], rate: Int, bits: BitDepth) -> Data {
    let n = x.count, bps = bits == .b16 ? 2 : bits == .b24 ? 3 : 4, fmt: UInt16 = bits == .f32 ? 3 : 1
    let dataLen = n * bps, pad = dataLen & 1
    var d = Data(capacity: 44 + dataLen + pad)
    d.ascii("RIFF"); d.le32(UInt32(36 + dataLen + pad)); d.ascii("WAVE")
    d.ascii("fmt "); d.le32(16); d.le16(fmt); d.le16(1)
    d.le32(UInt32(rate)); d.le32(UInt32(rate * bps)); d.le16(UInt16(bps)); d.le16(UInt16(bps * 8))
    d.ascii("data"); d.le32(UInt32(dataLen))
    var bytes = [UInt8](repeating: 0, count: dataLen + pad)
    var o = 0
    for v in x {
        switch bits {
        case .b16:
            var q = jsRound(v * 32767 + (Double.random(in: 0..<1) - Double.random(in: 0..<1)))
            q = max(-32768, min(32767, q))
            let u = UInt16(bitPattern: Int16(q))
            bytes[o] = UInt8(u & 0xff); bytes[o + 1] = UInt8(u >> 8); o += 2
        case .b24:
            var q = Int(jsRound(max(-1, min(1, v)) * 8388607))
            q = max(-8388608, min(8388607, q))
            bytes[o] = UInt8(q & 255); bytes[o + 1] = UInt8((q >> 8) & 255); bytes[o + 2] = UInt8((q >> 16) & 255); o += 3
        case .f32:
            let u = Float(v).bitPattern
            bytes[o] = UInt8(u & 0xff); bytes[o + 1] = UInt8((u >> 8) & 0xff); bytes[o + 2] = UInt8((u >> 16) & 0xff); bytes[o + 3] = UInt8(u >> 24); o += 4
        }
    }
    d.append(contentsOf: bytes)
    return d
}

/// Writes a multichannel 32-bit float WAV (for raw recordings and the test signal).
public func writeWavFloat(_ channels: [[Float]], rate: Int) -> Data {
    let C = channels.count, n = channels.map(\.count).min() ?? 0
    let dataLen = n * C * 4
    var d = Data(capacity: 44 + dataLen)
    d.ascii("RIFF"); d.le32(UInt32(36 + dataLen)); d.ascii("WAVE")
    d.ascii("fmt "); d.le32(16); d.le16(3); d.le16(UInt16(C))
    d.le32(UInt32(rate)); d.le32(UInt32(rate * 4 * C)); d.le16(UInt16(4 * C)); d.le16(32)
    d.ascii("data"); d.le32(UInt32(dataLen))
    var bytes = [UInt8](repeating: 0, count: dataLen)
    bytes.withUnsafeMutableBytes { raw in
        let p = raw.bindMemory(to: UInt32.self)
        for i in 0..<n { for c in 0..<C { p[i * C + c] = channels[c][i].bitPattern.littleEndian } }
    }
    d.append(contentsOf: bytes)
    return d
}

public struct WavInfo {
    public let fs: Int
    public let channels: Int
    public let bits: Int
    public let format: Int
    public let frames: Int
    let dataOff: Int
    let data: Data

    public init(_ data: Data) throws {
        let b = [UInt8](data)
        func str(_ o: Int, _ n: Int) -> String { String(decoding: b[o..<(o + n)], as: UTF8.self) }
        func u16(_ o: Int) -> Int { Int(b[o]) | Int(b[o + 1]) << 8 }
        func u32(_ o: Int) -> Int { u16(o) | u16(o + 2) << 16 }
        guard b.count >= 12, str(0, 4) == "RIFF", str(8, 4) == "WAVE" else { throw IRCaptureError("not a WAV file") }
        var o = 12, fmt: (Int, Int, Int, Int)? = nil, dataOff = -1, dataLen = 0
        while o + 8 <= b.count {
            let id = str(o, 4), len = u32(o + 4)
            if id == "fmt " {
                var af = u16(o + 8)
                if af == 0xFFFE && len >= 40 { af = u16(o + 32) }
                fmt = (af, u16(o + 10), u32(o + 12), u16(o + 22))
            } else if id == "data" {
                dataOff = o + 8; dataLen = min(len, b.count - dataOff); break
            }
            o += 8 + len + (len & 1)
        }
        guard let f = fmt, dataOff >= 0 else { throw IRCaptureError("WAV file has no audio data") }
        format = f.0; channels = f.1; fs = f.2; bits = f.3
        guard channels > 0, bits % 8 == 0, bits > 0 else { throw IRCaptureError("unsupported WAV format") }
        frames = dataLen / (bits / 8 * channels)
        self.dataOff = dataOff; self.data = data
    }

    public func channel(_ c: Int) throws -> [Double] {
        var x = [Double](repeating: 0, count: frames)
        let bps = bits / 8, stride = bps * channels
        try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let base = raw.baseAddress!.advanced(by: dataOff + c * bps)
            func at(_ i: Int) -> UnsafeRawPointer { base.advanced(by: i * stride) }
            switch (format, bits) {
            case (3, 32): for i in 0..<frames { x[i] = Double(Float(bitPattern: UInt32(littleEndian: at(i).loadUnaligned(as: UInt32.self)))) }
            case (3, 64): for i in 0..<frames { x[i] = Double(bitPattern: UInt64(littleEndian: at(i).loadUnaligned(as: UInt64.self))) }
            case (1, 16): for i in 0..<frames { x[i] = Double(Int16(littleEndian: at(i).loadUnaligned(as: Int16.self))) / 32768 }
            case (1, 24):
                for i in 0..<frames {
                    let p = at(i).assumingMemoryBound(to: UInt8.self)
                    let q = Int32(p[0]) | Int32(p[1]) << 8 | Int32(Int8(bitPattern: p[2])) << 16
                    x[i] = Double(q) / 8388608
                }
            case (1, 32): for i in 0..<frames { x[i] = Double(Int32(littleEndian: at(i).loadUnaligned(as: Int32.self))) / 2147483648 }
            default: throw IRCaptureError("unsupported WAV format (\(bits)-bit, code \(format))")
            }
        }
        return x
    }
}
