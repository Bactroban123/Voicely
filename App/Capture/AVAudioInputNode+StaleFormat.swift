import AVFoundation

extension AVAudioInputNode {
    /// Whether `outputFormat(forBus: 0)` still describes an input device that
    /// has since been replaced.
    ///
    /// After the input device changes (AirPods connecting, the iPhone mic
    /// taking over), an engine that already touched `inputNode` keeps
    /// reporting the previous device's sample rate from `outputFormat` —
    /// `prepare()` does not refresh it — while `inputFormat` tracks the
    /// hardware. `installTap` checks the tap format against the hardware rate
    /// and raises an Objective-C exception on a mismatch, which Swift cannot
    /// catch, so the app aborts. That is what killed Voicely on 2026-09-30.
    /// A fresh `AVAudioEngine` reads the current device.
    ///
    /// Only the sample rate is compared because that is exactly what
    /// `installTap` validates.
    var hasStaleOutputFormat: Bool {
        outputFormat(forBus: 0).sampleRate != inputFormat(forBus: 0).sampleRate
    }
}
