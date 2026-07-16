import Foundation

/// Captures hard failures so the Diagnostics tab can say what happened.
///
/// - Fatal signals (Swift runtime traps arrive as signals, not exceptions)
///   write a pre-composed line to ~/Library/Logs/Voicely/last-crash.log via a
///   pre-opened descriptor — the handler itself only calls `write(2)`, which
///   is async-signal-safe — then re-raise so macOS's ReportCrash still
///   produces the authoritative .ips report.
/// - Uncaught NSExceptions run in a normal (non-signal) context, so their
///   handler may format a real message before the runtime aborts.
/// - A session flag file distinguishes clean exits from crashes/force-kills.
///
/// Deliberately no MetricKit: `MXMetricPayload` is unavailable on macOS in
/// SDKs before 26, so subscribing pinned the whole app to a bleeding-edge
/// toolchain. It only ever produced a corroborating log line — delivery is
/// unreliable and roughly daily-batched for non-App-Store apps — so it cost
/// far more than it paid. The signal/exception handlers and the tap-latency
/// canary carry the real diagnostics.
final class CrashReporter: NSObject {
    static let shared = CrashReporter()

    /// nil until `install()` runs. False means the previous session ended in a
    /// crash OR a force-kill — the flag file can't tell those apart, so the UI
    /// wording is "didn't exit cleanly".
    private(set) var lastRunEndedCleanly: Bool?
    /// Contents of last-crash.log from the previous session, if any.
    private(set) var lastCrashDetail: String?

    private static let handledSignals: [Int32] = [SIGABRT, SIGILL, SIGSEGV, SIGFPE, SIGBUS, SIGTRAP]
    private static let signalNames: [Int32: String] = [
        SIGABRT: "SIGABRT", SIGILL: "SIGILL", SIGSEGV: "SIGSEGV",
        SIGFPE: "SIGFPE", SIGBUS: "SIGBUS", SIGTRAP: "SIGTRAP",
    ]

    // Shared with the signal handler: plain C storage only, prepared before
    // any crash can happen, read-only afterwards.
    private static var crashFD: Int32 = -1
    private static let messageSlots = 64
    private static let messagePointers =
        UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>.allocate(capacity: messageSlots)
    private static let messageLengths = UnsafeMutablePointer<Int>.allocate(capacity: messageSlots)

    private var directory: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/Voicely", isDirectory: true)
    }
    private var crashLogURL: URL { directory.appendingPathComponent("last-crash.log") }
    private var sessionFlagURL: URL { directory.appendingPathComponent("session.active") }

    /// Call as the very first thing at app launch.
    func install() {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)

        // Did the previous session exit cleanly? (Flag present = it didn't.)
        lastRunEndedCleanly = !fm.fileExists(atPath: sessionFlagURL.path)
        if let detail = try? String(contentsOf: crashLogURL, encoding: .utf8),
           !detail.isEmpty {
            lastCrashDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        fm.createFile(atPath: sessionFlagURL.path, contents: nil)

        // Fresh crash log for this session; pre-open the descriptor the
        // signal handler will write through.
        try? fm.removeItem(at: crashLogURL)
        Self.crashFD = open(crashLogURL.path, O_WRONLY | O_CREAT | O_APPEND, 0o644)

        // Pre-compose one message per handled signal so the handler never allocates.
        Self.messagePointers.initialize(repeating: nil, count: Self.messageSlots)
        Self.messageLengths.initialize(repeating: 0, count: Self.messageSlots)
        for sig in Self.handledSignals where Int(sig) < Self.messageSlots {
            let text = "Voicely fatal signal: \(Self.signalNames[sig] ?? "\(sig)")\n"
            let bytes = Array(text.utf8)
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bytes.count)
            buffer.update(from: bytes, count: bytes.count)
            Self.messagePointers[Int(sig)] = buffer
            Self.messageLengths[Int(sig)] = bytes.count
            // Known limitation: plain signal() (no sigaltstack/SA_ONSTACK) means a
            // stack-overflow SIGSEGV can't run this handler. The session flag still
            // reports the unclean exit and ReportCrash still writes the .ips.
            signal(sig, crashSignalHandler)
        }

        NSSetUncaughtExceptionHandler(uncaughtExceptionHandler)
    }

    /// Call from applicationWillTerminate so a normal quit isn't reported as a crash.
    func markCleanExit() {
        try? FileManager.default.removeItem(at: sessionFlagURL)
    }

    // MARK: - Handler plumbing (static: C function pointers can't capture)

    fileprivate static func writeCrashLine(signal sig: Int32) {
        guard crashFD >= 0, Int(sig) < messageSlots, let ptr = messagePointers[Int(sig)] else { return }
        _ = write(crashFD, ptr, messageLengths[Int(sig)])
    }

    fileprivate static func writeCrashText(_ text: String) {
        guard crashFD >= 0 else { return }
        let bytes = Array(text.utf8)
        _ = bytes.withUnsafeBufferPointer { write(crashFD, $0.baseAddress, $0.count) }
        fsync(crashFD)
    }

}

/// Async-signal-safe: only `write(2)`, `signal(2)`, `raise(2)` on pre-computed data.
private func crashSignalHandler(_ sig: Int32) {
    CrashReporter.writeCrashLine(signal: sig)
    signal(sig, SIG_DFL)
    raise(sig)
}

/// Runs in a normal context (not a signal handler) — formatting is fine here.
private func uncaughtExceptionHandler(_ exception: NSException) {
    let symbols = exception.callStackSymbols.prefix(12).joined(separator: "\n")
    CrashReporter.writeCrashText("""
    Voicely uncaught exception: \(exception.name.rawValue)
    reason: \(exception.reason ?? "—")
    \(symbols)
    """)
}
