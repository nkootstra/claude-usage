import SwiftUI
import ClaudeUsageCore

struct FloatingWidgetView: View {
    @ObservedObject var viewModel: UsageViewModel
    @AppStorage("warningThreshold") private var warningThreshold = 50.0
    @AppStorage("criticalThreshold") private var criticalThreshold = 80.0
    @AppStorage("enterpriseShowPct") private var showPercentage = false
    @State private var isHovering = false

    var onClose: (() -> Void)?

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
        switch pct {
        case 0..<warningThreshold: return Color(.systemGreen)
        case warningThreshold..<criticalThreshold: return Color(.systemOrange)
        default: return Color(.systemRed)
        }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.15), lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: min(pct / 100.0, 1.0))
                        .stroke(ringColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 32, height: 32)

                Text(displayText)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }
            .padding(10)

            if isHovering {
                Button {
                    onClose?()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .padding(4)
            }
        }
        .frame(width: 60, height: 60)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .onHover { isHovering = $0 }
    }
}
