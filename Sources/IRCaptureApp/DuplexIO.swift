#if os(macOS)
import AudioToolbox
import CoreAudio
import Foundation

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
        play = .allocate(capacity: max(signal.count, 1))
        signal.withUnsafeBufferPointer { play.initialize(from: $0.baseAddress!, count: signal.count) }
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
    }

    private func check(_ st: OSStatus, _ what: String) throws {
        if st != noErr { throw AppError("Couldn't \(what) (CoreAudio error \(st)).") }
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

    /// Copies out what was recorded, one array per requested input.
    func recording() -> [[Float]] {
        let n = min(recPosStorage, recCapacity)
        return rec.map { Array(UnsafeBufferPointer(start: $0, count: n)) }
    }

    /// Plays and records until the signal plus the extra time has been captured.
    static func run(device: AudioDevice, fs: Int, outChannel: Int, inputs: [Int], signal: [Float],
                    extraSeconds: Double = 1.0, cancelled: @escaping () -> Bool = { false },
                    progress: @escaping (Double) -> Void = { _ in }) async throws -> [[Float]] {
        let io = DuplexIO(device: device, fs: fs, outChannel: outChannel, inputs: inputs, signal: signal, extraSeconds: extraSeconds)
        try io.start(deviceID: device.id)
        defer { io.stop() }
        let started = Date()
        let expected = Double(io.recCapacity) / Double(fs)
        while !io.finished {
            try await Task.sleep(nanoseconds: 50_000_000)
            if cancelled() { throw CancellationError() }
            if io.error != noErr { throw AppError("Recording failed (CoreAudio error \(io.error)). Check that the interface is connected.") }
            let elapsed = Date().timeIntervalSince(started)
            if elapsed > expected + 5 && io.recorded == 0 {
                throw AppError("No audio is arriving from the interface. Check that it's connected and that IR Capture is allowed to use the microphone (System Settings › Privacy & Security › Microphone).")
            }
            if elapsed > expected * 1.5 + 10 { throw AppError("The interface stopped delivering audio part way through.") }
            progress(Double(io.recorded) / Double(io.recCapacity))
        }
        io.stop()
        return io.recording()
    }
}
#endif
