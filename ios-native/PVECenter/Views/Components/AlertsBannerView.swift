import SwiftUI

public struct AlertsBannerView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    public let alerts: [SmartAlert]
    public let onSelectTab: (AppTab) -> Void
    @State private var isExpanded: Bool = true

    public init(alerts: [SmartAlert], onSelectTab: @escaping (AppTab) -> Void) {
        self.alerts = alerts
        self.onSelectTab = onSelectTab
    }

    private var subtitleColor: Color {
        #if os(tvOS)
        return DesignTokens.secondaryText(colorScheme, highContrast: true)
        #else
        return DesignTokens.secondaryText(colorScheme, highContrast: contrast == .increased)
        #endif
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
                                    .lineLimit(1)
                                    .multilineTextAlignment(.leading)
                                if !isExpanded, let first = alerts.first {
                                    Text(first.title)
                                        .font(.caption)
                                        .foregroundStyle(subtitleColor)
                                        .lineLimit(1)
                                        .multilineTextAlignment(.leading)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(subtitleColor)
                        }
                        #if os(tvOS)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        #endif
                        .frame(minHeight: 36)
                        .contentShape(Rectangle())
                    }
                    .cardButtonStyle(cornerRadius: 12)

                    if isExpanded {
                        #if os(tvOS)
                        let rowSpacing: CGFloat = 10
                        let hSpacing: CGFloat = 14
                        let hPadding: CGFloat = 16
                        let vPadding: CGFloat = 12
                        let rowMinHeight: CGFloat = 54
                        #else
                        let rowSpacing: CGFloat = 8
                        let hSpacing: CGFloat = 10
                        let hPadding: CGFloat = 12
                        let vPadding: CGFloat = 10
                        let rowMinHeight: CGFloat = 44
                        #endif

                        VStack(spacing: rowSpacing) {
                            ForEach(alerts) { alert in
                                let alertColor = color(for: alert.severity)
                                Button {
                                    onSelectTab(alert.targetTab)
                                } label: {
                                    HStack(spacing: hSpacing) {
                                        Image(systemName: icon(for: alert.severity))
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(alertColor)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(alert.title)
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(DesignTokens.primaryText(colorScheme))
                                                .lineLimit(2)
                                                .multilineTextAlignment(.leading)
                                                .fixedSize(horizontal: false, vertical: true)
                                            Text(alert.subtitle)
                                                .font(.caption2)
                                                .foregroundStyle(subtitleColor)
                                                .lineLimit(2)
                                                .multilineTextAlignment(.leading)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        Image(systemName: "arrow.right")
                                            .foregroundStyle(subtitleColor)
                                            .font(.caption.weight(.semibold))
                                    }
                                    .padding(.horizontal, hPadding)
                                    .padding(.vertical, vPadding)
                                    .frame(minHeight: rowMinHeight)
                                    .background(
                                        DesignTokens.surfaceElevated(colorScheme),
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    )
                                }
                                .cardButtonStyle(cornerRadius: 12)
                            }
                        }
                    }
                }
            }
        }
    }
}
