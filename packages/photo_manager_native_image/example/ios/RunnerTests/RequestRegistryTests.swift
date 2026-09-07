import XCTest
@testable import photo_manager_native_image

final class RequestRegistryTests: XCTestCase {
    private func state(_ id: Int64, _ sink: @escaping (Result<NativeImageReply?, Error>) -> Void = { _ in }) -> NativeImageRequestState {
        NativeImageRequestState(requestId: id, completion: sink)
    }

    func testFinishDeliversExactlyOnce() {
        var replies = 0
        let s = state(1) { _ in replies += 1 }
        XCTAssertTrue(s.finish(.success(nil)))
        XCTAssertFalse(s.finish(.success(["pointer": 1])))
        XCTAssertFalse(s.finish(.failure(NativeImageError(code: "decode_failed", message: nil, details: nil))))
        XCTAssertEqual(replies, 1)
        XCTAssertTrue(s.isDone)
    }

    func testCancelBeforeAllocationMarksState() {
        let registry = NativeImageRequestRegistry()
        let s = state(7)
        XCTAssertTrue(registry.register(s))
        registry.cancel(requestId: 7)
        XCTAssertTrue(s.isCancelled)
        XCTAssertEqual(registry.cancelledAheadCount, 0)
    }

    func testCancelAheadOfRequestIsConsumedOnce() {
        let registry = NativeImageRequestRegistry()
        registry.cancel(requestId: 3)
        XCTAssertEqual(registry.cancelledAheadCount, 1)
        XCTAssertFalse(registry.register(state(3)))
        XCTAssertEqual(registry.cancelledAheadCount, 0)
        XCTAssertTrue(registry.register(state(3)))
    }

    func testCancelAfterRemovalDoesNotResurrectRequest() {
        let registry = NativeImageRequestRegistry()
        let s = state(9)
        XCTAssertTrue(registry.register(s))
        registry.remove(requestId: 9)
        registry.cancel(requestId: 9)
        XCTAssertFalse(s.isCancelled)
        XCTAssertEqual(registry.pendingCount, 0)
    }

    func testCancelledAheadSetIsBounded() {
        let registry = NativeImageRequestRegistry()
        for id in 0..<Int64(NativeImageRequestRegistry.cancelledAheadLimit + 5) {
            registry.cancel(requestId: id)
        }
        XCTAssertLessThanOrEqual(registry.cancelledAheadCount, NativeImageRequestRegistry.cancelledAheadLimit)
    }

    func testCancelAllDrainsPending() {
        let registry = NativeImageRequestRegistry()
        let a = state(1), b = state(2)
        _ = registry.register(a)
        _ = registry.register(b)
        let drained = registry.cancelAll()
        XCTAssertEqual(drained.count, 2)
        XCTAssertTrue(a.isCancelled && b.isCancelled)
        XCTAssertEqual(registry.pendingCount, 0)
    }

    func testConcurrentFinishDeliversOnce() {
        let counter = NSLock()
        var replies = 0
        let s = state(5) { _ in counter.lock(); replies += 1; counter.unlock() }
        DispatchQueue.concurrentPerform(iterations: 32) { _ in _ = s.finish(.success(nil)) }
        XCTAssertEqual(replies, 1)
    }
}
