import Combine
import Foundation
import Testing
@testable import ClaudeUsageApp

@Suite("Main queue publishers")
struct MainQueuePublisherTests {
    @Test("receiveOnMainQueue delivers background notifications on main thread")
    func receiveOnMainQueueDeliversOnMainThread() async throws {
        let deliveredOnMainThread = ThreadFlag()
        var cancellables = Set<AnyCancellable>()

        NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification)
            .receiveOnMainQueue()
            .sink { _ in
                deliveredOnMainThread.set(Thread.isMainThread)
            }
            .store(in: &cancellables)

        await Task.detached {
            NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: nil)
        }.value

        try await waitUntil(deliveredOnMainThread.hasValue)
        #expect(deliveredOnMainThread.value == true)
    }
}

private final class ThreadFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Bool?

    var value: Bool? {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }

    func set(_ value: Bool) {
        lock.lock()
        defer { lock.unlock() }
        storedValue = value
    }

    func hasValue() -> Bool {
        value != nil
    }
}

private func waitUntil(
    _ condition: @escaping @Sendable () -> Bool,
    timeout: Duration = .seconds(1)
) async throws {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        if ContinuousClock.now >= deadline {
            Issue.record("Timed out waiting for condition")
            return
        }
        try await Task.sleep(for: .milliseconds(10))
    }
}
