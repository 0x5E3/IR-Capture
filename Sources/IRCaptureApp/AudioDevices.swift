#if os(macOS)
import CoreAudio
import AudioToolbox
import Foundation

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
        if st != noErr { throw AppError("The interface wouldn't switch to \(rate) Hz (CoreAudio error \(st)).") }
        for _ in 0..<40 {
            if abs(nominalRate(id) - Double(rate)) < 0.5 { Thread.sleep(forTimeInterval: 0.3); return }
            Thread.sleep(forTimeInterval: 0.1)
        }
        throw AppError("The interface didn't switch to \(rate) Hz. Set it in Audio MIDI Setup and try again.")
    }
}

struct AppError: Error, LocalizedError {
    let message: String
    init(_ m: String) { message = m }
    var errorDescription: String? { message }
}
#endif
