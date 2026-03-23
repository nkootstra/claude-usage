import Foundation

public typealias CredentialProvider = @Sendable () -> OAuthCredential?

@MainActor
public final class UsageViewModel: ObservableObject {
    @Published public var usage: UsageResponse?
    @Published public var error: String?
    @Published public var lastUpdated: Date?
    @Published public private(set) var currentBackoff: TimeInterval?
    @Published public var historyPoints: [UsageDataPoint] = []
    @Published public var creditProjection: CreditBurnProjection?
    @Published public var availableUpdate: UpdateInfo?

    private let client: TokenRefreshingClient
    private var pollingInterval: TimeInterval
    private var pollingTask: Task<Void, Never>?
    private var updateTask: Task<Void, Never>?
    private let notificationService: NotificationService?
    private let historyStore: UsageHistoryStore?
    private let updateChecker: UpdateChecker

    public var isEnterprise: Bool {
        usage?.fiveHour == nil && usage?.sevenDay == nil
            && usage?.extraUsage?.isEnabled == true
    }

    public var menuBarText: String {
        if isEnterprise {
            guard let used = usage?.extraUsage?.usedCreditsAmount else { return "--" }
            if used < 1 { return "$0" }
            if used < 100 { return String(format: "$%.0f", used) }
            return String(format: "$%.0f", used)
        }
        guard let utilization = usage?.fiveHour?.utilization else { return "--" }
        return "\(Int(utilization))%"
    }

    public init(
        apiClient: AnthropicAPIClient = AnthropicAPIClient(),
        credentialProvider: @escaping CredentialProvider,
        pollingInterval: TimeInterval = 300,
        notificationService: NotificationService? = nil,
        historyStore: UsageHistoryStore? = nil,
        updateChecker: UpdateChecker = UpdateChecker()
    ) {
        self.client = TokenRefreshingClient(apiClient: apiClient, credentialProvider: credentialProvider)
        self.pollingInterval = pollingInterval
        self.notificationService = notificationService
        self.historyStore = historyStore
        self.updateChecker = updateChecker
    }

    public func startPolling() {
        stopPolling()
        pollingTask = Task {
            await refresh()
            while !Task.isCancelled {
                let interval = currentBackoff ?? pollingInterval
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { break }
                await refresh()
            }
        }
        startUpdateChecking()
    }

    private static let updateCheckInterval: TimeInterval = 6 * 3600 // 6 hours
    private static let dismissedVersionKey = "claude-usage.dismissedUpdateVersion"

    private func startUpdateChecking() {
        updateTask?.cancel()
        updateTask = Task {
            await checkForUpdate()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.updateCheckInterval))
                guard !Task.isCancelled else { break }
                await checkForUpdate()
            }
        }
    }

    private func checkForUpdate() async {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        guard let update = await updateChecker.check(currentVersion: currentVersion) else { return }
        let dismissed = UserDefaults.standard.string(forKey: Self.dismissedVersionKey)
        if update.version != dismissed {
            availableUpdate = update
        }
    }

    public func dismissUpdate() {
        if let version = availableUpdate?.version {
            UserDefaults.standard.set(version, forKey: Self.dismissedVersionKey)
        }
        availableUpdate = nil
    }

    public func updatePollingInterval(_ seconds: TimeInterval) {
        pollingInterval = seconds
        if pollingTask != nil {
            startPolling() // restart with new interval
        }
    }

    public func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        updateTask?.cancel()
        updateTask = nil
    }

    public func signOut() {
        stopPolling()
        usage = nil
        error = "No credential"
        lastUpdated = nil
        currentBackoff = nil
        historyPoints = []
        creditProjection = nil
    }

    public func refresh() async {
        do {
            let result = try await client.fetchUsage()
            usage = result.usage
            error = nil
            lastUpdated = Date()
            currentBackoff = nil

            // Record history
            if let store = historyStore {
                let u = result.usage
                let point = UsageDataPoint(
                    timestamp: Date(),
                    fiveHourUtilization: u.fiveHour?.utilization ?? 0,
                    sevenDayUtilization: u.sevenDay?.utilization ?? 0,
                    sonnetUtilization: u.sevenDaySonnet?.utilization,
                    opusUtilization: u.sevenDayOpus?.utilization,
                    extraUsageUtilization: u.extraUsage?.utilization,
                    extraUsedCents: u.extraUsage?.usedCredits,
                    extraLimitCents: u.extraUsage?.monthlyLimit
                )
                try? await store.record(point)
                // Prune on each write (cheap with indexed timestamp)
                try? await store.prune()
                historyPoints = (try? await store.load()) ?? []

                // Burn rate projection + notification
                if let fiveHourPct = result.usage.fiveHour?.utilization {
                    let projection = BurnRateCalculator.project(
                        points: historyPoints,
                        currentUtilization: fiveHourPct
                    )
                    if let svc = notificationService,
                       svc.shouldNotifyBurnRate(projection: projection, bucketLabel: "5-Hour") {
                        svc.sendBurnRateNotification(bucketLabel: "5-Hour", minutesRemaining: projection.minutesUntilExhaustion ?? 0)
                        svc.markBurnRateNotified(bucketLabel: "5-Hour")
                    }
                }
            }

            // Enterprise credit projection
            if let extra = result.usage.extraUsage, extra.isEnabled,
               let used = extra.usedCreditsAmount, let limit = extra.monthlyLimitAmount {
                creditProjection = BurnRateCalculator.projectCredits(
                    usedDollars: used,
                    limitDollars: limit
                )
            } else {
                creditProjection = nil
            }

            // Threshold notifications
            if let pct = usage?.fiveHour?.utilization {
                notificationService?.checkAndNotify(fiveHourPct: pct)
            }
        } catch let err as TokenRefreshingClientError {
            switch err {
            case .noCredential:
                error = "No credential"
            case .unauthorized:
                error = "Unauthorized — token may be revoked"
            case .backoff(let interval):
                currentBackoff = interval
                error = "Rate limited — retrying in \(Int(interval))s"
            case .other(let message):
                currentBackoff = min((currentBackoff ?? pollingInterval) * 2, 3600)
                error = message
            }
        } catch {
            currentBackoff = min((currentBackoff ?? pollingInterval) * 2, 3600)
            self.error = error.localizedDescription
        }
    }
}
