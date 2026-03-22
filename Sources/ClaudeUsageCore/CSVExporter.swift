import Foundation

public enum CSVExporter {
    public static func export(_ points: [UsageDataPoint]) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        var lines = ["date,five_hour_pct,seven_day_pct,sonnet_pct,opus_pct,extra_usage_pct,extra_used_cents,extra_limit_cents"]
        for point in points {
            let date = formatter.string(from: point.timestamp)
            let sonnet = point.sonnetUtilization.map { "\($0)" } ?? ""
            let opus = point.opusUtilization.map { "\($0)" } ?? ""
            let extraPct = point.extraUsageUtilization.map { "\($0)" } ?? ""
            let extraUsed = point.extraUsedCents.map { "\($0)" } ?? ""
            let extraLimit = point.extraLimitCents.map { "\($0)" } ?? ""
            lines.append("\(date),\(point.fiveHourUtilization),\(point.sevenDayUtilization),\(sonnet),\(opus),\(extraPct),\(extraUsed),\(extraLimit)")
        }
        return lines.joined(separator: "\n")
    }
}
