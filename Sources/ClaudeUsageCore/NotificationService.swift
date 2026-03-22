import Foundation
import UserNotifications

public final class NotificationService: Sendable {
    private let notifiedKey = "claude-usage.notified.thresholds"

    /// Returns active thresholds based on user settings
    private var thresholds: [Double] {
        var result: [Double] = []
        if UserDefaults.standard.object(forKey: "notifyAt80") == nil || UserDefaults.standard.bool(forKey: "notifyAt80") {
            result.append(80)
        }
        if UserDefaults.standard.object(forKey: "notifyAt95") == nil || UserDefaults.standard.bool(forKey: "notifyAt95") {
            result.append(95)
        }
        return result
    }

    public init() {}

    public func requestPermission() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    public func checkAndNotify(fiveHourPct: Double) {
        let notified = UserDefaults.standard.array(forKey: notifiedKey) as? [Double] ?? []

        for threshold in thresholds {
            if fiveHourPct >= threshold && !notified.contains(threshold) {
                sendNotification(threshold: threshold, current: fiveHourPct)
                var updated = notified
                updated.append(threshold)
                UserDefaults.standard.set(updated, forKey: notifiedKey)
            }
        }

        // Reset notifications when usage drops below lowest threshold
        if fiveHourPct < (thresholds.min() ?? 80) {
            UserDefaults.standard.removeObject(forKey: notifiedKey)
        }
    }

    // MARK: - Burn Rate

    private static let burnRateKeyPrefix = "claude-usage.burnrate.notified."

    /// Check if we should send a burn rate notification (< 60 min to exhaustion, not already notified)
    public func shouldNotifyBurnRate(projection: BurnRateProjection, bucketLabel: String) -> Bool {
        guard let minutes = projection.minutesUntilExhaustion,
              minutes > 0, minutes <= 60,
              projection.velocityPerHour > 0 else {
            return false
        }
        let key = Self.burnRateKeyPrefix + bucketLabel
        return !UserDefaults.standard.bool(forKey: key)
    }

    public func markBurnRateNotified(bucketLabel: String) {
        let key = Self.burnRateKeyPrefix + bucketLabel
        UserDefaults.standard.set(true, forKey: key)
    }

    public func resetBurnRateNotification(bucketLabel: String) {
        let key = Self.burnRateKeyPrefix + bucketLabel
        UserDefaults.standard.removeObject(forKey: key)
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
