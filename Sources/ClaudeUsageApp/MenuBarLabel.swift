import SwiftUI
import ClaudeUsageCore

struct MenuBarLabel: View {
    @ObservedObject var viewModel: UsageViewModel
    @AppStorage("enterpriseShowPct") private var showPercentage = false
    @AppStorage("warningThreshold") private var warningThreshold = 50.0
    @AppStorage("criticalThreshold") private var criticalThreshold = 80.0
    @AppStorage("colorMode") private var colorMode = "traffic_light"
    @AppStorage("menuBarLayout") private var menuBarLayout = MenuBarLayoutOption.fiveHourOnly.rawValue

    var body: some View {
        if viewModel.isEnterprise {
            enterpriseLabel
        } else {
            consumerLabel
        }
    }

    private var consumerLabel: some View {
        let primary = MenuBarMetrics.consumerPrimaryPercent(from: viewModel.usage)
        let secondary = MenuBarMetrics.consumerSecondaryPercent(from: viewModel.usage)
        return HStack(spacing: 2) {
            percentText(primary)
            if menuBarLayout == MenuBarLayoutOption.dual.rawValue {
                Text("·")
                    .foregroundStyle(.secondary)
                percentText(secondary)
            }
        }
        .font(.system(size: 11, weight: .medium, design: .rounded))
        .monospacedDigit()
    }

    @ViewBuilder
    private func percentText(_ value: Int?) -> some View {
        if let value {
            Text("\(value)%")
                .foregroundStyle(color(for: Double(value)))
        } else {
            Text("--")
                .foregroundStyle(.secondary)
        }
    }

    private func color(for percent: Double) -> Color {
        switch MenuBarMetrics.thresholdColor(
            for: percent,
            warning: warningThreshold,
            critical: criticalThreshold,
            colorMode: colorMode
        ) {
        case .ok: return Color(.systemGreen)
        case .warning: return Color(.systemOrange)
        case .critical: return Color(.systemRed)
        case .tealScale(let opacity): return Color(.systemTeal).opacity(opacity)
        }
    }

    private var enterpriseLabel: some View {
        HStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.2), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: min(enterprisePct / 100.0, 1.0))
                    .stroke(color(for: enterprisePct), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 12, height: 12)

            Text(enterpriseDisplayText)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
        }
    }

    private var enterprisePct: Double {
        let extra = viewModel.usage?.extraUsage
        guard let used = extra?.usedCredits, let limit = extra?.monthlyLimit, limit > 0 else { return 0 }
        return (used / limit) * 100
    }

    private var enterpriseDisplayText: String {
        if showPercentage {
            return "\(Int(enterprisePct))%"
        }
        guard let used = viewModel.usage?.extraUsage?.usedCreditsAmount else { return "--" }
        if used < 1 { return "$0" }
        return String(format: "$%.0f", used)
    }
}
