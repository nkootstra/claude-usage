import SwiftUI
import ClaudeUsageCore

// MARK: - Card Grid Layout

struct UsageDetailView: View {
    let usage: UsageResponse
    var creditProjection: CreditBurnProjection?

    /// Enterprise mode: no 5h/7d limits, only credits
    private var isEnterprise: Bool {
        usage.fiveHour == nil && usage.sevenDay == nil
            && usage.extraUsage?.isEnabled == true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isEnterprise {
                // Enterprise: credits are the hero
                if let extra = usage.extraUsage {
                    EnterpriseCreditCard(extra: extra, creditProjection: creditProjection)
                }

                // Per-model breakdown below
                let hasModel = usage.sevenDaySonnet != nil || usage.sevenDayOpus != nil
                if hasModel {
                    HStack(spacing: 8) {
                        if let bucket = usage.sevenDaySonnet {
                            UsageCard(label: "Sonnet", bucket: bucket, compact: true)
                        }
                        if let bucket = usage.sevenDayOpus {
                            UsageCard(label: "Opus", bucket: bucket, compact: true)
                        }
                        if usage.sevenDaySonnet == nil || usage.sevenDayOpus == nil {
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                }
            } else {
                // Consumer: 5h/7d cards as primary
                HStack(spacing: 8) {
                    if let bucket = usage.fiveHour {
                        UsageCard(label: "5-Hour", bucket: bucket)
                    }
                    if let bucket = usage.sevenDay {
                        UsageCard(label: "7-Day", bucket: bucket)
                    }
                }

                let hasModel = usage.sevenDaySonnet != nil || usage.sevenDayOpus != nil
                if hasModel {
                    HStack(spacing: 8) {
                        if let bucket = usage.sevenDaySonnet {
                            UsageCard(label: "Sonnet", bucket: bucket, compact: true)
                        }
                        if let bucket = usage.sevenDayOpus {
                            UsageCard(label: "Opus", bucket: bucket, compact: true)
                        }
                        if usage.sevenDaySonnet == nil || usage.sevenDayOpus == nil {
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                }

                // Consumer extra usage (if enabled alongside regular limits)
                if let extra = usage.extraUsage, extra.isEnabled {
                    ExtraUsageCard(extra: extra, creditProjection: creditProjection)
                }
            }
        }
    }
}

// MARK: - Usage Card (consumer 5h/7d/model)

struct UsageCard: View {
    let label: String
    let bucket: UsageBucket
    var compact: Bool = false

    private var pct: Double { bucket.utilization / 100.0 }

    private var barColor: Color {
        switch bucket.utilization {
        case 0..<50: return Color(.systemGreen)
        case 50..<80: return Color(.systemOrange)
        default: return Color(.systemRed)
        }
    }

    private var resetText: String {
        guard let date = bucket.resetsAtDate else { return "" }
        let remaining = date.timeIntervalSinceNow
        if remaining <= 0 { return "resetting..." }
        let totalMinutes = Int(remaining) / 60
        let days = totalMinutes / 1440
        let hours = (totalMinutes % 1440) / 60
        let mins = totalMinutes % 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(mins)m" }
        return "\(mins)m"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 4 : 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(compact ? .caption2 : .caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if !resetText.isEmpty {
                    Text(resetText)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }

            Text("\(Int(bucket.utilization))%")
                .font(compact ? .callout : .title3)
                .fontWeight(.semibold)
                .monospacedDigit()

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(Color.primary.opacity(0.08))
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(barColor)
                        .frame(width: max(0, geo.size.width * min(pct, 1.0)))
                }
            }
            .frame(height: compact ? 4 : 5)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(8)
    }
}

// MARK: - Enterprise Credit Card (hero)

struct EnterpriseCreditCard: View {
    let extra: ExtraUsage
    var creditProjection: CreditBurnProjection?
    @AppStorage("enterpriseShowPct") private var showPercentage = false

    private var hasLimit: Bool {
        extra.monthlyLimit != nil && extra.monthlyLimit! > 0
    }

    private var spendPct: Double {
        guard let used = extra.usedCredits, let limit = extra.monthlyLimit, limit > 0 else { return 0 }
        return used / limit
    }

    private var barColor: Color {
        let pct = spendPct * 100
        switch pct {
        case 0..<50: return Color(.systemGreen)
        case 50..<80: return Color(.systemOrange)
        default: return Color(.systemRed)
        }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Monthly Spend")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if hasLimit {
                    // Toggle between $ and % display
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
                    .help(showPercentage ? "Show as percentage" : "Show as dollars")
                }
            }

            if hasLimit && showPercentage {
                // Percentage mode
                Text("\(Int(spendPct * 100))%")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .monospacedDigit()

                if let limit = extra.monthlyLimitAmount {
                    Text("of \(formatUSD(limit)) limit")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            } else {
                // Dollar mode (default, or when no limit)
                if let used = extra.usedCreditsAmount {
                    Text(formatUSD(used))
                        .font(.title2)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }

                if let limit = extra.monthlyLimitAmount {
                    Text("of \(formatUSD(limit)) limit")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }

            // Progress bar only if there's a limit
            if hasLimit {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2.5)
                            .fill(Color.primary.opacity(0.08))
                        RoundedRectangle(cornerRadius: 2.5)
                            .fill(barColor)
                            .frame(width: max(0, geo.size.width * min(spendPct, 1.0)))
                    }
                }
                .frame(height: 5)
            }

            if let projection = creditProjection, let date = projection.projectedExhaustionDate {
                Text("~\(formatUSD(projection.burnRatePerDay))/day \u{2022} exhausts \(date, format: .dateTime.month(.abbreviated).day())")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(8)
    }
}

// MARK: - Consumer Extra Usage Card (secondary)

struct ExtraUsageCard: View {
    let extra: ExtraUsage
    var creditProjection: CreditBurnProjection?

    private var pct: Double { (extra.utilization ?? 0) / 100.0 }

    private var barColor: Color {
        guard let utilization = extra.utilization else { return Color(.systemOrange) }
        switch utilization {
        case 0..<50: return Color(.systemGreen)
        case 50..<80: return Color(.systemOrange)
        default: return Color(.systemRed)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Extra Usage")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let used = extra.usedCreditsAmount, let limit = extra.monthlyLimitAmount {
                    Text("$\(used, specifier: "%.2f") / $\(limit, specifier: "%.2f")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if let utilization = extra.utilization {
                Text("\(Int(utilization))%")
                    .font(.callout)
                    .fontWeight(.semibold)
                    .monospacedDigit()

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2.5)
                            .fill(Color.primary.opacity(0.08))
                        RoundedRectangle(cornerRadius: 2.5)
                            .fill(barColor)
                            .frame(width: max(0, geo.size.width * min(pct, 1.0)))
                    }
                }
                .frame(height: 5)
            }

            if let projection = creditProjection, let date = projection.projectedExhaustionDate {
                Text("~$\(projection.burnRatePerDay, specifier: "%.0f")/day \u{2022} exhausts \(date, format: .dateTime.month(.abbreviated).day())")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(8)
    }
}
