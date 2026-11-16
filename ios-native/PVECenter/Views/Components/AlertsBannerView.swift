import SwiftUI

public struct AlertsBannerView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    public let alerts: [SmartAlert]
    public let onSelectTab: (AppTab) -> Void
    @State private var isExpanded: Bool = true

    public init(alerts: [SmartAlert], onSelectTab: @escaping (AppTab) -> Void) {
        self.alerts = alerts
        self.onSelectTab = onSelectTab
    }

    private func color(for severity: SmartAlert.Severity) -> Color {
        switch severity {
        case .critical: DesignTokens.critical(colorScheme)
        case .warning: DesignTokens.caution(colorScheme)
        case .info: DesignTokens.signalTeal(colorScheme)
        }
    }

    private func icon(for severity: SmartAlert.Severity) -> String {
        switch severity {
        case .critical: "exclamationmark.octagon.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .info: "info.circle.fill"
        }
    }

    public var body: some View {
        if !alerts.isEmpty {
            let topSeverity = alerts.first(where: { $0.severity == .critical })?.severity
                ?? alerts.first(where: { $0.severity == .warning })?.severity
                ?? .info
            let accent = color(for: topSeverity)

            GlassCard(padding: 14, cornerRadius: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        if reduceMotion {
                            isExpanded.toggle()
                        } else {
                            withAnimation(.spring(response: 0.30, dampingFraction: 0.85)) {
                                isExpanded.toggle()
                            }
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: icon(for: topSeverity))
                                .font(.body.weight(.semibold))
                                .foregroundStyle(accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(alerts.count) point\(alerts.count > 1 ? "s" : "") d'attention")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(DesignTokens.primaryText(colorScheme))
                                if !isExpanded, let first = alerts.first {
                                    Text(first.title)
                                        .font(.caption)
                                        .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                                }
                            }
                            Spacer()
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                        }
                        .frame(minHeight: 36)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if isExpanded {
                        VStack(spacing: 8) {
                            ForEach(alerts) { alert in
                                let alertColor = color(for: alert.severity)
                                Button {
                                    onSelectTab(alert.targetTab)
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: icon(for: alert.severity))
                                            .font(.subheadline)
                                            .foregroundStyle(alertColor)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(alert.title)
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(DesignTokens.primaryText(colorScheme))
                                            Text(alert.subtitle)
                                                .font(.caption2)
                                                .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                                                .lineLimit(2)
                                        }
                                        Spacer()
                                        Image(systemName: "arrow.right")
                                            .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                                            .font(.caption.weight(.semibold))
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .frame(minHeight: 44)
                                    .background(
                                        DesignTokens.surfaceElevated(colorScheme),
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }
}
