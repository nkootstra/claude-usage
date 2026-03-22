import SwiftUI
import Charts
import ClaudeUsageCore

struct UsageChartView: View {
    let points: [UsageDataPoint]
    let isEnterprise: Bool

    @State private var selectedRange: ChartRange = .auto

    enum ChartRange: String, CaseIterable {
        case auto = "Auto"
        case sevenDay = "7d"
        case thirtyDay = "30d"

        var localizedLabel: LocalizedStringKey {
            LocalizedStringKey(rawValue)
        }
    }

    /// How much history we actually have
    private var dataSpan: TimeInterval {
        guard let first = points.first, let last = points.last else { return 0 }
        return last.timestamp.timeIntervalSince(first.timestamp)
    }

    /// Available ranges based on actual data span
    private var availableRanges: [ChartRange] {
        var ranges: [ChartRange] = [.auto]
        if dataSpan > 24 * 3600 { ranges.append(.sevenDay) }     // > 1 day
        if dataSpan > 7 * 24 * 3600 { ranges.append(.thirtyDay) } // > 7 days
        return ranges
    }

    private var effectiveInterval: TimeInterval {
        switch selectedRange {
        case .auto: return dataSpan + 60 // show all data + small margin
        case .sevenDay: return 7 * 24 * 3600
        case .thirtyDay: return 30 * 24 * 3600
        }
    }

    private var filteredPoints: [UsageDataPoint] {
        let cutoff = Date().addingTimeInterval(-effectiveInterval)
        let filtered = points.filter { $0.timestamp >= cutoff }
        if filtered.count > 200 {
            return Downsampler.downsample(filtered, targetCount: 200)
        }
        return filtered
    }

    private var xAxisLabel: String {
        let hours = dataSpan / 3600
        if hours < 1 { return "minutes" }
        if hours < 24 { return "hours" }
        return "days"
    }

    private var xAxisFormat: Date.FormatStyle {
        let hours = effectiveInterval / 3600
        if hours <= 24 { return .dateTime.hour(.defaultDigits(amPM: .abbreviated)) }
        if hours <= 7 * 24 { return .dateTime.weekday(.abbreviated) }
        return .dateTime.month(.abbreviated).day()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("History")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                Spacer()
                if availableRanges.count > 1 {
                    Picker("", selection: $selectedRange) {
                        ForEach(availableRanges, id: \.self) { range in
                            Text(range.localizedLabel).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: CGFloat(availableRanges.count) * 45)
                }
            }

            if filteredPoints.count >= 2 {
                Chart {
                    ForEach(filteredPoints, id: \.timestamp) { point in
                        if !isEnterprise {
                            // 5-Hour area + line
                            AreaMark(
                                x: .value("Time", point.timestamp),
                                y: .value("Usage", point.fiveHourUtilization),
                                series: .value("Bucket", "5-Hour")
                            )
                            .foregroundStyle(
                                .linearGradient(
                                    colors: [Color(.systemTeal).opacity(0.25), Color(.systemTeal).opacity(0.03)],
                                    startPoint: .bottom, endPoint: .top
                                )
                            )
                            .interpolationMethod(.catmullRom)

                            LineMark(
                                x: .value("Time", point.timestamp),
                                y: .value("Usage", point.fiveHourUtilization),
                                series: .value("Bucket", "5-Hour")
                            )
                            .foregroundStyle(Color(.systemTeal))
                            .interpolationMethod(.catmullRom)
                            .lineStyle(StrokeStyle(lineWidth: 1.5))

                            // 7-Day area + line
                            AreaMark(
                                x: .value("Time", point.timestamp),
                                y: .value("Usage", point.sevenDayUtilization),
                                series: .value("Bucket", "7-Day")
                            )
                            .foregroundStyle(
                                .linearGradient(
                                    colors: [Color(.systemOrange).opacity(0.25), Color(.systemOrange).opacity(0.03)],
                                    startPoint: .bottom, endPoint: .top
                                )
                            )
                            .interpolationMethod(.catmullRom)

                            LineMark(
                                x: .value("Time", point.timestamp),
                                y: .value("Usage", point.sevenDayUtilization),
                                series: .value("Bucket", "7-Day")
                            )
                            .foregroundStyle(Color(.systemOrange))
                            .interpolationMethod(.catmullRom)
                            .lineStyle(StrokeStyle(lineWidth: 1.5))

                        } else if let extraPct = point.extraUsageUtilization {
                            AreaMark(
                                x: .value("Time", point.timestamp),
                                y: .value("Spend %", extraPct),
                                series: .value("Bucket", "Spend")
                            )
                            .foregroundStyle(
                                .linearGradient(
                                    colors: [Color(.systemOrange).opacity(0.25), Color(.systemOrange).opacity(0.03)],
                                    startPoint: .bottom, endPoint: .top
                                )
                            )
                            .interpolationMethod(.catmullRom)

                            LineMark(
                                x: .value("Time", point.timestamp),
                                y: .value("Spend %", extraPct),
                                series: .value("Bucket", "Spend")
                            )
                            .foregroundStyle(Color(.systemOrange))
                            .interpolationMethod(.catmullRom)
                            .lineStyle(StrokeStyle(lineWidth: 1.5))
                        }
                    }
                }
                .chartYScale(domain: 0...100)
                .chartYAxis {
                    AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let v = value.as(Int.self) {
                                Text("\(v)%")
                                    .font(.system(size: 8))
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(date, format: xAxisFormat)
                                    .font(.system(size: 8))
                            }
                        }
                    }
                }
                .chartLegend(position: .bottom, spacing: 4) {
                    if !isEnterprise {
                        HStack(spacing: 12) {
                            Label("5-Hour", systemImage: "circle.fill")
                                .foregroundStyle(Color(.systemTeal))
                            Label("7-Day", systemImage: "circle.fill")
                                .foregroundStyle(Color(.systemOrange))
                        }
                        .font(.system(size: 9))
                    }
                }
                .frame(height: 120)
            } else {
                Text("Not enough data yet — check back after a few polls")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(height: 40)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}
