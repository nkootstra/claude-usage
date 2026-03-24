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
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.12), lineWidth: 3.5)
            Circle()
                .trim(from: 0, to: min(pct / 100.0, 1.0))
                .stroke(ringColor, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                .rotationEffect(.degrees(-90))

            Text(displayText)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .frame(width: 44, height: 44)
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .preferredColorScheme(.dark)
        .padding(10) // extra space for the close button to float in
        .overlay(alignment: .topTrailing) {
            if isHovering {
                Button {
                    onClose?()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .buttonStyle(.borderless)
                .padding(2)
            }
        }
        .onHover { isHovering = $0 }
    }
}
