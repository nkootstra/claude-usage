import Foundation
import UserNotifications

public final class NotificationService: Sendable {
    private let notifiedKey = "claude-usage.notified.thresholds"
    // UserDefaults is documented thread-safe but isn't marked Sendable in Swift 6.
    nonisolated(unsafe) private let defaults: UserDefaults

    /// Returns active thresholds based on user settings
    private var thresholds: [Double] {
        let warning = defaults.object(forKey: "warningThreshold") as? Double ?? 50
        let critical = defaults.object(forKey: "criticalThreshold") as? Double ?? 80
        return [warning, critical]
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func requestPermission() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    public func checkAndNotify(fiveHourPct: Double) {
        let enabled = defaults.object(forKey: "notificationThresholdAlerts") as? Bool ?? true
        guard enabled else { return }

        // Track the persisted set in-place; reading once per iteration would
        // miss earlier appends and let the per-iteration overwrite drop them.
        var notified = defaults.array(forKey: notifiedKey) as? [Double] ?? []

        for threshold in thresholds {
            if fiveHourPct >= threshold && !notified.contains(threshold) {
                sendNotification(threshold: threshold, current: fiveHourPct)
                notified.append(threshold)
                defaults.set(notified, forKey: notifiedKey)
            }
        }

        // Reset notifications when usage drops below lowest threshold
        if fiveHourPct < (thresholds.min() ?? 80) {
            defaults.removeObject(forKey: notifiedKey)
        }
    }

    // MARK: - Burn Rate

    private static let burnRateKeyPrefix = "claude-usage.burnrate.notified."

    /// Check if we should send a burn rate notification (< 60 min to exhaustion, not already notified)
    public func shouldNotifyBurnRate(projection: BurnRateProjection, bucketLabel: String) -> Bool {
        let enabled = defaults.object(forKey: "notificationBurnRateAlerts") as? Bool ?? true
        guard enabled else { return false }
        guard let minutes = projection.minutesUntilExhaustion,
              minutes > 0, minutes <= 60,
              projection.velocityPerHour > 0 else {
            return false
        }
        let key = Self.burnRateKeyPrefix + bucketLabel
        return !defaults.bool(forKey: key)
    }

    public func markBurnRateNotified(bucketLabel: String) {
        let key = Self.burnRateKeyPrefix + bucketLabel
        defaults.set(true, forKey: key)
    }

    public func resetBurnRateNotification(bucketLabel: String) {
        let key = Self.burnRateKeyPrefix + bucketLabel
        defaults.removeObject(forKey: key)
    }

    public func sendBurnRateNotification(bucketLabel: String, minutesRemaining: Double) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "notification.burnRate.title", bundle: .main)
        content.body = String(localized: "notification.burnRate.body \(bucketLabel) \(Int(minutesRemaining))", bundle: .main)
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "claude-usage.burnrate.\(bucketLabel)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func sendNotification(threshold: Double, current: Double) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "notification.threshold.title", bundle: .main)
        content.body = String(localized: "notification.threshold.body \(Int(current)) \(Int(threshold))", bundle: .main)
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "claude-usage.threshold.\(Int(threshold))",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
