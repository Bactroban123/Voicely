import Foundation

/// Disk-backed mirror of the unified log. Third-party apps can only read back
/// the *current* process's unified-log entries (OSLogStore is current-process
/// scope without a private entitlement), so a rotating file under
/// ~/Library/Logs/Voicely is the only durable, user-exportable record that
/// survives a crash or relaunch.
///
/// All writes hop to a background serial queue: `append` must return
/// immediately even when called from the CGEventTap callback path.
final class FileLogMirror {
    static let shared = FileLogMirror()

    private let queue = DispatchQueue(label: "com.voicely.logging", qos: .utility)
    private let maxFileBytes: UInt64 = 5 * 1024 * 1024
    private let ringCapacity = 200

    private let directory: URL
    private let fileURL: URL
    private let rotatedURL: URL
    private var handle: FileHandle?
    private var ring: [String] = []
    private let stamp: DateFormatter

    private init() {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        directory = library.appendingPathComponent("Logs/Voicely", isDirectory: true)
        fileURL = directory.appendingPathComponent("voicely.log")
        rotatedURL = directory.appendingPathComponent("voicely.1.log")
        stamp = DateFormatter()
        stamp.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        stamp.locale = Locale(identifier: "en_US_POSIX")
        queue.async { [self] in openHandle() }
    }

    /// Non-blocking; safe to call from any thread, including the tap callback chain.
    func append(category: String, level: String, message: String) {
        let when = Date() // stamp at call time, not when the queue drains
        queue.async { [self] in
            let line = "\(stamp.string(from: when)) [\(level)] \(category): \(message)"
            ring.append(line)
            if ring.count > ringCapacity { ring.removeFirst(ring.count - ringCapacity) }
            guard let handle, let data = (line + "\n").data(using: .utf8) else { return }
            do {
                try handle.write(contentsOf: data)
                rotateIfNeeded()
            } catch {
                self.handle = nil // logging must never take the app down
            }
        }
    }

    /// Most recent formatted lines, for the Diagnostics tab (instant, no disk read).
    func recentLines(_ count: Int) -> [String] {
        queue.sync { Array(ring.suffix(count)) }
    }

    // MARK: - Queue-only internals

    private func openHandle() {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                FileManager.default.createFile(atPath: fileURL.path, contents: nil)
            }
            let h = try FileHandle(forWritingTo: fileURL)
            try h.seekToEnd()
            handle = h
        } catch {
            handle = nil
        }
    }

    private func rotateIfNeeded() {
        guard let size = try? handle?.offset(), size > maxFileBytes else { return }
        try? handle?.close()
        handle = nil
        try? FileManager.default.removeItem(at: rotatedURL)
        try? FileManager.default.moveItem(at: fileURL, to: rotatedURL)
        openHandle()
    }
}
