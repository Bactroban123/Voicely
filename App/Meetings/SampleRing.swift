import Foundation

/// A single-producer / single-consumer ring for handing audio samples off the
/// real-time thread.
///
/// Core Audio's IO thread has a hard deadline (~10ms at 48kHz/512 frames) and
/// may not allocate, take locks, or touch ARC — the allocator's slow path or a
/// VM fault will blow the deadline and glitch the capture. So the producer here
/// does exactly two things: `memcpy` into preallocated storage, then publish an
/// index. No allocation, no locks, no refcounting.
///
/// Overflow drops the newest samples rather than blocking: back-pressuring a
/// real-time thread is never an option, and a bounded ring is also what keeps
/// the "two hours costs the same RAM as two minutes" promise honest when the
/// disk stalls (Time Machine, APFS snapshots) — unbounded `queue.async` would
/// pile buffers up instead.
///
/// Memory ordering: `writeIndex` is written only by the producer and read only
/// by the consumer (and vice versa for `readIndex`), as naturally-aligned words,
/// which arm64 loads and stores without tearing. There are no acquire/release
/// fences here, so the consumer may observe a slightly stale `writeIndex` — the
/// only consequence is that it drains those samples on the next pass. That
/// tradeoff is deliberate: it avoids a dependency (swift-atomics) or a
/// macOS 15 floor (`Synchronization.Atomic`) for a guarantee this use doesn't
/// need.
final class SampleRing {
    private let storage: UnsafeMutablePointer<Float>
    private let capacity: Int
    private var writeIndex = 0      // producer only
    private var readIndex = 0       // consumer only
    private var droppedSamples = 0  // producer only; diagnostics

    /// - Parameter capacity: sample slots. Default ~10s at 48kHz mono, which is
    ///   generous headroom over the sub-millisecond drain latency we expect.
    init(capacity: Int = 48_000 * 10) {
        self.capacity = capacity
        storage = UnsafeMutablePointer<Float>.allocate(capacity: capacity)
        storage.initialize(repeating: 0, count: capacity)
    }

    deinit {
        storage.deinitialize(count: capacity)
        storage.deallocate()
    }

    /// REAL-TIME SAFE. Call only from the audio IO thread.
    /// Returns false if samples were dropped because the consumer fell behind.
    @discardableResult
    func write(_ samples: UnsafePointer<Float>, count: Int) -> Bool {
        let used = writeIndex - readIndex
        let free = capacity - used
        guard count <= free else {
            droppedSamples += count
            return false
        }
        let offset = writeIndex % capacity
        let firstChunk = min(count, capacity - offset)
        storage.advanced(by: offset).update(from: samples, count: firstChunk)
        if firstChunk < count {
            storage.update(from: samples.advanced(by: firstChunk), count: count - firstChunk)
        }
        writeIndex += count   // publish last: the consumer never reads ahead of this
        return true
    }

    /// Consumer side. Drains up to `into.count` samples; returns how many.
    func read(into destination: UnsafeMutablePointer<Float>, max maxCount: Int) -> Int {
        let available = writeIndex - readIndex
        let count = min(available, maxCount)
        guard count > 0 else { return 0 }
        let offset = readIndex % capacity
        let firstChunk = min(count, capacity - offset)
        destination.update(from: storage.advanced(by: offset), count: firstChunk)
        if firstChunk < count {
            destination.advanced(by: firstChunk).update(from: storage, count: count - firstChunk)
        }
        readIndex += count
        return count
    }

    /// Samples the producer had to discard. Read from the consumer side for
    /// diagnostics only — an approximate value is fine.
    var dropped: Int { droppedSamples }

    var isEmpty: Bool { writeIndex == readIndex }
}
