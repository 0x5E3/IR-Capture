import Foundation

// Radix-2 complex FFT, a direct port of the one in dsp.js so results match the
// page bit-for-bit in structure. Inverse includes the 1/n scale.

public func nextPow2(_ n: Int) -> Int { var p = 1; while p < n { p *= 2 }; return p }

final class FFTTables {
    let n: Int
    let rev: [Int32]
    let cos: [Double]
    let sin: [Double]
    init(_ n: Int) {
        self.n = n
        var bits = 0; while (1 << bits) < n { bits += 1 }
        var rev = [Int32](repeating: 0, count: n)
        for i in 0..<n {
            var r = 0, x = i
            for _ in 0..<bits { r = (r << 1) | (x & 1); x >>= 1 }
            rev[i] = Int32(r)
        }
        let h = n >> 1
        var c = [Double](repeating: 0, count: max(h, 1)), s = [Double](repeating: 0, count: max(h, 1))
        for i in 0..<h { c[i] = Foundation.cos(2 * Double.pi * Double(i) / Double(n)); s[i] = Foundation.sin(2 * Double.pi * Double(i) / Double(n)) }
        self.rev = rev; self.cos = c; self.sin = s
    }
    private static var cache: [Int: FFTTables] = [:]
    private static let lock = NSLock()
    static func get(_ n: Int) -> FFTTables {
        lock.lock(); defer { lock.unlock() }
        if let t = cache[n] { return t }
        if cache.count >= 3 { cache.removeAll() }   // bound memory
        let t = FFTTables(n); cache[n] = t
        return t
    }
}

/// In-place complex FFT on separate real/imaginary buffers.
public func fft(_ re: UnsafeMutablePointer<Double>, _ im: UnsafeMutablePointer<Double>, _ n: Int, inverse: Bool) {
    let t = FFTTables.get(n)
    t.rev.withUnsafeBufferPointer { rev in
        for i in 0..<n {
            let j = Int(rev[i])
            if j > i {
                let a = re[i]; re[i] = re[j]; re[j] = a
                let b = im[i]; im[i] = im[j]; im[j] = b
            }
        }
    }
    let sgn: Double = inverse ? 1 : -1
    t.cos.withUnsafeBufferPointer { cs in
        t.sin.withUnsafeBufferPointer { sn in
            var size = 2
            while size <= n {
                let half = size >> 1, step = n / size
                var i = 0
                while i < n {
                    var k = 0
                    for j in 0..<half {
                        let wr = cs[k], wi = sgn * sn[k]
                        let p = i + j, q = p + half
                        let tr = re[q] * wr - im[q] * wi, ti = re[q] * wi + im[q] * wr
                        re[q] = re[p] - tr; im[q] = im[p] - ti
                        re[p] += tr; im[p] += ti
                        k += step
                    }
                    i += size
                }
                size *= 2
            }
        }
    }
    if inverse { let s = 1.0 / Double(n); for i in 0..<n { re[i] *= s; im[i] *= s } }
}

public func fft(_ re: inout [Double], _ im: inout [Double], inverse: Bool) {
    let n = re.count
    re.withUnsafeMutableBufferPointer { r in
        im.withUnsafeMutableBufferPointer { m in
            fft(r.baseAddress!, m.baseAddress!, n, inverse: inverse)
        }
    }
}

struct KernelSpectrum {
    var re: [Double]
    var im: [Double]
    let nfft: Int
    let M: Int
    init(_ h: [Double], _ nfft: Int) {
        re = [Double](repeating: 0, count: nfft); im = [Double](repeating: 0, count: nfft)
        for i in 0..<h.count { re[i] = h[i] }
        fft(&re, &im, inverse: false)
        self.nfft = nfft; M = h.count
    }
}

/// Overlap-add linear convolution; returns length N+M-1 (Float, like the page).
func convolveOLA(_ x: [Double], _ K: KernelSpectrum) -> [Float] {
    let nfft = K.nfft, M = K.M, B = nfft - M + 1
    var y = [Float](repeating: 0, count: x.count + M - 1)
    var re = [Double](repeating: 0, count: nfft), im = [Double](repeating: 0, count: nfft)
    re.withUnsafeMutableBufferPointer { rp in
    im.withUnsafeMutableBufferPointer { ip in
    K.re.withUnsafeBufferPointer { kr in
    K.im.withUnsafeBufferPointer { ki in
    x.withUnsafeBufferPointer { xp in
    y.withUnsafeMutableBufferPointer { yp in
        let r = rp.baseAddress!, m = ip.baseAddress!
        var s = 0
        while s < x.count {
            r.update(repeating: 0, count: nfft); m.update(repeating: 0, count: nfft)
            let e = min(s + B, x.count)
            for i in s..<e { r[i - s] = xp[i] }
            fft(r, m, nfft, inverse: false)
            for i in 0..<nfft {
                let a = r[i], b = m[i], c = kr[i], d = ki[i]
                r[i] = a * c - b * d; m[i] = a * d + b * c
            }
            fft(r, m, nfft, inverse: true)
            let lim = min(nfft, yp.count - s)
            for i in 0..<lim { yp[s + i] = Float(Double(yp[s + i]) + r[i]) }
            s += B
        }
    }}}}}}
    return y
}
