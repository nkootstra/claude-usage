import SwiftUI
import ClaudeUsageCore

// MARK: - Hero + Row List Layout

struct UsageDetailView: View {
    let usage: UsageResponse
    var creditProjection: CreditBurnProjection?

    private var isEnterprise: Bool {
        usage.fiveHour == nil && usage.sevenDay == nil
            && usage.extraUsage?.isEnabled == true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            hero
            subRows
        }
    }

    // MARK: Hero

    @ViewBuilder
    private var hero: some View {
        if isEnterprise, let extra = usage.extraUsage {
            EnterpriseHeroCard(extra: extra, creditProjection: creditProjection)
        } else if let bucket = usage.fiveHour {
            BucketHeroCard(label: "5-Hour", bucket: bucket)
        } else if let bucket = usage.sevenDay {
            BucketHeroCard(label: "7-Day", bucket: bucket)
        } else {
            HeroCard(label: "No active limit", value: nil, caption: nil, pct: nil, color: .secondary)
        }
    }

    // MARK: Sub-rows

    @ViewBuilder
    private var subRows: some View {
        let rows = buildRows()
        if !rows.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    if index > 0 { Divider().opacity(0.2) }
                    row
                }
            }
            .padding(.top, 4)
        }
    }

    private func buildRows() -> [UsageRow] {
        var rows: [UsageRow] = []

        if !isEnterprise {
            // Consumer: if 5-Hour was the hero, show 7-Day as a sub-row
            if usage.fiveHour != nil, let sevenDay = usage.sevenDay {
                rows.append(UsageRow.bucket(label: "7-Day", bucket: sevenDay))
            }
        }

        if let sonnet = usage.sevenDaySonnet {
            rows.append(UsageRow.bucket(label: "Sonnet", bucket: sonnet))
        }
        if let opus = usage.sevenDayOpus {
            rows.append(UsageRow.bucket(label: "Opus", bucket: opus))
        }

        // Consumer extra usage row (enterprise already shown in hero)
        if !isEnterprise, let extra = usage.extraUsage, extra.isEnabled {
            rows.append(UsageRow.extra(extra: extra, creditProjection: creditProjection))
        }

        return rows
    }
}

// MARK: - Threshold-based color helper

private func thresholdColor(for pct: Double, warning: Double, critical: Double) -> Color {
    switch pct {
    case 0..<warning: return Color(.systemGreen)
    case warning..<critical: return Color(.systemOrange)
    default: return Color(.systemRed)
    }
}

// MARK: - Hero Card (shared shell)

struct HeroCard: View {
    let label: LocalizedStringKey
    let value: String?
    let caption: String?
    let pct: Double?
    let color: Color
    var trailing: AnyView? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                if let trailing { trailing }
            }

            if let value {
                Text(value)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .fontDesign(.rounded)
                    .monospacedDigit()
            }

            if let pct {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.primary.opacity(0.08))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(color)
                            .frame(width: max(0, geo.size.width * min(max(pct, 0), 1.0)))
                    }
                }
                .frame(height: 4)
            }

            if let caption {
                Text(caption)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }
}

// MARK: - Bucket Hero (5h/7d)

private struct BucketHeroCard: View {
    let label: LocalizedStringKey
    let bucket: UsageBucket
    @AppStorage("warningThreshold") private var warningThreshold = 50.0
    @AppStorage("criticalThreshold") private var criticalThreshold = 80.0

    var body: some View {
        HeroCard(
            label: label,
            value: "\(Int(bucket.utilization))%",
            caption: resetCaption(for: bucket),
            pct: bucket.utilization / 100.0,
            color: thresholdColor(for: bucket.utilization, warning: warningThreshold, critical: criticalThreshold)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text("\(Int(bucket.utilization)) percent" + (resetCaption(for: bucket).map { ", \($0)" } ?? "")))
    }
}

// MARK: - Enterprise Hero (Monthly Spend)

private struct EnterpriseHeroCard: View {
    let extra: ExtraUsage
    var creditProjection: CreditBurnProjection?
    @AppStorage("enterpriseShowPct") private var showPercentage = false
    @AppStorage("warningThreshold") private var warningThreshold = 50.0
    @AppStorage("criticalThreshold") private var criticalThreshold = 80.0

    private var hasLimit: Bool {
        (extra.monthlyLimit ?? 0) > 0
    }

    private var spendPct: Double {
        guard let used = extra.usedCredits, let limit = extra.monthlyLimit, limit > 0 else { return 0 }
        return used / limit
    }

    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 2
        return f
    }()

    private func formatUSD(_ amount: Double) -> String {
        Self.currencyFormatter.string(from: NSNumber(value: amount)) ?? String(format: "$%.2f", amount)
    }

    private var valueText: String? {
        if hasLimit && showPercentage {
            return "\(Int(spendPct * 100))%"
        } else if let used = extra.usedCreditsAmount {
            return formatUSD(used)
        }
        return nil
    }

    private var caption: String? {
        var parts: [String] = []
        if hasLimit, !showPercentage, let limit = extra.monthlyLimitAmount {
            parts.append("of \(formatUSD(limit)) limit")
        } else if hasLimit, showPercentage, let limit = extra.monthlyLimitAmount {
            parts.append("of \(formatUSD(limit)) limit")
        }
        if let projection = creditProjection, let date = projection.projectedExhaustionDate {
            let dateStr = date.formatted(.dateTime.month(.abbreviated).day())
            parts.append("~\(formatUSD(projection.burnRatePerDay))/day · exhausts \(dateStr)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        HeroCard(
            label: "Monthly Spend",
            value: valueText,
            caption: caption,
            pct: hasLimit ? spendPct : nil,
            color: thresholdColor(for: spendPct * 100, warning: warningThreshold, critical: criticalThreshold),
            trailing: hasLimit ? AnyView(
                Button {
                    showPercentage.toggle()
                } label: {
                    Text(showPercentage ? "$" : "%")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .frame(width: 16, height: 16)
                        .background(Color.primary.opacity(0.06))
                        .cornerRadius(3)
                }
                .buttonStyle(.borderless)
                .help(showPercentage ? "Show as dollars" : "Show as percentage")
            ) : nil
        )
    }
}

// MARK: - Usage Row

struct UsageRow: View {
    let label: LocalizedStringKey
    let pct: Double
    let percentText: String
    let meta: String?
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)

            if let meta {
                Text(meta)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.primary.opacity(0.08))
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(color)
                        .frame(width: max(0, geo.size.width * min(max(pct, 0), 1.0)))
                }
            }
            .frame(width: 60, height: 3)

            Text(percentText)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 30, alignment: .trailing)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 10)
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(percentText))
    }

    static func bucket(label: LocalizedStringKey, bucket: UsageBucket) -> UsageRow {
        let warning = UserDefaults.standard.object(forKey: "warningThreshold") as? Double ?? 50.0
        let critical = UserDefaults.standard.object(forKey: "criticalThreshold") as? Double ?? 80.0
        return UsageRow(
            label: label,
            pct: bucket.utilization / 100.0,
            percentText: "\(Int(bucket.utilization))%",
            meta: nil,
            color: thresholdColor(for: bucket.utilization, warning: warning, critical: critical)
        )
    }

    static func extra(extra: ExtraUsage, creditProjection: CreditBurnProjection?) -> UsageRow {
        let warning = UserDefaults.standard.object(forKey: "warningThreshold") as? Double ?? 50.0
        let critical = UserDefaults.standard.object(forKey: "criticalThreshold") as? Double ?? 80.0
        let utilization = extra.utilization ?? 0
        return UsageRow(
            label: "Extra",
            pct: utilization / 100.0,
            percentText: "\(Int(utilization))%",
            meta: nil,
            color: thresholdColor(for: utilization, warning: warning, critical: critical)
        )
    }
}

// MARK: - Reset time helper

private func resetCaption(for bucket: UsageBucket) -> String? {
    guard let date = bucket.resetsAtDate else { return nil }
    let remaining = date.timeIntervalSinceNow
    if remaining <= 0 { return "resetting…" }
    let totalMinutes = Int(remaining) / 60
    let days = totalMinutes / 1440
    let hours = (totalMinutes % 1440) / 60
    let mins = totalMinutes % 60
    if days > 0 { return "resets in \(days)d \(hours)h" }
    if hours > 0 { return "resets in \(hours)h \(mins)m" }
    return "resets in \(mins)m"
}
