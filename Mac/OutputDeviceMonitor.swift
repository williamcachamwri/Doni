import CoreAudio
import Foundation

/// The desktop's counterpart to the phone's `.oldDeviceUnavailable`.
///
/// macOS has no audio session to be interrupted, but a song playing into a DAC that gets unplugged, or
/// AirPods taken off the ear, is the same silence the phone stops for — and nothing on the Mac pauses by
/// itself. The phone learns this from `AVAudioSession.routeChangeNotification`; there is no notification
/// here, so the question is asked of Core Audio instead.
///
/// Asked on the tick rather than listened for: the ticker already runs four times a second while sound is
/// coming, two property reads cost microseconds, and a `AudioObjectAddPropertyListenerBlock` callback has
/// to be made `@Sendable` in a way Swift 6 will not accept from a `@MainActor` object without lying about
/// it. The answer is the same fact either way — the device the song started on no longer exists.
@MainActor
enum OutputDeviceMonitor {
    /// Whether `device` is still one of the machine's audio devices.
    static func isPresent(_ device: AudioDeviceID) -> Bool {
        devices().contains(device)
    }

    /// The device sound is going to right now.
    static func current() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &address, 0, nil, &size, &id) == noErr, id != 0 else {
            return nil
        }
        return id
    }

    private static func devices() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(0)
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject),
                                             &address, 0, nil, &size) == noErr, size > 0 else {
            return []
        }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }
}
