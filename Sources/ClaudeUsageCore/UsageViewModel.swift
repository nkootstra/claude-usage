import Foundation

public typealias CredentialProvider = @Sendable () -> OAuthCredential?

@MainActor
public final class UsageViewModel: ObservableObject {
    @Published public var usage: UsageResponse?
    @Published public var error: UsageError?
    @Published public var lastUpdated: Date?
    @Published public private(set) var currentBackoff: TimeInterval?
    @Published public var creditProjection: CreditBurnProjection?
    @Published public var availableUpdate: UpdateInfo?
    @Published public var profile: ProfileResponse?

    public var planTier: PlanTier {
        PlanTier.derive(profile: profile, isEnterprise: isEnterprise)
    }

    private let client: TokenRefreshingClient
    private let pollingService: PollingService
    private let notificationCoordinator: NotificationCoordinator?
    private let updateService: UpdateService

    public var isEnterprise: Bool {
        usage?.fiveHour == nil && usage?.sevenDay == nil
            && usage?.extraUsage?.isEnabled == true
    }

    public var menuBarText: String {
        if isEnterprise {
            guard let used = usage?.extraUsage?.usedCreditsAmount else { return "--" }
            if used < 1 { return "$0" }
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
        updateChecker: UpdateChecker = UpdateChecker()
    ) {
        let client = TokenRefreshingClient(apiClient: apiClient, credentialProvider: credentialProvider)
        self.client = client
        self.pollingService = PollingService(client: client, pollingInterval: pollingInterval)
        self.notificationCoordinator = notificationService.map { NotificationCoordinator(notificationService: $0) }
        self.updateService = UpdateService(checker: updateChecker)

        pollingService.onResult = { @MainActor [weak self] result in
            await self?.handleFetchResult(result)
        }
        updateService.onUpdate = { [weak self] update in
            self?.availableUpdate = update
        }
    }

    public func startPolling() {
        pollingService.start()
        updateService.start()
    }

    public func stopPolling() {
        pollingService.stop()
        updateService.stop()
    }

    public func updatePollingInterval(_ seconds: TimeInterval) {
        pollingService.updateInterval(seconds)
    }

    public func dismissUpdate() {
        if let version = availableUpdate?.version {
            updateService.dismissUpdate(version: version)
        }
        availableUpdate = nil
    }

    public func signOut() {
        stopPolling()
        usage = nil
        error = .noCredential
        lastUpdated = nil
        currentBackoff = nil
        creditProjection = nil
        profile = nil
        notificationCoordinator?.reset()
    }

    private func refreshProfileIfNeeded() async {
        if profile != nil { return }
        if let fetched = try? await client.fetchProfile() {
            profile = fetched
        }
    }

    /// Single manual refresh — used by UI "refresh" button and tests.
    public func refresh() async {
        pollingService.resetBackoff()
        currentBackoff = nil
        do {
            let result = try await client.fetchUsage()
            await handleFetchResult(.success(result))
        } catch {
            await handleFetchResult(.failure(error))
        }
        // Restart polling so the loop picks up the new backoff state
        pollingService.start()
    }

    private func handleFetchResult(_ result: Result<UsageFetchResult, any Error>) async {
        switch result {
        case .success(let fetchResult):
            usage = fetchResult.usage
            error = nil
            lastUpdated = Date()
            currentBackoff = nil
            pollingService.resetBackoff()

            await refreshProfileIfNeeded()

            if let notificationCoordinator {
                creditProjection = notificationCoordinator.evaluate(usage: fetchResult.usage).creditProjection
            } else if let extra = fetchResult.usage.extraUsage, extra.isEnabled,
                      let used = extra.usedCreditsAmount, let limit = extra.monthlyLimitAmount {
                creditProjection = BurnRateCalculator.projectCredits(
                    usedDollars: used,
                    limitDollars: limit
                )
            } else {
                creditProjection = nil
            }

        case .failure(let err):
            if let clientError = err as? TokenRefreshingClientError {
                switch clientError {
                case .noCredential:
                    error = .noCredential
                case .unauthorized:
                    error = .unauthorized
                case .backoff(let interval):
                    pollingService.setBackoff(interval)
                    currentBackoff = interval
                    error = .rateLimited(retryIn: interval)
                case .other(let message):
                    pollingService.applyBackoff(baseInterval: 30)
                    currentBackoff = pollingService.currentBackoff
                    error = .networkError(message)
                }
            } else {
                pollingService.applyBackoff(baseInterval: 30)
                currentBackoff = pollingService.currentBackoff
                error = .unknown(err.localizedDescription)
            }
        }
    }
}
