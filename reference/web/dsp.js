/* ircapture DSP — JavaScript port of ircapture.py v0.1.
   Runs in the page, in a Web Worker, or in Node (for testing).
   Pipeline: log sweeps -> deconvolution -> averaging + diagnostics ->
   optional speaker-terminal reference division -> set/individual trim ->
   multi-rate, multi-length WAV export -> zip. */
var IRC = (function () {
  "use strict";
  var VERSION = "0.1-web";
  var H_MAX = 5, LIN_PRE_S = 0.020, DIST_WIN_S = 0.050;

  // ------------------------------------------------------------ spec
  function makeSpec(o) {
    var s = {
      fs: 96000, f1: 20, f2: 22000, duration: 6, n_sweeps: 5, discard: 1,
      gap: 2, lead: 1, level_dbfs: -12, fade_in: 0.1, fade_out: 0.005
    };
    for (var k in o) if (o[k] !== undefined) s[k] = o[k];
    s.f2 = Math.min(s.f2, 0.45 * s.fs);
    if (!(s.f1 > 0 && s.f1 < s.f2)) throw new Error("Sweep range is invalid.");
    if (s.n_sweeps - s.discard < 1) throw new Error("Use more sweeps than you discard.");
    s.L = s.duration / Math.log(s.f2 / s.f1);
    s.nSweep = Math.round(s.duration * s.fs);
    s.nGap = Math.round(s.gap * s.fs);
    s.nLead = Math.round(s.lead * s.fs);
    s.period = s.nSweep + s.nGap;
    return s;
  }
  function harmonicAdvance(s, n) { return s.L * Math.log(n); }
  function maxIrSeconds(s) { return s.gap + s.duration - harmonicAdvance(s, 10) - 0.05; }
  function specJSON(s) {
    return { fs: s.fs, f1: s.f1, f2: s.f2, duration: s.duration, n_sweeps: s.n_sweeps,
      discard: s.discard, gap: s.gap, lead: s.lead, level_dbfs: s.level_dbfs,
      fade_in: s.fade_in, fade_out: s.fade_out, ircapture_version: VERSION };
  }

  function halfHann(n, rising) {
    var w = new Float64Array(n);
    for (var i = 0; i < n; i++) {
      var v = 0.5 - 0.5 * Math.cos(Math.PI * (i + 0.5) / n);
      w[rising ? i : n - 1 - i] = v;
    }
    return w;
  }

  function makeSweep(s) {
    var n = s.nSweep, x = new Float64Array(n), L = s.L, k = 2 * Math.PI * s.f1 * L;
    for (var i = 0; i < n; i++) x[i] = Math.sin(k * (Math.exp(i / s.fs / L) - 1));
    var fi = Math.floor(s.fade_in * s.fs), fo = Math.floor(s.fade_out * s.fs), w, j;
    if (fi) { w = halfHann(fi, true); for (j = 0; j < fi; j++) x[j] *= w[j]; }
    if (fo) { w = halfHann(fo, false); for (j = 0; j < fo; j++) x[n - fo + j] *= w[j]; }
    return x;
  }

  function makeTestSignal(s) {
    var sw = makeSweep(s), g = Math.pow(10, s.level_dbfs / 20);
    var out = new Float32Array(s.nLead + s.n_sweeps * s.period + Math.floor(0.5 * s.fs));
    for (var k = 0; k < s.n_sweeps; k++) {
      var o = s.nLead + k * s.period;
      for (var i = 0; i < s.nSweep; i++) out[o + i] = sw[i] * g;
    }
    return out;
  }

  // ------------------------------------------------------------ FFT
  var tables = {};
  function nextPow2(n) { var p = 1; while (p < n) p *= 2; return p; }
  function getTables(n) {
    if (tables[n]) return tables[n];
    var bits = Math.round(Math.log2(n)), rev = new Uint32Array(n), i;
    for (i = 0; i < n; i++) {
      var r = 0, x = i;
      for (var b = 0; b < bits; b++) { r = (r << 1) | (x & 1); x >>= 1; }
      rev[i] = r >>> 0;
    }
    var h = n >> 1, cos = new Float64Array(h), sin = new Float64Array(h);
    for (i = 0; i < h; i++) { cos[i] = Math.cos(2 * Math.PI * i / n); sin[i] = Math.sin(2 * Math.PI * i / n); }
    tables = {}; // keep only one size cached to bound memory
    tables[n] = { rev: rev, cos: cos, sin: sin };
    return tables[n];
  }
  // in-place complex FFT; inverse includes 1/n
  function fft(re, im, inverse) {
    var n = re.length, t = getTables(n), rev = t.rev, cs = t.cos, sn = t.sin, i, j, k;
    for (i = 0; i < n; i++) {
      j = rev[i];
      if (j > i) { var a = re[i]; re[i] = re[j]; re[j] = a; a = im[i]; im[i] = im[j]; im[j] = a; }
    }
    var sgn = inverse ? 1 : -1;
    for (var size = 2; size <= n; size *= 2) {
      var half = size >> 1, step = n / size;
      for (i = 0; i < n; i += size) {
        for (j = 0, k = 0; j < half; j++, k += step) {
          var wr = cs[k], wi = sgn * sn[k];
          var p = i + j, q = p + half;
          var tr = re[q] * wr - im[q] * wi, ti = re[q] * wi + im[q] * wr;
          re[q] = re[p] - tr; im[q] = im[p] - ti;
          re[p] += tr; im[p] += ti;
        }
      }
    }
    if (inverse) for (i = 0; i < n; i++) { re[i] /= n; im[i] /= n; }
  }

  function kernelSpectrum(h, nfft) {
    var re = new Float64Array(nfft), im = new Float64Array(nfft);
    re.set(h);
    fft(re, im, false);
    return { re: re, im: im, nfft: nfft, M: h.length };
  }

  // overlap-add linear convolution; returns Float32Array of length N+M-1
  function convolveOLA(x, K) {
    var nfft = K.nfft, M = K.M, B = nfft - M + 1;
    var y = new Float32Array(x.length + M - 1);
    var re = new Float64Array(nfft), im = new Float64Array(nfft);
    for (var s = 0; s < x.length; s += B) {
      re.fill(0); im.fill(0);
      var e = Math.min(s + B, x.length);
      for (var i = s; i < e; i++) re[i - s] = x[i];
      fft(re, im, false);
      for (i = 0; i < nfft; i++) {
        var a = re[i], b = im[i], c = K.re[i], d = K.im[i];
        re[i] = a * c - b * d; im[i] = a * d + b * c;
      }
      fft(re, im, true);
      var lim = Math.min(nfft, y.length - s);
      for (i = 0; i < lim; i++) y[s + i] += re[i];
    }
    return y;
  }

  function inverseFilter(sweep, s) {
    var n = sweep.length, inv = new Float64Array(n), i;
    for (i = 0; i < n; i++) inv[i] = sweep[n - 1 - i] * Math.exp(-(i / s.fs) / s.L);
    var nfft = nextPow2(2 * n - 1);
    var A = kernelSpectrum(sweep, nfft), B = kernelSpectrum(inv, nfft);
    var lo = Math.max(200, 4 * s.f1), hi = Math.min(8000, s.f2 / 2), vals = [];
    for (i = 0; i <= nfft / 2; i++) {
      var f = i * s.fs / nfft;
      if (f >= lo && f <= hi) {
        var r = A.re[i] * B.re[i] - A.im[i] * B.im[i], m = A.re[i] * B.im[i] + A.im[i] * B.re[i];
        vals.push(Math.sqrt(r * r + m * m));
      }
    }
    var v = Float64Array.from(vals).sort(), med = v.length % 2 ? v[(v.length - 1) / 2] : 0.5 * (v[v.length / 2 - 1] + v[v.length / 2]);
    for (i = 0; i < n; i++) inv[i] /= med;
    return inv;
  }

  // ------------------------------------------------------------ analysis
  function absMax(a, s0, s1) {
    var m = 0; s0 = s0 || 0; s1 = s1 === undefined ? a.length : s1;
    for (var i = s0; i < s1; i++) { var v = Math.abs(a[i]); if (v > m) m = v; }
    return m;
  }
  function argAbsMax(a, s0, s1) {
    var m = -1, k = s0; for (var i = s0; i < s1; i++) { var v = Math.abs(a[i]); if (v > m) { m = v; k = i; } }
    return k;
  }

  function locateImpulses(h, s, tol) {
    tol = tol || 4;
    var P = s.period, g = argAbsMax(h, 0, h.length), gv = Math.abs(h[g]);
    function peakNear(i) {
      var lo = Math.max(0, i - tol), hi = Math.min(h.length, i + tol + 1);
      if (lo >= hi) return null;
      var j = argAbsMax(h, lo, hi);
      return Math.abs(h[j]) > 0.5 * gv ? j : null;
    }
    var first = g, j;
    while ((j = peakNear(first - P)) !== null) first = j;
    var found = [first];
    while ((j = peakNear(found[found.length - 1] + P)) !== null) found.push(j);
    var expected = [], jitter = 0;
    for (var k = 0; k < found.length; k++) {
      expected.push(first + k * P);
      jitter = Math.max(jitter, Math.abs(found[k] - expected[k]));
    }
    return { expected: expected, jitter: jitter };
  }

  function bandWeight(f, f1, f2, nyq) {
    var loA = f1 / 2, loB = f1 * 1.5, hiA = f2 * 0.8, hiB = Math.min(f2 * 1.25, nyq);
    var lf = Math.log2(Math.max(f, 1e-3));
    function ramp(x0, x1) { return Math.min(1, Math.max(0, (lf - Math.log2(x0)) / (Math.log2(x1) - Math.log2(x0)))); }
    var lo = 1 - ramp(loA, loB), hi = ramp(hiA, hiB);
    var e = 6 * Math.max(0.5 - 0.5 * Math.cos(Math.PI * lo), 0.5 - 0.5 * Math.cos(Math.PI * hi));
    return Math.pow(10, e);
  }

  function divideByReference(hm, hr, s, npre, regDb) {
    var W = hm.length, nfft = nextPow2(2 * W);
    var mr = new Float64Array(nfft), mi = new Float64Array(nfft), rr = new Float64Array(nfft), ri = new Float64Array(nfft), i;
    mr.set(hm); rr.set(hr);
    fft(mr, mi, false); fft(rr, ri, false);
    var pmax = 0, pr = new Float64Array(nfft);
    for (i = 0; i < nfft; i++) { pr[i] = rr[i] * rr[i] + ri[i] * ri[i]; if (pr[i] > pmax) pmax = pr[i]; }
    var base = pmax * Math.pow(10, -regDb / 10);
    for (i = 0; i < nfft; i++) {
      var bin = i <= nfft / 2 ? i : nfft - i;
      var eps = base * bandWeight(bin * s.fs / nfft, s.f1, s.f2, s.fs / 2);
      var den = pr[i] + eps;
      // (m * conj(r)) / den
      var a = mr[i], b = mi[i], c = rr[i], d = -ri[i];
      mr[i] = (a * c - b * d) / den; mi[i] = (a * d + b * c) / den;
    }
    fft(mr, mi, true);
    var out = new Float64Array(W);
    for (i = 0; i < npre; i++) out[i] = mr[nfft - npre + i];
    for (i = npre; i < W; i++) out[i] = mr[i - npre];
    return out;
  }

  function onsetIndex(h, thrDb) {
    var pk = absMax(h), thr = pk * Math.pow(10, -thrDb / 20);
    for (var i = 0; i < h.length; i++) if (Math.abs(h[i]) > thr) return i;
    return 0;
  }

  function db10(x) { return 10 * Math.log10(Math.max(x, 1e-30)); }
  function round(x, d) { var p = Math.pow(10, d); return Math.round(x * p) / p; }

  /* rec: array of Float64Array channels at s.fs. names: one per non-reference
     channel. refIndex: channel index of the reference tap or null. */
  function analyse(rec, s, names, refIndex, opt, progress) {
    opt = Object.assign({ ir_max: 1.0, reg_db: 40, onset_db: 20 }, opt || {});
    progress = progress || function () {};
    var fs = s.fs, C = rec.length, i, k, n;
    var micRows = [];
    for (i = 0; i < C; i++) if (i !== refIndex) micRows.push(i);
    if (names.length !== micRows.length) throw new Error(micRows.length + " mic channels but " + names.length + " names");
    var labels = [];
    for (i = 0; i < C; i++) labels.push(i === refIndex ? "reference" : names[micRows.indexOf(i)]);
    var warnings = [];
    var recPeaks = rec.map(function (r) { return 20 * Math.log10(Math.max(absMax(r), 1e-12)); });
    recPeaks.forEach(function (p, i) {
      if (p > -0.3) warnings.push(labels[i] + ": the recording peaks at " + p.toFixed(1) + " dBFS and has probably clipped. Lower that input's gain and record again.");
      else if (p < -30) warnings.push(labels[i] + ": the recording peaks at only " + p.toFixed(1) + " dBFS. Raise that input's gain.");
    });

    progress("Building the inverse sweep");
    var inv = inverseFilter(makeSweep(s), s);
    var K = kernelSpectrum(inv, nextPow2(2 * inv.length));
    var h = [];
    for (i = 0; i < C; i++) {
      progress("Deconvolving " + labels[i] + " (" + (i + 1) + " of " + C + ")");
      h.push(convolveOLA(rec[i], K));
    }
    K = null;

    var anchor = refIndex;
    if (anchor === null || anchor === undefined) {
      var best = -1; anchor = 0;
      for (i = 0; i < C; i++) { var m = absMax(h[i]); if (m > best) { best = m; anchor = i; } }
    }
    progress("Finding the sweeps");
    var loc = locateImpulses(h[anchor], s);
    if (loc.expected.length !== s.n_sweeps)
      warnings.push("Found " + loc.expected.length + " sweeps but the test signal has " + s.n_sweeps + ". Check that the sweep settings match the test signal you recorded, and that the whole pass was recorded.");
    if (loc.jitter > 1)
      warnings.push("The sweeps drift by up to " + loc.jitter + " samples. Playback and recording may not be on the same interface clock.");

    var pre = Math.round((harmonicAdvance(s, H_MAX + 0.5) + 0.02) * fs);
    var seglen = s.period;
    var used = [];
    loc.expected.forEach(function (p, k) {
      if (k < s.discard) return;
      if (p - pre >= 0 && p - pre + seglen <= h[anchor].length) used.push(p);
    });
    if (!used.length) throw new Error("No complete sweeps were found. Check that the sweep settings match the test signal you recorded.");
    if (used.length < 2) warnings.push("Only one usable sweep, so the noise floor can't be measured.");

    var irMax = Math.min(opt.ir_max, maxIrSeconds(s), (seglen - pre) / fs - 0.05);
    if (irMax < opt.ir_max - 1e-9) warnings.push("The analysis window was shortened to " + irMax.toFixed(2) + " s by the sweep timing. Use a longer gap for longer room tails.");
    var npre = Math.round(LIN_PRE_S * fs), nlin = npre + Math.round(irMax * fs);
    var a0 = pre - npre, keep = pre + nlin, Kn = used.length;

    // averaged region [p-pre, p-pre+keep) per channel, plus per-sweep linear windows
    var avg = [], linK = [], lin = [];
    for (i = 0; i < C; i++) {
      var A = new Float64Array(keep), LK = [];
      for (k = 0; k < Kn; k++) {
        var o = used[k] - pre, hi = h[i];
        for (n = 0; n < keep; n++) A[n] += hi[o + n];
        LK.push(Float64Array.from(hi.subarray(o + a0, o + a0 + nlin)));
      }
      for (n = 0; n < keep; n++) A[n] /= Kn;
      avg.push(A); linK.push(LK); lin.push(A.slice(a0, a0 + nlin));
    }
    h = null;

    progress("Measuring noise and distortion");
    var diag = {}, L = s.L, w = Math.round(DIST_WIN_S * fs), g1 = Math.round(0.001 * fs);
    for (i = 0; i < C; i++) {
      var x = lin[i], peak = absMax(x), d = { recording_peak_dbfs: round(recPeaks[i], 1) }, noiseRms = 0, q;
      if (Kn >= 2) {
        var acc = 0;
        for (n = 0; n < nlin; n++) {
          var ss = 0;
          for (k = 0; k < Kn; k++) { var r = linK[i][k][n] - x[n]; ss += r * r; }
          acc += ss;
        }
        noiseRms = Math.sqrt(acc / nlin / (Kn - 1) / Kn);
        d.noise_floor_db = round(20 * Math.log10(Math.max(noiseRms, 1e-30) / peak), 1);
        var wl = Math.round(0.01 * fs), half = Math.floor(wl / 2), cs = new Float64Array(nlin + 1);
        for (n = 0; n < nlin; n++) cs[n + 1] = cs[n] + x[n] * x[n];
        var last = -1;
        for (n = 0; n < nlin; n++) {
          var s0 = Math.max(0, n - half), s1 = Math.min(nlin, n - half + wl);
          var env = Math.sqrt(Math.max(0, cs[s1] - cs[s0]) / wl);
          if (env > 2 * noiseRms) last = n;
        }
        q = argAbsMax(x, 0, nlin);
        d.tail_above_noise_ms = last >= 0 ? round((last - q) / fs * 1000, 1) : 0;
        var rmsX = 0; for (n = 0; n < nlin; n++) rmsX += x[n] * x[n];
        var lv = [], cc = [], nx = Math.sqrt(rmsX);
        for (k = 0; k < Kn; k++) {
          var e2 = 0, dot = 0, y = linK[i][k];
          for (n = 0; n < nlin; n++) { e2 += y[n] * y[n]; dot += y[n] * x[n]; }
          lv.push(10 * Math.log10(e2 / rmsX)); cc.push(dot / (Math.sqrt(e2) * nx));
        }
        d.sweep_level_spread_db = round(Math.max.apply(null, lv) - Math.min.apply(null, lv), 2);
        d.sweep_min_correlation = round(Math.min.apply(null, cc), 5);
      }
      q = a0 + argAbsMax(x, 0, nlin);
      var eLin = 0; for (n = q - g1; n < q + w; n++) eLin += avg[i][n] * avg[i][n];
      var eNoise = noiseRms * noiseRms * (w + g1), hd = {}, worst = null;
      for (var hn = 2; hn <= H_MAX; hn++) {
        var c = q - Math.round(L * Math.log(hn) * fs), e = 0;
        for (n = c - g1; n < c + w; n++) if (n >= 0) e += avg[i][n] * avg[i][n];
        var v = (Kn >= 2 && e < 2 * eNoise) ? null : round(db10(e / eLin), 1);
        hd["H" + hn] = v;
        if (v !== null && (worst === null || v > worst)) worst = v;
      }
      d.harmonics_db = hd;
      if (worst !== null && worst > -30 && i !== refIndex)
        warnings.push(labels[i] + ": harmonic distortion is " + Math.round(worst) + " dB below the linear response. The speaker is being driven hard; an IR can't capture that, so try about 6 dB less level.");
      diag[labels[i]] = d;
    }

    progress("Computing the impulse responses");
    var irs = {}, onsets = {};
    names.forEach(function (nm, j) {
      var r = micRows[j];
      irs[nm] = (refIndex !== null && refIndex !== undefined) ? divideByReference(lin[r], lin[refIndex], s, npre, opt.reg_db) : lin[r].slice();
      onsets[nm] = onsetIndex(irs[nm], opt.onset_db);
    });
    var firstOn = Math.min.apply(null, names.map(function (nm) { return onsets[nm]; }));
    names.forEach(function (nm) {
      diag[nm].arrival_ms = round((onsets[nm] - npre) / fs * 1000, 3);
      diag[nm].delay_vs_first_mic_ms = round((onsets[nm] - firstOn) / fs * 1000, 3);
    });
    return {
      irs: irs, fs: fs, t0: npre, onsets: onsets,
      mode: (refIndex !== null && refIndex !== undefined) ? "reference" : "sweep",
      sweeps_used: Kn, timing_jitter_samples: loc.jitter, analysis_window_s: round(irMax, 3),
      diagnostics: diag, warnings: warnings, names: names.slice()
    };
  }

  // ------------------------------------------------------------ resampling
  var KAISER_BETA = 8.6, ZC = 32, KT = 8192, kaiserTab = null;
  function besselI0(x) { var s = 1, t = 1, k = 1; for (; k < 60; k++) { t *= (x / (2 * k)) * (x / (2 * k)); s += t; if (t < 1e-17 * s) break; } return s; }
  function kaiserAt(u) { // u in [0,1]
    if (!kaiserTab) {
      kaiserTab = new Float64Array(KT + 2); var i0 = besselI0(KAISER_BETA);
      for (var i = 0; i <= KT + 1; i++) { var v = Math.min(1, i / KT); kaiserTab[i] = besselI0(KAISER_BETA * Math.sqrt(1 - v * v)) / i0; }
    }
    var p = u * KT, i = Math.floor(p), f = p - i;
    return kaiserTab[i] * (1 - f) + kaiserTab[i + 1] * f;
  }
  // band-limited (windowed-sinc) resampler, zero phase, preserves sample amplitude
  function resampleTo(x, fs, rate) {
    if (rate === fs) return Float64Array.from(x);
    var ratio = rate / fs, c = Math.min(1, ratio) * 0.97, halfW = ZC / c;
    var n = Math.round(x.length * ratio), y = new Float64Array(n);
    for (var m = 0; m < n; m++) {
      var t = m / ratio, lo = Math.max(0, Math.ceil(t - halfW)), hi = Math.min(x.length - 1, Math.floor(t + halfW)), acc = 0;
      for (var k = lo; k <= hi; k++) {
        var d = t - k, a = c * d, sinc = a === 0 ? 1 : Math.sin(Math.PI * a) / (Math.PI * a);
        acc += x[k] * c * sinc * kaiserAt(Math.abs(d) / halfW);
      }
      y[m] = acc;
    }
    return y;
  }

  function cut(h, start, n, nIn, fadeFrac) {
    var out = new Float64Array(n), s0 = Math.max(start, 0), s1 = Math.min(start + n, h.length), i, w;
    for (i = s0; i < s1; i++) out[i - start] = h[i];
    if (nIn > 0) { w = halfHann(nIn, true); for (i = 0; i < nIn; i++) out[i] *= w[i]; }
    var nf = Math.max(Math.floor(fadeFrac * n), 2);
    w = halfHann(nf, false);
    for (i = 0; i < nf; i++) out[n - nf + i] *= w[i];
    return out;
  }

  // ------------------------------------------------------------ WAV
  function writeWav(x, rate, bits) {
    var n = x.length, bps = bits === "16" ? 2 : bits === "24" ? 3 : 4, fmt = bits === "32f" ? 3 : 1;
    var dataLen = n * bps, buf = new ArrayBuffer(44 + dataLen + (dataLen & 1)), v = new DataView(buf), i, q;
    function str(o, s) { for (var j = 0; j < s.length; j++) v.setUint8(o + j, s.charCodeAt(j)); }
    str(0, "RIFF"); v.setUint32(4, 36 + dataLen + (dataLen & 1), true); str(8, "WAVE");
    str(12, "fmt "); v.setUint32(16, 16, true); v.setUint16(20, fmt, true); v.setUint16(22, 1, true);
    v.setUint32(24, rate, true); v.setUint32(28, rate * bps, true); v.setUint16(32, bps, true); v.setUint16(34, bps * 8, true);
    str(36, "data"); v.setUint32(40, dataLen, true);
    var o = 44;
    for (i = 0; i < n; i++) {
      if (bits === "16") {
        q = Math.round(x[i] * 32767 + (Math.random() - Math.random()));
        v.setInt16(o, Math.max(-32768, Math.min(32767, q)), true); o += 2;
      } else if (bits === "24") {
        q = Math.round(Math.max(-1, Math.min(1, x[i])) * 8388607);
        q = Math.max(-8388608, Math.min(8388607, q));
        v.setUint8(o, q & 255); v.setUint8(o + 1, (q >> 8) & 255); v.setUint8(o + 2, (q >> 16) & 255); o += 3;
      } else { v.setFloat32(o, x[i], true); o += 4; }
    }
    return new Uint8Array(buf);
  }

  function readWav(buf) {
    var v = new DataView(buf), str = function (o, n) { var s = ""; for (var j = 0; j < n; j++) s += String.fromCharCode(v.getUint8(o + j)); return s; };
    if (buf.byteLength < 12 || str(0, 4) !== "RIFF" || str(8, 4) !== "WAVE") throw new Error("not a WAV file");
    var o = 12, fmt = null, dataOff = -1, dataLen = 0;
    while (o + 8 <= buf.byteLength) {
      var id = str(o, 4), len = v.getUint32(o + 4, true);
      if (id === "fmt ") {
        var af = v.getUint16(o + 8, true);
        fmt = { format: af, ch: v.getUint16(o + 10, true), fs: v.getUint32(o + 12, true), bits: v.getUint16(o + 22, true) };
        if (af === 0xFFFE && len >= 40) fmt.format = v.getUint16(o + 32, true);
      } else if (id === "data") { dataOff = o + 8; dataLen = Math.min(len, buf.byteLength - dataOff); break; }
      o += 8 + len + (len & 1);
    }
    if (!fmt || dataOff < 0) throw new Error("WAV file has no audio data");
    var bps = fmt.bits / 8, frames = Math.floor(dataLen / (bps * fmt.ch));
    return { fs: fmt.fs, channels: fmt.ch, bits: fmt.bits, format: fmt.format, frames: frames, dataOff: dataOff, bps: bps, view: v };
  }
  function wavChannel(info, c) {
    var x = new Float64Array(info.frames), v = info.view, bps = info.bps, stride = bps * info.channels, o = info.dataOff + c * bps, i;
    if (info.format === 3 && info.bits === 32) for (i = 0; i < info.frames; i++, o += stride) x[i] = v.getFloat32(o, true);
    else if (info.format === 3 && info.bits === 64) for (i = 0; i < info.frames; i++, o += stride) x[i] = v.getFloat64(o, true);
    else if (info.format === 1 && info.bits === 16) for (i = 0; i < info.frames; i++, o += stride) x[i] = v.getInt16(o, true) / 32768;
    else if (info.format === 1 && info.bits === 24) for (i = 0; i < info.frames; i++, o += stride) {
      var q = v.getUint8(o) | (v.getUint8(o + 1) << 8) | (v.getInt8(o + 2) << 16); x[i] = q / 8388608;
    }
    else if (info.format === 1 && info.bits === 32) for (i = 0; i < info.frames; i++, o += stride) x[i] = v.getInt32(o, true) / 2147483648;
    else throw new Error("unsupported WAV format (" + info.bits + "-bit, code " + info.format + ")");
    return x;
  }

  // ------------------------------------------------------------ zip (stored)
  var crcTab = null;
  function crc32(u8) {
    if (!crcTab) { crcTab = new Uint32Array(256); for (var n = 0; n < 256; n++) { var c = n; for (var k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1; crcTab[n] = c >>> 0; } }
    var crc = 0xFFFFFFFF; for (var i = 0; i < u8.length; i++) crc = crcTab[(crc ^ u8[i]) & 255] ^ (crc >>> 8);
    return (crc ^ 0xFFFFFFFF) >>> 0;
  }
  function makeZip(files) { // [{path, data: Uint8Array}]
    var enc = new TextEncoder(), parts = [], central = [], off = 0, now = new Date();
    var dt = ((now.getHours() << 11) | (now.getMinutes() << 5) | (now.getSeconds() >> 1)) & 0xFFFF;
    var dd = (((now.getFullYear() - 1980) << 9) | ((now.getMonth() + 1) << 5) | now.getDate()) & 0xFFFF;
    files.forEach(function (f) {
      var name = enc.encode(f.path), crc = crc32(f.data), sz = f.data.length;
      var lh = new DataView(new ArrayBuffer(30));
      lh.setUint32(0, 0x04034b50, true); lh.setUint16(4, 20, true); lh.setUint16(6, 0x0800, true); lh.setUint16(8, 0, true);
      lh.setUint16(10, dt, true); lh.setUint16(12, dd, true); lh.setUint32(14, crc, true); lh.setUint32(18, sz, true); lh.setUint32(22, sz, true);
      lh.setUint16(26, name.length, true); lh.setUint16(28, 0, true);
      parts.push(new Uint8Array(lh.buffer), name, f.data);
      var ch = new DataView(new ArrayBuffer(46));
      ch.setUint32(0, 0x02014b50, true); ch.setUint16(4, 20, true); ch.setUint16(6, 20, true); ch.setUint16(8, 0x0800, true); ch.setUint16(10, 0, true);
      ch.setUint16(12, dt, true); ch.setUint16(14, dd, true); ch.setUint32(16, crc, true); ch.setUint32(20, sz, true); ch.setUint32(24, sz, true);
      ch.setUint16(28, name.length, true); ch.setUint32(42, off, true);
      central.push(new Uint8Array(ch.buffer), name);
      off += 30 + name.length + sz;
    });
    var csize = central.reduce(function (a, b) { return a + b.length; }, 0);
    var end = new DataView(new ArrayBuffer(22));
    end.setUint32(0, 0x06054b50, true); end.setUint16(8, files.length, true); end.setUint16(10, files.length, true);
    end.setUint32(12, csize, true); end.setUint32(16, off, true);
    return new Blob(parts.concat(central, [new Uint8Array(end.buffer)]), { type: "application/zip" });
  }

  // ------------------------------------------------------------ export
  function safeName(s) { return String(s).trim().replace(/[^A-Za-z0-9._-]+/g, "_").replace(/^_+|_+$/g, "") || "ir"; }
  function rateTag(r) { return (r / 1000).toString().replace(/\.0+$/, "") + "k"; }

  function exportFiles(res, capture, opt, progress) {
    opt = Object.assign({ rates: [44100, 48000, 88200, 96000], lengths: ["full", 1024, 2048, 4096], full_ms: 500,
      bits: ["24"], trim: ["set"], preroll_ms: 0.25, fade_frac: 0.10, peak_dbfs: -1 }, opt || {});
    progress = progress || function () {};
    var fs = res.fs, names = res.names, onsets = res.onsets, preFs = opt.preroll_ms / 1000 * fs, files = [];
    var resampled = {};
    opt.rates.forEach(function (rate) {
      progress("Resampling to " + rateTag(rate));
      names.forEach(function (m) {
        var y = resampleTo(res.irs[m], fs, rate), g = fs / rate; // keep convolution gain equal across rates
        for (var i = 0; i < y.length; i++) y[i] *= g;
        resampled[m + "@" + rate] = y;
      });
    });
    var firstOn = Math.min.apply(null, names.map(function (m) { return onsets[m]; }));
    opt.trim.forEach(function (mode) {
      var vars = [];
      opt.rates.forEach(function (rate) {
        var setStart = Math.round((firstOn - preFs) * rate / fs), nIn = Math.round(opt.preroll_ms / 1000 * rate);
        names.forEach(function (m) {
          var hr = resampled[m + "@" + rate];
          var start = mode === "set" ? setStart : Math.round((onsets[m] - preFs) * rate / fs);
          opt.lengths.forEach(function (ln) {
            var n = ln === "full" ? Math.round(opt.full_ms / 1000 * rate) : +ln;
            vars.push({ mic: m, rate: rate, len: ln, x: cut(hr, start, n, nIn, opt.fade_frac) });
          });
        });
      });
      var target = Math.pow(10, opt.peak_dbfs / 20), gains = {};
      if (mode === "set") {
        var g = target / Math.max.apply(null, vars.map(function (v) { return absMax(v.x); }));
        names.forEach(function (m) { gains[m] = g; });
      } else names.forEach(function (m) {
        gains[m] = target / Math.max.apply(null, vars.filter(function (v) { return v.mic === m; }).map(function (v) { return absMax(v.x); }));
      });
      res.gains = res.gains || {}; res.gains[mode] = gains;
      progress("Writing " + mode + "-trimmed files");
      vars.forEach(function (v) {
        var y = new Float64Array(v.x.length), gg = gains[v.mic];
        for (var i = 0; i < y.length; i++) y[i] = v.x[i] * gg;
        opt.bits.forEach(function (b) {
          files.push({ path: capture + "/" + mode + "/" + rateTag(v.rate) + "/" + capture + "_" + safeName(v.mic) + "_" + rateTag(v.rate) + "_" + b + "_" + v.len + ".wav",
            data: writeWav(y, v.rate, b) });
        });
      });
    });
    return files;
  }

  // 1/6-octave smoothed magnitude of each mic IR, after the set gain, for plotting
  function responseCurves(res, gain, fc) {
    fc = fc || (function () { var a = []; for (var i = 0; i < 160; i++) a.push(20 * Math.pow(1000, i / 159)); return a; })();
    var out = { fc: fc, curves: {} }, fs = res.fs;
    res.names.forEach(function (m) {
      var h = res.irs[m], start = Math.max(0, res.onsets[m] - Math.round(0.00025 * fs)), n = Math.min(h.length - start, Math.round(0.5 * fs));
      var nfft = nextPow2(Math.max(n, 1 << 16)), re = new Float64Array(nfft), im = new Float64Array(nfft), i;
      for (i = 0; i < n; i++) re[i] = h[start + i] * (gain || 1);
      fft(re, im, false);
      var P = new Float64Array(nfft / 2 + 1); for (i = 0; i <= nfft / 2; i++) P[i] = re[i] * re[i] + im[i] * im[i];
      var cs = new Float64Array(P.length + 1); for (i = 0; i < P.length; i++) cs[i + 1] = cs[i] + P[i];
      out.curves[m] = fc.map(function (c) {
        var lo = Math.max(1, Math.floor(c * Math.pow(2, -1 / 12) * nfft / fs)), hi = Math.max(lo + 1, Math.ceil(c * Math.pow(2, 1 / 12) * nfft / fs));
        hi = Math.min(hi, P.length);
        return round(db10((cs[hi] - cs[lo]) / (hi - lo)), 2);
      });
    });
    return out;
  }

  // Make each IR's main peak positive, so mics sum without cancelling (as commercial packs do).
  // Port of normalize_polarity() in ircapture.py. Returns notes; records res.polarity.
  function normalizePolarity(res, keep) {
    var names = res.names, pol = {}, notes = [];
    names.forEach(function (m) {
      var h = res.irs[m], k = 0, best = -1;
      for (var i = 0; i < h.length; i++) { var a = Math.abs(h[i]); if (a > best) { best = a; k = i; } }
      var neg = h[k] < 0, flip = neg && !keep;
      if (flip) for (var j = 0; j < h.length; j++) h[j] = -h[j];
      pol[m] = { main_peak: neg ? "negative" : "positive", flipped: flip };
    });
    res.polarity = { mode: keep ? "keep" : "positive", mics: pol };
    var flipped = names.filter(function (m) { return pol[m].flipped; }), kept = names.filter(function (m) { return !pol[m].flipped; });
    flipped.forEach(function (m) {
      notes.push(kept.length ? m + " was inverted relative to " + kept[0] + " and has been flipped." : m + " came out inverted (main peak negative) and has been flipped.");
    });
    if (keep) names.forEach(function (m) { if (pol[m].main_peak === "negative") notes.push(m + " is inverted (main peak negative). It was kept as recorded."); });
    return notes;
  }

  function reportJSON(res, s, capture, extra) {
    var r = { capture: capture, created: new Date().toISOString(), ircapture_version: VERSION, sweep: specJSON(s) };
    ["mode", "sweeps_used", "timing_jitter_samples", "analysis_window_s", "diagnostics", "warnings"].forEach(function (k) { r[k] = res[k]; });
    if (res.polarity) r.polarity = res.polarity;
    if (extra) for (var k in extra) r[k] = extra[k];
    return JSON.stringify(r, null, 2);
  }

  return {
    VERSION: VERSION, makeSpec: makeSpec, specJSON: specJSON, makeSweep: makeSweep, makeTestSignal: makeTestSignal,
    inverseFilter: inverseFilter, analyse: analyse, onsetIndex: onsetIndex, resampleTo: resampleTo,
    exportFiles: exportFiles, responseCurves: responseCurves, reportJSON: reportJSON, normalizePolarity: normalizePolarity,
    writeWav: writeWav, readWav: readWav, wavChannel: wavChannel, makeZip: makeZip, safeName: safeName, rateTag: rateTag,
    fft: fft, nextPow2: nextPow2
  };
})();
if (typeof module !== "undefined") module.exports = IRC;
