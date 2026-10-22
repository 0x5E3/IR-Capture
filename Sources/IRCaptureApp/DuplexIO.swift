#if os(macOS)
import AudioToolbox
import CoreAudio
import Foundation
import IRCaptureCore

/// Plays a signal out of one output channel and records chosen inputs, on ONE interface
/// (so input and output share a clock). Uses a single AUHAL unit with input and output enabled.
/// Start latency doesn't matter: the processing finds the sweeps in the recording itself.
final class DuplexIO {
    private var unit: AudioUnit?
    private let fs: Int
    private let outChannels: Int
    private let inChannels: Int
    private let outChannel: Int            // 0-based
    private let inputs: [Int]              // 0-based device input channels to keep
    private let play: UnsafeMutablePointer<Float>
    private let playCount: Int
    private var playPos = 0
    private let rec: [UnsafeMutablePointer<Float>]
    let recCapacity: Int
    private var recPosStorage = 0
    private let scratchFrames = 16384
    private let scratch: UnsafeMutableAudioBufferListPointer
    private let scratchData: [UnsafeMutablePointer<Float>]
    private var renderError: OSStatus = noErr
    // Dropout detection (P0.10): each input callback's sample time should follow the last one exactly.
    private var lastSampleTime: Float64 = -1
    private var lastFrames = 0
    private static let maxGaps = 64
    private let gapAt = UnsafeMutablePointer<Int>.allocate(capacity: DuplexIO.maxGaps)     // recorded frame where it happened
    private let gapLen = UnsafeMutablePointer<Int>.allocate(capacity: DuplexIO.maxGaps)    // frames missing (negative: repeated)
    private var gapCount = 0

    /// Frames recorded so far (read from the main thread for progress only).
    var recorded: Int { recPosStorage }
    var finished: Bool { recPosStorage >= recCapacity }
    var error: OSStatus { renderError }

    init(device: AudioDevice, fs: Int, outChannel: Int, inputs: [Int], signal: [Float], extraSeconds: Double = 1.0) {
        self.fs = fs
        outChannels = device.outputChannels
        inChannels = device.inputChannels
        self.outChannel = outChannel
        self.inputs = inputs
        playCount = signal.count
        let buf = UnsafeMutablePointer<Float>.allocate(capacity: max(signal.count, 1))
        signal.withUnsafeBufferPointer { buf.initialize(from: $0.baseAddress!, count: signal.count) }
        play = buf
        recCapacity = signal.count + Int(extraSeconds * Double(fs))
        rec = inputs.map { _ in
            let p = UnsafeMutablePointer<Float>.allocate(capacity: signal.count + Int(extraSeconds * Double(fs)))
            p.initialize(repeating: 0, count: signal.count + Int(extraSeconds * Double(fs)))
            return p
        }
        scratch = AudioBufferList.allocate(maximumBuffers: max(device.inputChannels, 1))
        scratchData = (0..<max(device.inputChannels, 1)).map { _ in
            let p = UnsafeMutablePointer<Float>.allocate(capacity: 16384); p.initialize(repeating: 0, count: 16384); return p
        }
        for i in 0..<scratch.count {
            scratch[i] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(scratchFrames * 4), mData: UnsafeMutableRawPointer(scratchData[i]))
        }
    }

    deinit {
        stop()
        play.deallocate()
        rec.forEach { $0.deallocate() }
        scratchData.forEach { $0.deallocate() }
        free(scratch.unsafeMutablePointer)
        gapAt.deallocate()
        gapLen.deallocate()
    }

    /// Gaps in the input timestamps so far, as (seconds into the recording, frames missing).
    var gaps: [(seconds: Double, frames: Int)] {
        (0..<min(gapCount, DuplexIO.maxGaps)).map { (Double(gapAt[$0]) / Double(fs), gapLen[$0]) }
    }

    private func check(_ st: OSStatus, _ what: String) throws {
        if st != noErr {
            Log.write("CoreAudio error \(st) trying to \(what)")
            throw AppError("Couldn't \(what). Check that the interface is connected and not in use by another app that holds it exclusively, then try again. (CoreAudio error \(st))")
        }
    }

    func start(deviceID: AudioDeviceID) throws {
        var desc = AudioComponentDescription(componentType: kAudioUnitType_Output, componentSubType: kAudioUnitSubType_HALOutput,
                                             componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0)
        guard let comp = AudioComponentFindNext(nil, &desc) else { throw AppError("CoreAudio's HAL unit is missing.") }
        var u: AudioUnit?
        try check(AudioComponentInstanceNew(comp, &u), "open the audio unit")
        guard let unit = u else { throw AppError("Couldn't open the audio unit.") }
        self.unit = unit

        var one: UInt32 = 1
        let u32 = UInt32(MemoryLayout<UInt32>.size)
        try check(AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &one, u32), "enable recording")
        try check(AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &one, u32), "enable playback")
        var dev = deviceID
        try check(AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &dev,
                                       UInt32(MemoryLayout<AudioDeviceID>.size)), "select the interface")

        func format(_ ch: Int) -> AudioStreamBasicDescription {
            AudioStreamBasicDescription(mSampleRate: Float64(fs), mFormatID: kAudioFormatLinearPCM,
                                        mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved,
                                        mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
                                        mChannelsPerFrame: UInt32(ch), mBitsPerChannel: 32, mReserved: 0)
        }
        let asbdSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var outFmt = format(outChannels), inFmt = format(inChannels)
        try check(AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &outFmt, asbdSize), "set the playback format")
        try check(AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &inFmt, asbdSize), "set the recording format")
        var maxFrames = UInt32(scratchFrames)
        AudioUnitSetProperty(unit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &maxFrames, u32)

        let me = Unmanaged.passUnretained(self).toOpaque()
        var inCB = AURenderCallbackStruct(inputProc: { refCon, flags, ts, _, frames, _ in
            Unmanaged<DuplexIO>.fromOpaque(refCon).takeUnretainedValue().didInput(flags, ts, frames)
        }, inputProcRefCon: me)
        try check(AudioUnitSetProperty(unit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0, &inCB,
                                       UInt32(MemoryLayout<AURenderCallbackStruct>.size)), "set the recording callback")
        var outCB = AURenderCallbackStruct(inputProc: { refCon, _, _, _, frames, ioData in
            Unmanaged<DuplexIO>.fromOpaque(refCon).takeUnretainedValue().render(frames, ioData)
            return noErr
        }, inputProcRefCon: me)
        try check(AudioUnitSetProperty(unit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &outCB,
                                       UInt32(MemoryLayout<AURenderCallbackStruct>.size)), "set the playback callback")
        try check(AudioUnitInitialize(unit), "start the interface")
        try check(AudioOutputUnitStart(unit), "start the interface")
    }

    func stop() {
        guard let unit else { return }
        AudioOutputUnitStop(unit)
        AudioUnitUninitialize(unit)
        AudioComponentInstanceDispose(unit)
        self.unit = nil
    }

    // Real-time thread: no allocation, no locks.
    private func didInput(_ flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>, _ ts: UnsafePointer<AudioTimeStamp>, _ frames: UInt32) -> OSStatus {
        guard let unit else { return noErr }
        let n = Int(frames)
        guard n <= scratchFrames else { return noErr }
        for i in 0..<scratch.count {
            scratch[i].mDataByteSize = UInt32(n * 4)
            scratch[i].mData = UnsafeMutableRawPointer(scratchData[i])
        }
        let st = AudioUnitRender(unit, flags, ts, 1, frames, scratch.unsafeMutablePointer)
        if st != noErr { renderError = st; return st }
        let pos = recPosStorage
        let t = ts.pointee
        if t.mFlags.contains(.sampleTimeValid) && pos < recCapacity {
            if lastSampleTime >= 0 {
                let gap = Int((t.mSampleTime - (lastSampleTime + Float64(lastFrames))).rounded())
                if gap != 0 {
                    if gapCount < DuplexIO.maxGaps { gapAt[gapCount] = pos; gapLen[gapCount] = gap }
                    gapCount += 1
                }
            }
            lastSampleTime = t.mSampleTime
            lastFrames = n
        }
        let m = min(n, recCapacity - pos)
        if m > 0 {
            for (k, ch) in inputs.enumerated() where ch < scratchData.count {
                (rec[k] + pos).update(from: scratchData[ch], count: m)
            }
            recPosStorage = pos + m
        }
        return noErr
    }

    private func render(_ frames: UInt32, _ ioData: UnsafeMutablePointer<AudioBufferList>?) {
        guard let ioData else { return }
        let n = Int(frames)
        let abl = UnsafeMutableAudioBufferListPointer(ioData)
        for (i, buf) in abl.enumerated() {
            guard let p = buf.mData?.assumingMemoryBound(to: Float.self) else { continue }
            let count = min(n, Int(buf.mDataByteSize) / 4)
            p.update(repeating: 0, count: count)
            if i == outChannel {
                let avail = max(0, min(count, playCount - playPos))
                if avail > 0 { p.update(from: play + playPos, count: avail) }
            }
        }
        playPos += n
    }

    /// Peak level of each input over frames [from, to), for the live meters (main thread, read only).
    func peaks(from: Int, to: Int) -> [Float] {
        let a = max(0, from), b = min(to, recCapacity)
        return rec.map { p in
            var pk: Float = 0
            if b > a { for i in a..<b { let v = abs(p[i]); if v > pk { pk = v } } }
            return pk
        }
    }

    /// Copies out what was recorded, one array per requested input.
    func recording() -> [[Float]] {
        let n = min(recPosStorage, recCapacity)
        return rec.map { Array(UnsafeBufferPointer(start: $0, count: n)) }
    }

    /// What happened during one pass, for report.json and the dropout warning.
    struct Report {
        var gaps: [(seconds: Double, frames: Int)]
        var overloads: Int
        var bufferFrames: Int
        var dropoutWarning: String? {
            guard !gaps.isEmpty || overloads > 0 else { return nil }
            let at = gaps.first.map { g -> String in let s = max(0, Int(g.seconds)); return " at \(s / 60):\(String(format: "%02d", s % 60))" } ?? ""
            return "Audio dropped out\(at) while recording (\(max(gaps.count, overloads)) time\(max(gaps.count, overloads) == 1 ? "" : "s")). Record again with other apps closed. If it keeps happening, raise the interface's buffer size in its control panel or in Audio MIDI Setup."
        }
        var json: JSON {
            .object([("buffer_frames", .int(bufferFrames)), ("overloads", .int(overloads)),
                     ("gaps", .array(gaps.map { .object([("at_s", .number((($0.seconds * 1000).rounded()) / 1000)), ("frames", .int($0.frames))]) }))])
        }
    }

    /// Plays and records until the signal plus the extra time has been captured.
    static func run(device: AudioDevice, fs: Int, outChannel: Int, inputs: [Int], signal: [Float],
                    extraSeconds: Double = 1.0, cancelled: @escaping () -> Bool = { false },
                    progress: @escaping (Double) -> Void = { _ in },
                    meter: (([Float]) -> Void)? = nil,
                    report: ((Report) -> Void)? = nil) async throws -> [[Float]] {
        let io = DuplexIO(device: device, fs: fs, outChannel: outChannel, inputs: inputs, signal: signal, extraSeconds: extraSeconds)
        // The HAL also reports processor overloads on the device; count them while this pass runs.
        let overloads = OverloadCounter()
        var oa = CoreAudioHelper.addr(kAudioDeviceProcessorOverload)
        let listener: AudioObjectPropertyListenerBlock = { _, _ in overloads.bump() }
        let listening = AudioObjectAddPropertyListenerBlock(device.id, &oa, overloads.queue, listener) == noErr
        defer { if listening { AudioObjectRemovePropertyListenerBlock(device.id, &oa, overloads.queue, listener) } }
        try io.start(deviceID: device.id)
        defer { io.stop() }
        let started = Date()
        let expected = Double(io.recCapacity) / Double(fs)
        var metered = 0
        while !io.finished {
            try await Task.sleep(nanoseconds: 50_000_000)
            if cancelled() { throw CancellationError() }
            if io.error != noErr { throw AppError("Recording stopped because the interface stopped answering. Check its cable and power, then try again. (CoreAudio error \(io.error))") }
            let elapsed = Date().timeIntervalSince(started)
            if elapsed > expected + 5 && io.recorded == 0 {
                throw AppError("No audio is arriving from the interface. Check that it's connected and that IR Capture is allowed to use the microphone (System Settings › Privacy & Security › Microphone).")
            }
            if elapsed > expected * 1.5 + 10 { throw AppError("The interface stopped delivering audio part way through. Check its cable and power, close other audio apps, and try again.") }
            progress(Double(io.recorded) / Double(io.recCapacity))
            if let meter {
                let pos = io.recorded
                if pos > metered { meter(io.peaks(from: metered, to: pos)); metered = pos }
            }
        }
        io.stop()
        let r = Report(gaps: io.gaps, overloads: overloads.value, bufferFrames: CoreAudioHelper.bufferFrames(device.id))
        if !r.gaps.isEmpty || r.overloads > 0 { Log.write("dropouts: \(r.gaps.count) gaps \(r.gaps.prefix(5)), \(r.overloads) overloads, buffer \(r.bufferFrames)") }
        report?(r)
        return io.recording()
    }
}

/// Counts kAudioDeviceProcessorOverload notifications on its own queue.
final class OverloadCounter {
    let queue = DispatchQueue(label: "ircapture.overloads")
    private var n = 0
    func bump() { n += 1 }                       // called on `queue`
    var value: Int { queue.sync { n } }
}
#endif
