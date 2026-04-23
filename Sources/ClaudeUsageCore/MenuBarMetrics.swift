import Foundation

public enum MenuBarColorSemantic: Equatable, Sendable {
    case ok
    case warning
    case critical
    case tealScale(opacity: Double)
}

public enum MenuBarMetrics {
    public static func consumerPrimaryPercent(from usage: UsageResponse?) -> Int? {
        guard let utilization = usage?.fiveHour?.utilization else { return nil }
        return Int(utilization)
    }

    public static func consumerSecondaryPercent(from usage: UsageResponse?) -> Int? {
        guard let utilization = usage?.sevenDay?.utilization else { return nil }
        return Int(utilization)
    }

    public static func thresholdColor(
        for percent: Double,
        warning: Double,
        critical: Double,
        colorMode: String
    ) -> MenuBarColorSemantic {
        if colorMode == "single_color" {
            let opacity = 0.4 + (percent / 100.0) * 0.6
            return .tealScale(opacity: min(max(opacity, 0.4), 1.0))
        }
        switch percent {
        case ..<warning: return .ok
        case warning..<critical: return .warning
        default: return .critical
        }
    }
}
