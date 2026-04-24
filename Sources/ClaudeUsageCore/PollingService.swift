import Foundation

public protocol PollingServiceProtocol: AnyObject, Sendable {
    @MainActor func start(fireImmediately: Bool, initialDelay: TimeInterval?)
    @MainActor func stop()
    @MainActor func updateInterval(_ seconds: TimeInterval)
}

@MainActor
public final class PollingService: PollingServiceProtocol {
    private let client: TokenRefreshingClient
    private var pollingInterval: TimeInterval
    private var pollingTask: Task<Void, Never>?
    private(set) var currentBackoff: TimeInterval?

    public var onResult: (@MainActor @Sendable (Result<UsageFetchResult, any Error>) async -> Void)?

    public init(client: TokenRefreshingClient, pollingInterval: TimeInterval = 300) {
        self.client = client
        self.pollingInterval = pollingInterval
    }

    public func start(fireImmediately: Bool = true, initialDelay: TimeInterval? = nil) {
        stop()
        pollingTask = Task {
            if fireImmediately {
                await fetchAndDeliver()
            } else if let initialDelay, initialDelay > 0 {
                try? await Task.sleep(for: .seconds(initialDelay))
                guard !Task.isCancelled else { return }
                await fetchAndDeliver()
            }
            while !Task.isCancelled {
                let interval = currentBackoff ?? pollingInterval
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { break }
                await fetchAndDeliver()
            }
        }
    }

    public func stop() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    public func updateInterval(_ seconds: TimeInterval) {
        pollingInterval = seconds
        if pollingTask != nil {
            start()
        }
    }

    public func resetBackoff() {
        currentBackoff = nil
    }

    public func applyBackoff(baseInterval: TimeInterval) {
        currentBackoff = min((currentBackoff ?? baseInterval) * 2, 120)
    }

    public func setBackoff(_ interval: TimeInterval) {
        currentBackoff = min(interval, 120)
    }

    private func fetchAndDeliver() async {
        do {
            let result = try await client.fetchUsage()
            await onResult?(.success(result))
        } catch {
            await onResult?(.failure(error))
        }
    }
}
