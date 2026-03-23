import Foundation

public protocol HistoryServiceProtocol: Sendable {
    func record(from usage: UsageResponse) async
    func loadPoints() async -> [UsageDataPoint]
}

public final class HistoryService: HistoryServiceProtocol, Sendable {
    private let store: UsageHistoryStore

    public init(store: UsageHistoryStore) {
        self.store = store
    }

    public func record(from usage: UsageResponse) async {
        let point = UsageDataPoint(
            timestamp: Date(),
            fiveHourUtilization: usage.fiveHour?.utilization ?? 0,
            sevenDayUtilization: usage.sevenDay?.utilization ?? 0,
            sonnetUtilization: usage.sevenDaySonnet?.utilization,
            opusUtilization: usage.sevenDayOpus?.utilization,
            extraUsageUtilization: usage.extraUsage?.utilization,
            extraUsedCents: usage.extraUsage?.usedCredits,
            extraLimitCents: usage.extraUsage?.monthlyLimit
        )
        try? await store.record(point)
        try? await store.prune()
    }

    public func loadPoints() async -> [UsageDataPoint] {
        (try? await store.load()) ?? []
    }
}
