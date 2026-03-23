import SwiftUI
import ClaudeUsageCore

struct MenuBarLabel: View {
    @ObservedObject var viewModel: UsageViewModel
    @AppStorage("enterpriseShowPct") private var showPercentage = false
    @AppStorage("warningThreshold") private var warningThreshold = 50.0
    @AppStorage("criticalThreshold") private var criticalThreshold = 80.0
    @AppStorage("colorMode") private var colorMode = "traffic_light"

    private var pct: Double {
        if viewModel.isEnterprise {
            let extra = viewModel.usage?.extraUsage
            guard let used = extra?.usedCredits, let limit = extra?.monthlyLimit, limit > 0 else { return 0 }
            return (used / limit) * 100
        }
        return viewModel.usage?.fiveHour?.utilization ?? 0
    }

    private var displayText: String {
        if viewModel.isEnterprise {
            if showPercentage {
                return "\(Int(pct))%"
            }
            guard let used = viewModel.usage?.extraUsage?.usedCreditsAmount else { return "--" }
            if used < 1 { return "$0" }
            return String(format: "$%.0f", used)
        }
        return viewModel.menuBarText
    }

    private var ringColor: Color {
        if colorMode == "single_color" {
            // Teal gradient: lighter at low usage, darker at high
            return Color(.systemTeal).opacity(0.4 + (pct / 100.0) * 0.6)
        }
        // Traffic light mode
        switch pct {
        case 0..<warningThreshold: return Color(.systemGreen)
        case warningThreshold..<criticalThreshold: return Color(.systemOrange)
        default: return Color(.systemRed)
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.2), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: min(pct / 100.0, 1.0))
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 12, height: 12)

            Text(displayText)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
        }
    }
}
