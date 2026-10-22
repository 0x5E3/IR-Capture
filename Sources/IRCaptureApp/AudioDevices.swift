#if os(macOS)
import CoreAudio
import AudioToolbox
import Foundation
import IRCaptureCore

/// An audio interface as CoreAudio sees it.
struct AudioDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let inputChannels: Int
    let outputChannels: Int
    let sampleRates: [Int]
    var isDuplex: Bool { inputChannels > 0 && outputChannels > 0 }
}

enum CoreAudioHelper {
    static let captureRates = [44100, 48000, 88200, 96000]

    static func addr(_ sel: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func devices() -> [AudioDevice] {
        var a = addr(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        let sys = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(sys, &a, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(sys, &a, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.map { id in
            AudioDevice(id: id, uid: string(id, kAudioDevicePropertyDeviceUID) ?? "\(id)",
                        name: string(id, kAudioObjectPropertyName) ?? "Device \(id)",
                        inputChannels: channels(id, input: true), outputChannels: channels(id, input: false),
                        sampleRates: rates(id))
        }
    }

    static func string(_ id: AudioObjectID, _ sel: AudioObjectPropertySelector) -> String? {
        var a = addr(sel)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let st = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(id, &a, 0, nil, &size, $0) }
        guard st == noErr, let v = value else { return nil }
        return v.takeRetainedValue() as String
    }

    static func channels(_ id: AudioDeviceID, input: Bool) -> Int {
        var a = addr(kAudioDevicePropertyStreamConfiguration, input ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &a, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 16)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, raw) == noErr else { return 0 }
        let abl = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return abl.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    static func rates(_ id: AudioDeviceID) -> [Int] {
        var a = addr(kAudioDevicePropertyAvailableNominalSampleRates)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &a, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ranges = [AudioValueRange](repeating: AudioValueRange(), count: Int(size) / MemoryLayout<AudioValueRange>.size)
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, &ranges) == noErr else { return [] }
        return captureRates.filter { r in ranges.contains { Double(r) >= $0.mMinimum - 0.5 && Double(r) <= $0.mMaximum + 0.5 } }
    }

    static func nominalRate(_ id: AudioDeviceID) -> Double {
        var a = addr(kAudioDevicePropertyNominalSampleRate)
        var r: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        AudioObjectGetPropertyData(id, &a, 0, nil, &size, &r)
        return r
    }

    /// Sets the interface's sample rate and waits for it to take effect.
    static func setNominalRate(_ id: AudioDeviceID, _ rate: Int) throws {
        if abs(nominalRate(id) - Double(rate)) < 0.5 { return }
        var a = addr(kAudioDevicePropertyNominalSampleRate)
        var r = Float64(rate)
        let st = AudioObjectSetPropertyData(id, &a, 0, nil, UInt32(MemoryLayout<Float64>.size), &r)
        let khz = "\(rateTag(rate).dropLast()) kHz"
        if st != noErr {
            Log.write("rate switch to \(rate) failed, CoreAudio error \(st)")
            throw AppError("Could not switch the interface to \(khz). Set it to \(khz) in Audio MIDI Setup, then try again. (CoreAudio error \(st))")
        }
        for _ in 0..<40 {
            if abs(nominalRate(id) - Double(rate)) < 0.5 { Thread.sleep(forTimeInterval: 0.3); Log.write("interface now at \(rate) Hz"); return }
            Thread.sleep(forTimeInterval: 0.1)
        }
        Log.write("rate switch to \(rate) timed out; still \(nominalRate(id))")
        throw AppError("The interface sample rate is not \(khz). Set it to \(khz) in Audio MIDI Setup, then try again.")
    }

    /// Puts the interface back to the rate it had before (so the user's DAW session isn't disturbed), and
    /// waits up to 4 s for the switch to take effect, so the next job starts from a known rate. Best effort:
    /// never throws. Blocks, so call it off the main thread.
    static func restoreRate(_ id: AudioDeviceID, _ rate: Double) {
        guard rate > 0, abs(nominalRate(id) - rate) >= 0.5 else { return }
        var a = addr(kAudioDevicePropertyNominalSampleRate)
        var r = Float64(rate)
        let st = AudioObjectSetPropertyData(id, &a, 0, nil, UInt32(MemoryLayout<Float64>.size), &r)
        guard st == noErr else { Log.write("restoring interface rate to \(Int(rate)) Hz failed, CoreAudio error \(st)"); return }
        for _ in 0..<40 {
            if abs(nominalRate(id) - rate) < 0.5 { Thread.sleep(forTimeInterval: 0.3); Log.write("restored interface rate to \(Int(rate)) Hz"); return }
            Thread.sleep(forTimeInterval: 0.1)
        }
        Log.write("restoring interface rate to \(Int(rate)) Hz timed out; it reports \(nominalRate(id))")
    }

    /// The interface's current I/O buffer size in frames (0 if unknown).
    static func bufferFrames(_ id: AudioDeviceID) -> Int {
        var a = addr(kAudioDevicePropertyBufferFrameSize)
        var v: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(id, &a, 0, nil, &size, &v) == noErr ? Int(v) : 0
    }

    /// The best capture rate: the highest the interface supports, up to 96 kHz.
    static func bestRate(_ d: AudioDevice) -> Int { d.sampleRates.filter { $0 <= 96000 }.max() ?? 48000 }

    /// Calls `changed` on the main queue whenever an interface is plugged in or removed.
    static func watchDevices(_ changed: @escaping () -> Void) {
        var a = addr(kAudioHardwarePropertyDevices)
        let st = AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &a, DispatchQueue.main) { _, _ in changed() }
        if st != noErr { Log.write("couldn't watch for interface changes, CoreAudio error \(st)") }
    }

    /// Opens Audio MIDI Setup, where interface sample rates and aggregate devices are set.
    static func openAudioMIDISetup() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-b", "com.apple.audio.AudioMIDISetup"]
        try? p.run()
    }
}

struct AppError: Error, LocalizedError {
    let message: String
    init(_ m: String) { message = m }
    var errorDescription: String? { message }
}
#endif
