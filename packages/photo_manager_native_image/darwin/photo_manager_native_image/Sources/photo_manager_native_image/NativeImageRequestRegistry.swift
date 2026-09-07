import Foundation

/// Reply payload: `{pointer, width, height, rowBytes}`.
typealias NativeImageReply = [String: Int64]

/// One in-flight request. `finish` delivers the reply exactly once no matter
/// how many exit paths race to call it.
final class NativeImageRequestState {
    let requestId: Int64
    private let lock = NSLock()
    private var done = false
    private var cancelled = false
    private var completion: ((Result<NativeImageReply?, Error>) -> Void)?

    init(requestId: Int64, completion: @escaping (Result<NativeImageReply?, Error>) -> Void) {
        self.requestId = requestId
        self.completion = completion
    }

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    var isDone: Bool {
        lock.lock(); defer { lock.unlock() }
        return done
    }

    func markCancelled() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
    }

    /// Returns `true` if this call delivered the reply, `false` if it was
    /// already delivered.
    @discardableResult
    func finish(_ result: Result<NativeImageReply?, Error>) -> Bool {
        lock.lock()
        if done {
            lock.unlock()
            return false
        }
        done = true
        let completion = self.completion
        self.completion = nil
        lock.unlock()
        completion?(result)
        return true
    }
}

/// Tracks requests between arrival and reply so that cancels can be applied
/// before a buffer is allocated. Cancels for ids not yet seen are remembered
/// and consumed by the request when it arrives.
final class NativeImageRequestRegistry {
    static let cancelledAheadLimit = 4096

    private let lock = NSLock()
    private var pending: [Int64: NativeImageRequestState] = [:]
    private var cancelledAhead: Set<Int64> = []

    /// Registers a request. Returns `false` when a cancel for this id arrived
    /// first; the caller must reply `nil` without doing any work.
    func register(_ state: NativeImageRequestState) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if cancelledAhead.remove(state.requestId) != nil {
            return false
        }
        pending[state.requestId] = state
        return true
    }

    func cancel(requestId: Int64) {
        lock.lock(); defer { lock.unlock() }
        if let state = pending[requestId] {
            state.markCancelled()
        } else {
            // A cancel that raced an already-sent reply would otherwise pin
            // its id here forever; the set is a hint, so it is safe to drop.
            if cancelledAhead.count >= Self.cancelledAheadLimit {
                cancelledAhead.removeAll()
            }
            cancelledAhead.insert(requestId)
        }
    }

    func remove(requestId: Int64) {
        lock.lock(); defer { lock.unlock() }
        pending.removeValue(forKey: requestId)
    }

    /// Cancels and drains every pending request (engine detach).
    func cancelAll() -> [NativeImageRequestState] {
        lock.lock(); defer { lock.unlock() }
        let states = Array(pending.values)
        states.forEach { $0.markCancelled() }
        pending.removeAll()
        cancelledAhead.removeAll()
        return states
    }

    var pendingCount: Int {
        lock.lock(); defer { lock.unlock() }
        return pending.count
    }

    var cancelledAheadCount: Int {
        lock.lock(); defer { lock.unlock() }
        return cancelledAhead.count
    }
}
