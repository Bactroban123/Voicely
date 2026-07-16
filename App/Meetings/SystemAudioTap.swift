import AVFoundation
import CoreAudio
import Foundation

/// Captures what the Mac is *playing* — i.e. everyone else on the call — via a
/// Core Audio process tap feeding a private aggregate device.
///
/// Why this and not ScreenCaptureKit: SCK routes audio capture through the
/// Screen Recording permission, so macOS would tell the user Voicely "wants to
/// record this computer's screen" — for an app whose entire pitch is that it
/// doesn't watch you. A process tap is audio-only, needs no paid signing
/// (verified: a fully unsigned build captures real audio), and taps the HAL
/// mixdown, so it works regardless of which app is playing or which output
/// device is active (built-in, AirPods, external).
///
/// Mic is deliberately NOT captured here — no tap or SCK can. `MeetingRecorder`
/// runs a separate AVAudioEngine for that. Keeping them apart is what gives
/// "Me" vs "Them" attribution for free, with no diarization.
@available(macOS 14.2, *)
final class SystemAudioTap {
    enum TapError: Error {
        /// Tap creation refused — on macOS 14.4+ this is where a missing
        /// audio-capture TCC grant surfaces.
        case tapRefused(OSStatus)
        case aggregateDeviceFailed(OSStatus)
        case ioProcFailed(OSStatus)
        case tapFormatUnavailable
    }

    /// Called on Core Audio's real-time IO thread. Do no allocation, no locks,
    /// and no I/O of consequence here — hand the samples off and return.
    typealias SampleHandler = (UnsafePointer<Float>, Int) -> Void

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var running = false

    /// The tap's native format. The HAL mixdown is 48 kHz; the ASR engines want
    /// 16 kHz, so callers must resample (`MeetingRecorder` does).
    private(set) var format: AVAudioFormat?

    /// Begins capture. `onSamples` fires on the audio IO thread with interleaved
    /// Float32 in `format`.
    func start(onSamples: @escaping SampleHandler) throws {
        // Exclude nothing: Voicely plays no audio, so there's no risk of taping
        // ourselves. (Note the exclusion list takes Core Audio *process object*
        // IDs, not PIDs — if Voicely ever gains a start/stop chime, translate
        // via kAudioHardwarePropertyTranslatePIDToProcessObject first.)
        let description = CATapDescription(monoGlobalTapButExcludeProcesses: [])
        description.name = "Voicely meeting capture"
        description.isPrivate = true            // invisible to other apps and Sound settings
        description.muteBehavior = .unmuted     // never mute what the user is hearing

        let tapStatus = AudioHardwareCreateProcessTap(description, &tapID)
        guard tapStatus == noErr, tapID != kAudioObjectUnknown else {
            throw TapError.tapRefused(tapStatus)
        }

        guard let uid = Self.stringProperty(tapID, kAudioTapPropertyUID),
              var asbd = Self.tapFormat(tapID) else {
            destroyTap()
            throw TapError.tapFormatUnavailable
        }
        format = withUnsafePointer(to: &asbd) { AVAudioFormat(streamDescription: $0) }

        // A private aggregate device wrapping only the tap: no sub-devices, so
        // it neither claims hardware nor appears as a selectable input.
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Voicely Meeting Capture",
            kAudioAggregateDeviceUIDKey: "com.voicely.meeting.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[String: Any]](),
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: uid,
                kAudioSubTapDriftCompensationKey: true,
            ]],
        ]
        let aggregateStatus = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID)
        guard aggregateStatus == noErr, aggregateID != kAudioObjectUnknown else {
            destroyTap()
            throw TapError.aggregateDeviceFailed(aggregateStatus)
        }

        let ioStatus = AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, nil) { _, inputData, _, _, _ in
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
            for buffer in buffers {
                guard let data = buffer.mData else { continue }
                let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                guard count > 0 else { continue }
                onSamples(data.assumingMemoryBound(to: Float.self), count)
            }
        }
        guard ioStatus == noErr, let ioProcID else {
            destroyAggregate(); destroyTap()
            throw TapError.ioProcFailed(ioStatus)
        }

        let startStatus = AudioDeviceStart(aggregateID, ioProcID)
        guard startStatus == noErr else {
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
            self.ioProcID = nil
            destroyAggregate(); destroyTap()
            throw TapError.ioProcFailed(startStatus)
        }
        running = true
        VoicelyLog.meeting.info("system audio tap started (\(Int(format?.sampleRate ?? 0))Hz)")
    }

    /// Tears everything down in reverse order. Safe to call when not running.
    func stop() {
        if running, let ioProcID {
            AudioDeviceStop(aggregateID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
        }
        ioProcID = nil
        running = false
        destroyAggregate()
        destroyTap()
    }

    deinit { stop() }

    // MARK: - Teardown helpers (idempotent)

    private func destroyAggregate() {
        guard aggregateID != kAudioObjectUnknown else { return }
        AudioHardwareDestroyAggregateDevice(aggregateID)
        aggregateID = kAudioObjectUnknown
    }

    private func destroyTap() {
        guard tapID != kAudioObjectUnknown else { return }
        AudioHardwareDestroyProcessTap(tapID)
        tapID = kAudioObjectUnknown
    }

    // MARK: - Property reads

    private static func stringProperty(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<CFString?>.size)
        var value: Unmanaged<CFString>?
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0)
        }
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    private static func tapFormat(_ tap: AudioObjectID) -> AudioStreamBasicDescription? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &asbd)
        return status == noErr ? asbd : nil
    }
}
