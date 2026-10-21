/* namprep — JavaScript port of namprep.py v0.1.
   Lines a recording of NAM's v3 training signal (TONE3000's sweep file) up
   to the sample and cuts it to the exact length, with checks. Runs in the
   page or in Node (for testing). Needs IRC (dsp.js) for the FFT. */
var NAMPREP = (function () {
  "use strict";
  var VERSION = "0.1-web";
  var LAYOUT = __NAM_LAYOUT__;
  var FS = 48000, N = LAYOUT.length, BLIPS = LAYOUT.blips, VAL = LAYOUT.validation_length;
  var NOISE = [420000, 498000], FIRST = LAYOUT.first_sound, LAST = LAYOUT.last_sound, EB = LAYOUT.env_block;
  var ENV = LAYOUT.env_db;
  var CLICK_WIN = 960, DRIFT_SEG = [24000, 360000], DRIFT_MAX = 48, MIN_ENV_CORR = 0.6;

  function PrepError(msg) { var e = new Error(msg); e.prep = true; return e; }

  // ---------------------------------------------------------------- resampling
  var KB = 8.6, ZC = 32, KT = 8192, KTAB = null;
  function besselI0(x) { var s = 1, t = 1; for (var k = 1; k < 60; k++) { t *= (x / (2 * k)) * (x / (2 * k)); s += t; if (t < 1e-17 * s) break; } return s; }
  function ktab() {
    if (!KTAB) { KTAB = new Float64Array(KT + 2); var i0 = besselI0(KB); for (var i = 0; i <= KT + 1; i++) { var v = Math.min(1, i / KT); KTAB[i] = besselI0(KB * Math.sqrt(1 - v * v)) / i0; } }
    return KTAB;
  }
  function kernel(d, c, halfW) {
    var a = c * d, sinc = a === 0 ? 1 : Math.sin(Math.PI * a) / (Math.PI * a), tab = ktab();
    var p = Math.abs(d) / halfW * KT, i = Math.floor(p); if (i < 0) i = 0; if (i > KT) i = KT;
    var f = p - i;
    return c * sinc * (tab[i] * (1 - f) + tab[i + 1] * f);
  }
  function gcd(a, b) { while (b) { var t = a % b; a = b; b = t; } return a; }
  // polyphase form of the windowed-sinc resampler (same samples as namprep.py)
  function resampleTo(x, fs, rate) {
    if (rate === fs) return Float64Array.from(x);
    var g = gcd(fs, rate), P = rate / g, Q = fs / g, ratio = rate / fs, c = Math.min(1, ratio) * 0.97, halfW = ZC / c;
    var n = Math.floor(x.length * ratio + 0.5), y = new Float64Array(n), L = x.length;
    for (var r = 0; r < Math.min(P, n); r++) {
      var cnt = Math.floor((n - 1 - r) / P) + 1, t = r / ratio, lo = Math.ceil(t - halfW), hi = Math.floor(t + halfW);
      var nw = hi - lo + 1, w = new Float64Array(nw);
      for (var j = 0; j < nw; j++) w[j] = kernel(t - (lo + j), c, halfW);
      for (var u = 0; u < cnt; u++) {
        var base = Q * u + lo, acc = 0;
        for (j = 0; j < nw; j++) { var k = base + j; acc += w[j] * (k >= 0 && k < L ? x[k] : 0); }
        y[r + P * u] = acc;
      }
    }
    return y;
  }

  // ---------------------------------------------------------------- helpers
  function db(x) { return x > 0 ? 20 * Math.log10(x) : -200; }
  function rnd(x, d) { var p = Math.pow(10, d); return Math.floor(x * p + 0.5) / p; }
  function absMax(a, s0, s1) { var m = 0; for (var i = s0; i < s1; i++) { var v = Math.abs(a[i]); if (v > m) m = v; } return m; }
  function take(x, d, n) {
    var out = new Float64Array(n), s0 = Math.max(0, d), s1 = Math.min(x.length, d + n);
    for (var i = s0; i < s1; i++) out[i - d] = x[i];
    return out;
  }
  function envelopeDb(x) {
    var nb = Math.floor(x.length / EB), e = new Float64Array(nb);
    for (var b = 0; b < nb; b++) {
      var s = 0, o = b * EB; for (var i = 0; i < EB; i++) s += x[o + i] * x[o + i];
      e[b] = 20 * Math.log10(Math.max(Math.sqrt(s / EB), 1e-5));
    }
    return e;
  }
  function coarseOffset(x) {
    var env = envelopeDb(x), L = ENV.length, mean = 0, i;
    for (i = 0; i < L; i++) mean += ENV[i];
    mean /= L;
    var T = new Float64Array(L), tn = 0;
    for (i = 0; i < L; i++) { T[i] = ENV[i] - mean; tn += T[i] * T[i]; }
    tn = Math.sqrt(tn);
    var kmin = -Math.floor(FIRST / EB), pad = -kmin, e = new Float64Array(pad + env.length + L).fill(-100);
    e.set(env, pad);
    var kmax = env.length - Math.floor(L / 2);
    var cs = new Float64Array(e.length + 1), cs2 = new Float64Array(e.length + 1);
    for (i = 0; i < e.length; i++) { cs[i + 1] = cs[i] + e[i]; cs2[i + 1] = cs2[i] + e[i] * e[i]; }
    var best = -2, bk = null, kend = Math.max(kmin + 1, kmax);
    for (var k = kmin; k < kend; k++) {
      var s = k + pad;
      if (s + L > e.length) break;
      var sm = cs[s + L] - cs[s], ss = cs2[s + L] - cs2[s] - sm * sm / L;
      if (ss <= 1e-9) continue;
      var dot = 0; for (i = 0; i < L; i++) dot += e[s + i] * T[i];
      var r = dot / (Math.sqrt(ss) * tn);
      if (r > best + 1e-12) { best = r; bk = k; }
    }
    if (bk === null) throw PrepError("the recording is too short to contain the training signal");
    return [bk * EB, best];
  }
  function clickOnset(x, centre, noisePeak) {
    var lo = Math.max(0, centre - CLICK_WIN), hi = Math.min(x.length, centre + CLICK_WIN);
    if (hi - lo < 10) return null;
    var p = absMax(x, lo, hi);
    if (p < 4 * noisePeak || p <= 0) return null;
    var thr = Math.max(0.1 * p, 2 * noisePeak), i, first = -1, j = lo;
    for (i = lo; i < hi; i++) { if (first < 0 && Math.abs(x[i]) >= thr) first = i; if (Math.abs(x[i]) > Math.abs(x[j])) j = i; }
    return [first, p, x[j] > 0 ? 1 : -1];
  }
  function humCheck(noise) {
    var n = noise.length, nfft = 1 << 17, re = new Float64Array(nfft), im = new Float64Array(nfft), i;
    for (i = 0; i < n; i++) re[i] = noise[i] * (0.5 - 0.5 * Math.cos(2 * Math.PI * (i + 0.5) / n));
    IRC.fft(re, im, false);
    var nb = nfft / 2 + 1, P = new Float64Array(nb), tot = 0;
    for (i = 0; i < nb; i++) { P[i] = re[i] * re[i] + im[i] * im[i]; var f = i * FS / nfft; if (f >= 20 && f <= 2000) tot += P[i]; }
    var best = [null, 0];
    [50, 60].forEach(function (f0) {
      var s = 0;
      for (var b = 0; b < nb; b++) {
        var f = b * FS / nfft, hit = false;
        for (var k = 1; k <= 8; k++) if (Math.abs(f - k * f0) <= 3) { hit = true; break; }
        if (hit) s += P[b];
      }
      var share = tot > 0 ? s / tot : 0;
      if (share > best[1]) best = [f0, share];
    });
    return best;
  }
  function fx(v, d) { return v.toFixed(d); }
  function g3(v) { return String(Number(v.toPrecision(3))); }

  // ---------------------------------------------------------------- main step
  function prepareChannel(x, fs, label, progress) {
    var warn = [], info = { recorded_rate: fs }, i;
    if (fs !== FS) { if (progress) progress(label + ": converting " + (fs / 1000) + " kHz to 48 kHz"); x = resampleTo(x, fs, FS); info.resampled_to_48k = true; }
    if (x.length < Math.floor((LAST - FIRST) / 2))
      throw PrepError(label + ": the recording is only " + fx(x.length / FS, 0) + " s long; the training signal is " + fx(N / FS, 0) + " s. Record the whole file.");
    if (progress) progress(label + ": finding the training signal");
    var co = coarseOffset(x), d0 = co[0], r = co[1];
    info.match = rnd(r, 3);
    if (r < MIN_ENV_CORR)
      throw PrepError(label + ": couldn't find the training signal in this recording (match " + fx(r, 2) + "). Check that the TONE3000 sweep file is what played, and that this is the right track.");
    var nzw = take(x, d0 + NOISE[0], NOISE[1] - NOISE[0]), noisePeak = absMax(nzw, 0, nzw.length);
    var clicks = BLIPS.map(function (b) { return clickOnset(x, b + d0, noisePeak); });
    if (!clicks[0] && !clicks[1])
      throw PrepError(label + ": found the signal but not its two alignment clicks at 10.5 s and 11.5 s. A noise gate or a very low level can hide them: turn gates off and record again.");
    var ds = []; clicks.forEach(function (c, k) { if (c) ds.push(c[0] - BLIPS[k]); });
    var d = ds[0];
    if (ds.length < 2) { warn.push(label + ": only one of the two alignment clicks was found; alignment is less certain"); info.click_agreement_samples = null; }
    else {
      info.click_agreement_samples = Math.abs(ds[1] - ds[0]);
      if (Math.abs(ds[1] - ds[0]) > 1) warn.push(label + ": the two alignment clicks disagree by " + Math.abs(ds[1] - ds[0]) + " samples; something in the chain smears clicks (a gate, a long room tail)");
      d = Math.min(ds[0], ds[1]);
    }
    var sign = (clicks[0] || clicks[1])[2];
    info.offset_samples = d; info.offset_ms = rnd(d / FS * 1000, 3); info.polarity = sign < 0 ? "inverted" : "normal";
    if (d + LAST >= x.length)
      throw PrepError(label + ": the recording stops " + fx((d + LAST - x.length + 1) / FS, 1) + " s before the training signal ends. Record (or export) a little past the end.");
    if (d + FIRST < 0)
      throw PrepError(label + ": the recording starts " + fx(-(d + FIRST) / FS, 2) + " s after the training signal began. Start recording before playback.");
    if (d < 0 || d + N > x.length) info.padded_samples = Math.max(0, -d) + Math.max(0, d + N - x.length);
    var y = take(x, d, N);

    if (progress) progress(label + ": checking the take");
    var SL = DRIFT_SEG[1] - DRIFT_SEG[0], a = y.subarray(DRIFT_SEG[0], DRIFT_SEG[1]);
    var ext = take(x, d + N - VAL + DRIFT_SEG[0] - DRIFT_MAX, SL + 2 * DRIFT_MAX), na = 0;
    for (i = 0; i < SL; i++) na += a[i] * a[i];
    na = Math.sqrt(na);
    var bestK = 0, bestC = -2;
    for (var k = -DRIFT_MAX; k <= DRIFT_MAX; k++) {
      var o = k + DRIFT_MAX, dot = 0, nb = 0;
      for (i = 0; i < SL; i++) { var bv = ext[o + i]; dot += a[i] * bv; nb += bv * bv; }
      nb = Math.sqrt(nb);
      var c = na > 0 && nb > 0 ? dot / (na * nb) : 0;
      if (c > bestC + 1e-12) { bestC = c; bestK = k; }
    }
    info.drift_samples = bestK; info.start_end_correlation = rnd(bestC, 5);
    if (bestC < 0.9) warn.push(label + ": the closing 9 s don't match the opening 9 s (correlation " + fx(bestC, 2) + "). The amp changed a lot during the take, or playback and recording ran at different speeds. Use one interface for both, with the project at 48 kHz.");
    else if (Math.abs(bestK) > 1) warn.push(label + ": the end of the take has drifted " + bestK + " samples against the start. Playback and recording don't share a clock: use one interface for both (not separate input and output devices).");
    var num = 0, den = 0;
    for (i = 0; i < VAL; i++) { var v1 = y[N - VAL + i], df = y[i] - v1; num += df * df; den += v1 * v1; }
    var esr = den > 0 ? num / den : NaN;
    info.replicate_esr = Number(esr.toPrecision(3));
    if (esr > 0.005) warn.push(label + ": the amp sounded different at the end than at the start (replicate ESR " + g3(esr) + "). Warm the amp up for 20 minutes, keep levels steady, and record again. A model can't be much more accurate than this.");

    var pk = absMax(y, 0, N), clip = 0, flat = 0;
    for (i = 0; i < N; i++) { var av = Math.abs(y[i]); if (av >= 0.999) clip++; if (i > 0 && av > 0.5 && y[i] === y[i - 1]) flat++; }
    info.peak_dbfs = rnd(db(pk), 1); info.clipped_samples = clip;
    if (clip > 0) warn.push(label + ": " + clip + " samples at full scale, so the recording clipped. Lower the interface input gain about 6 dB and record again.");
    else if (flat > 20) warn.push(label + ": the waveform has flat tops (" + flat + " repeated samples near the peak). Something before the interface may be clipping (a pad, a line out, a preamp).");
    else if (pk > Math.pow(10, -3 / 20)) warn.push(label + ": peaks at " + fx(db(pk), 1) + " dBFS, close to clipping. TONE3000 suggests peaks around -8 dBFS: lower the input gain a few dB.");
    else if (pk < Math.pow(10, -24 / 20)) warn.push(label + ": peaks at only " + fx(db(pk), 1) + " dBFS. Raise the input gain so peaks land around -8 dBFS.");

    var nz = y.subarray(NOISE[0], NOISE[1]), ns = 0;
    for (i = 0; i < nz.length; i++) ns += nz[i] * nz[i];
    var nrms = Math.sqrt(ns / nz.length);
    info.noise_dbfs = rnd(db(nrms), 1);
    info.noise_below_peak_db = nrms > 0 ? rnd(db(pk) - db(nrms), 1) : null;
    var hc = nrms > 0 ? humCheck(nz) : [null, 0];
    info.hum_hz = (hc[1] > 0.5 && nrms > Math.pow(10, -90 / 20)) ? hc[0] : null;
    info.hum_share = rnd(hc[1], 2);
    if (nrms > 0 && db(pk) - db(nrms) < 40) warn.push(label + ": the noise floor is only " + fx(db(pk) - db(nrms), 0) + " dB below the peaks. Noise ends up in the model: check cables, gain staging and noisy gear.");
    if (info.hum_hz) warn.push(label + ": the noise is mostly " + hc[0] + " Hz hum. Try the ground lift on the reamp box or load box, and keep audio cables away from power cables.");
    return { y: y, info: info, warn: warn };
  }

  function finish(kind, names, outs, diag, warnings) {
    var first = Math.min.apply(null, names.map(function (n) { return diag[n].offset_samples; }));
    names.forEach(function (n) { diag[n].delay_vs_first_ms = rnd((diag[n].offset_samples - first) / FS * 1000, 3); });
    var notes = [];
    if (kind === "amp") notes.push("Amp-only model: pair it with cab IRs captured with the speaker-terminal reference (reference mode). Sweep-referenced IRs would add the speaker's impedance bump twice.");
    else {
      notes.push("Full-chain model: each mic is its own model. Close mics work best; NAM only models a short stretch of time, so room sound won't carry over well.");
      if (names.length > 1) notes.push("Each file is lined up on its own. To blend two of these models like the real mics, delay each by its delay_vs_first_ms in the DAW.");
    }
    return { kind: kind, names: names, outputs: outs, diagnostics: diag, warnings: warnings, notes: notes };
  }
  function prepare(channels, kind, progress) {   // channels: [{name, x, fs}]
    if (kind !== "amp" && kind !== "full") throw PrepError("kind must be 'amp' or 'full'");
    var outs = {}, diag = {}, warnings = [], names = [];
    channels.forEach(function (ch) {
      var r = prepareChannel(ch.x, ch.fs, ch.name, progress);
      outs[ch.name] = r.y; diag[ch.name] = r.info; warnings = warnings.concat(r.warn); names.push(ch.name);
    });
    return finish(kind, names, outs, diag, warnings);
  }

  // ---------------------------------------------------------------- output
  function wav24(x) {
    var n = x.length, dataLen = n * 3, buf = new ArrayBuffer(44 + dataLen + (dataLen & 1)), v = new DataView(buf), u8 = new Uint8Array(buf);
    function str(o, s) { for (var j = 0; j < s.length; j++) v.setUint8(o + j, s.charCodeAt(j)); }
    str(0, "RIFF"); v.setUint32(4, 36 + dataLen + (dataLen & 1), true); str(8, "WAVE");
    str(12, "fmt "); v.setUint32(16, 16, true); v.setUint16(20, 1, true); v.setUint16(22, 1, true);
    v.setUint32(24, FS, true); v.setUint32(28, FS * 3, true); v.setUint16(32, 3, true); v.setUint16(34, 24, true);
    str(36, "data"); v.setUint32(40, dataLen, true);
    for (var i = 0, o = 44; i < n; i++, o += 3) {
      var q = Math.floor(x[i] * 8388608 + 0.5); if (q > 8388607) q = 8388607; else if (q < -8388608) q = -8388608;
      u8[o] = q & 255; u8[o + 1] = (q >> 8) & 255; u8[o + 2] = (q >> 16) & 255;
    }
    return u8;
  }
  function safeName(s) { return String(s).trim().replace(/[^A-Za-z0-9._-]+/g, "_").replace(/^_+|_+$/g, "") || "capture"; }
  function fileName(capture, name) { return safeName(capture) + "_" + safeName(name) + ".wav"; }
  function uploadNotes(res, capture) {
    var L = ["NAM capture: " + capture, "", "How to train it at TONE3000", "",
      "1. Go to tone3000.com and log in.",
      "2. Choose Create Tone, then Capture.",
      "3. Upload the file(s) in this folder (one model per file).",
      "4. Settings: Model Standard, Best Fit on, 400 max epochs (TONE3000's suggestion).",
      "5. Name each model with the amp, the knob settings and, for mics, the mic and its position.",
      "6. Leave it private unless you mean to share it.",
      "7. When it's done, check the ESR: under 0.01 is great; 0.3 or more means something went wrong.", ""];
    res.notes.forEach(function (n) { L.push("Note: " + n); });
    L.push("");
    res.names.forEach(function (n) { var d = res.diagnostics[n]; L.push(fileName(capture, n) + ": peak " + d.peak_dbfs.toFixed(1) + " dBFS, noise " + d.noise_dbfs.toFixed(1) + " dBFS, replicate ESR " + d.replicate_esr.toFixed(5)); });
    if (res.warnings.length) { L.push("", "Warnings:"); res.warnings.forEach(function (w) { L.push("- " + w); }); }
    return L.join("\n") + "\n";
  }
  function report(res, capture, extra) {
    var r = { capture: capture, kind: res.kind, created: new Date().toISOString(), namprep_version: VERSION, signal: LAYOUT.name,
      diagnostics: res.diagnostics, warnings: res.warnings, notes: res.notes };
    if (extra) for (var k in extra) r[k] = extra[k];
    return JSON.stringify(r, null, 2);
  }

  return { VERSION: VERSION, N: N, FS: FS, prepare: prepare, prepareChannel: prepareChannel, finish: finish, resampleTo: resampleTo, wav24: wav24, safeName: safeName,
    fileName: fileName, uploadNotes: uploadNotes, report: report, envelopeDb: envelopeDb };
})();
if (typeof module !== "undefined") module.exports = NAMPREP;
