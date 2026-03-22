import SwiftUI
import ClaudeUsageCore

struct MenuBarLabel: View {
    @ObservedObject var viewModel: UsageViewModel

    private var pct: Double {
        if viewModel.isEnterprise {
            let extra = viewModel.usage?.extraUsage
            guard let used = extra?.usedCredits, let limit = extra?.monthlyLimit, limit > 0 else { return 0 }
            return (used / limit) * 100
        }
        return viewModel.usage?.fiveHour?.utilization ?? 0
    }

    private var ringColor: Color {
        switch pct {
        case 0..<50: return Color(.systemGreen)
        case 50..<80: return Color(.systemOrange)
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

            Text(viewModel.menuBarText)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
        }
    }
}
