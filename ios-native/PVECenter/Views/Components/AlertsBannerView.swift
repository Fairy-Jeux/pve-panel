import SwiftUI

public struct AlertsBannerView: View {
    public let alerts: [SmartAlert]
    public let onSelectTab: (AppTab) -> Void
    @State private var isExpanded: Bool = true

    public init(alerts: [SmartAlert], onSelectTab: @escaping (AppTab) -> Void) {
        self.alerts = alerts
        self.onSelectTab = onSelectTab
    }

    private func color(for severity: SmartAlert.Severity) -> Color {
        switch severity {
        case .critical: .red
        case .warning: .orange
        case .info: .cyan
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

            GlassCard(padding: 14, cornerRadius: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: icon(for: topSeverity))
                                .font(.body.weight(.semibold))
                                .foregroundStyle(accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(alerts.count) point\(alerts.count > 1 ? "s" : "") d'attention")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                if !isExpanded, let first = alerts.first {
                                    Text(first.title)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
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
                                        Circle()
                                            .fill(alertColor)
                                            .frame(width: 8, height: 8)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(alert.title)
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(.primary)
                                            Text(alert.subtitle)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                        Spacer()
                                        Image(systemName: "arrow.right.circle.fill")
                                            .foregroundStyle(alertColor.opacity(0.85))
                                            .font(.subheadline)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(alertColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
        }
    }
}
