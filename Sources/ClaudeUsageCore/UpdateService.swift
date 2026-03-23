import Foundation

public protocol UpdateServiceProtocol: AnyObject, Sendable {
    @MainActor func start()
    @MainActor func stop()
}

@MainActor
public final class UpdateService: UpdateServiceProtocol {
    private let checker: UpdateChecker
    private var task: Task<Void, Never>?
    private static let checkInterval: TimeInterval = 6 * 3600
    private static let dismissedVersionKey = "claude-usage.dismissedUpdateVersion"

    public var onUpdate: (@MainActor (UpdateInfo?) -> Void)?

    public init(checker: UpdateChecker = UpdateChecker()) {
        self.checker = checker
    }

    public func start() {
        stop()
        task = Task {
            await checkForUpdate()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.checkInterval))
                guard !Task.isCancelled else { break }
                await checkForUpdate()
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    public func dismissUpdate(version: String) {
        UserDefaults.standard.set(version, forKey: Self.dismissedVersionKey)
        onUpdate?(nil)
    }

    private func checkForUpdate() async {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        guard let update = await checker.check(currentVersion: currentVersion) else { return }
        let dismissed = UserDefaults.standard.string(forKey: Self.dismissedVersionKey)
        if update.version != dismissed {
            onUpdate?(update)
        }
    }
}
