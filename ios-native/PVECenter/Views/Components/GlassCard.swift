import SwiftUI

// MARK: - Studio Dark & Luminous Palette for Apple Liquid Glass (.glassEffect)

public enum DesignTokens {
    public static func canvas(_ scheme: ColorScheme) -> Color {
        Color(red: 0.020, green: 0.031, blue: 0.067)
    }

    public static func surface(_ scheme: ColorScheme) -> Color {
        Color(red: 0.075, green: 0.094, blue: 0.145)
    }

    public static func surfaceElevated(_ scheme: ColorScheme) -> Color {
        Color.white.opacity(0.065)
    }

    public static func primaryText(_ scheme: ColorScheme) -> Color {
        Color(red: 0.949, green: 0.957, blue: 0.973)
    }

    public static func secondaryText(_ scheme: ColorScheme, highContrast: Bool = false) -> Color {
        if highContrast {
            return primaryText(scheme).opacity(0.88)
        }
        return Color(red: 0.620, green: 0.667, blue: 0.753)
    }

    public static func hairBorder(_ scheme: ColorScheme, highContrast: Bool = false) -> Color {
        Color.white.opacity(highContrast ? 0.34 : 0.14)
    }

    public static func signalTeal(_ scheme: ColorScheme) -> Color {
        Color(red: 0.220, green: 0.824, blue: 0.910)
    }

    public static func nominal(_ scheme: ColorScheme) -> Color {
        Color(red: 0.239, green: 0.839, blue: 0.549)
    }

    public static func caution(_ scheme: ColorScheme) -> Color {
        Color(red: 0.961, green: 0.651, blue: 0.137)
    }

    public static func critical(_ scheme: ColorScheme) -> Color {
        Color(red: 1.000, green: 0.420, blue: 0.420)
    }
}

// MARK: - Native Apple Liquid Glass Panel Container (`macOS 26` / `iOS 26`)

public struct GlassCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private let padding: CGFloat
    private let cornerRadius: CGFloat
    private let elevated: Bool
    private let content: Content

    public init(
        padding: CGFloat = 16,
        cornerRadius: CGFloat = 20,
        elevated: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.elevated = elevated
        self.content = content()
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if reduceTransparency {
            content
                .padding(padding)
                .background(DesignTokens.surface(colorScheme), in: shape)
                .overlay(
                    shape.strokeBorder(
                        DesignTokens.hairBorder(colorScheme, highContrast: contrast == .increased),
                        lineWidth: 1.5
                    )
                )
        } else {
            content
                .padding(padding)
                .background(Color.white.opacity(elevated ? 0.05 : 0.025), in: shape)
                .glassEffect(.regular, in: shape)
                .overlay(
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.24),
                                Color.white.opacity(0.06),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.85
                    )
                )
        }
    }
}

/// Arrière-plan atmosphérique profond permettant aux surfaces Liquid Glass
/// de réfracter naturellement lumière et couleur sans jamais masquer le contenu.
public struct AmbientBackgroundView: View {
    public init() {}

    public var body: some View {
        ZStack {
            Color(red: 0.020, green: 0.031, blue: 0.067)

            RadialGradient(
                colors: [
                    Color(red: 0.055, green: 0.647, blue: 0.914).opacity(0.22),
                    Color.clear,
                ],
                center: .topLeading,
                startRadius: 20,
                endRadius: 560
            )

            RadialGradient(
                colors: [
                    Color(red: 0.388, green: 0.400, blue: 0.945).opacity(0.20),
                    Color.clear,
                ],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 520
            )

            RadialGradient(
                colors: [
                    Color(red: 0.063, green: 0.725, blue: 0.506).opacity(0.10),
                    Color.clear,
                ],
                center: .bottom,
                startRadius: 20,
                endRadius: 480
            )
        }
        .ignoresSafeArea()
    }
}

// MARK: - Native Liquid Glass Status Pill

public struct StatusPill: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    public let title: String
    public let color: Color
    public let systemImage: String

    public init(_ title: String, color: Color, systemImage: String = "circle.fill") {
        self.title = title
        self.color = color
        self.systemImage = systemImage
    }

    public var body: some View {
        let base = Label {
            Text(title)
                .font(.caption.weight(.semibold))
        } icon: {
            Image(systemName: systemImage)
                .font(.caption2.weight(.bold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)

        if reduceTransparency {
            base
                .background(color.opacity(0.18), in: Capsule())
                .overlay(Capsule().strokeBorder(color.opacity(0.45), lineWidth: 1))
        } else {
            base
                .background(color.opacity(0.14), in: Capsule())
                .glassEffect(.regular, in: Capsule())
                .overlay(Capsule().strokeBorder(color.opacity(0.32), lineWidth: 0.75))
        }
    }
}

// MARK: - Signature Component : Baie Télémétrique Rack 2U

public struct RackBayMatrixView: View {
    @Environment(\.colorScheme) private var colorScheme
    public let node: NodeSummary
    public let resources: [PveResource]
    public let drives: [PhysicalDriveInfo]
    public let onSelectMachines: () -> Void
    public let onSelectStorage: () -> Void

    public init(
        node: NodeSummary,
        resources: [PveResource],
        drives: [PhysicalDriveInfo],
        onSelectMachines: @escaping () -> Void,
        onSelectStorage: @escaping () -> Void
    ) {
        self.node = node
        self.resources = resources
        self.drives = drives
        self.onSelectMachines = onSelectMachines
        self.onSelectStorage = onSelectStorage
    }

    public var body: some View {
        let teal = DesignTokens.signalTeal(colorScheme)
        let nominal = DesignTokens.nominal(colorScheme)
        let caution = DesignTokens.caution(colorScheme)
        let critical = DesignTokens.critical(colorScheme)

        GlassCard(padding: 16, cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("BAIE PROXMOX • \(node.name.uppercased())")
                            .font(.system(.caption, design: .monospaced, weight: .bold))
                            .foregroundStyle(teal)
                        Text("PVE \(node.pveVersion) • Uptime \(node.uptimeHuman)")
                            .font(.caption)
                            .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                    }
                    Spacer()
                    StatusPill("Nominal", color: nominal, systemImage: "checkmark.circle.fill")
                }

                if !resources.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Button(action: onSelectMachines) {
                            HStack {
                                Text("NŒUDS & CONTENEURS (\(resources.filter(\.isRunning).count)/\(resources.count))")
                                    .font(.system(.caption2, design: .monospaced, weight: .semibold))
                                    .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                            }
                            .frame(minHeight: 26)
                        }
                        .buttonStyle(.plain)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 6)], spacing: 6) {
                            ForEach(resources) { res in
                                HStack(spacing: 5) {
                                    Image(systemName: res.isRunning ? "power.circle.fill" : "pause.circle")
                                        .font(.caption2)
                                        .foregroundStyle(res.isRunning ? nominal : DesignTokens.secondaryText(colorScheme))
                                    Text("#\(res.vmid)")
                                        .font(.system(.caption2, design: .monospaced, weight: .semibold))
                                        .foregroundStyle(DesignTokens.primaryText(colorScheme))
                                    Spacer(minLength: 0)
                                    Text(res.type.badgeLabel)
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(
                                    Color.white.opacity(0.06),
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                )
                                .accessibilityLabel("\(res.type.badgeLabel) \(res.vmid) \(res.name), \(res.isRunning ? "en ligne" : "arrêté")")
                            }
                        }
                    }
                }

                if !drives.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Button(action: onSelectStorage) {
                            HStack {
                                Text("BAIES DISQUES (\(drives.count) MONTÉS)")
                                    .font(.system(.caption2, design: .monospaced, weight: .semibold))
                                    .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                            }
                            .frame(minHeight: 26)
                        }
                        .buttonStyle(.plain)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 6)], spacing: 6) {
                            ForEach(Array(drives.enumerated()), id: \.element.id) { idx, drive in
                                let bayColor: Color = !drive.isHealthy
                                    ? critical
                                    : (drive.usedPct >= 85 ? caution : teal)
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 4) {
                                        Image(systemName: drive.isHealthy ? "internaldrive.fill" : "exclamationmark.triangle.fill")
                                            .font(.caption2)
                                            .foregroundStyle(bayColor)
                                        Text(String(format: "B%02d", idx + 1))
                                            .font(.system(.caption2, design: .monospaced, weight: .bold))
                                            .foregroundStyle(DesignTokens.primaryText(colorScheme))
                                    }
                                    UsageProgressBar(percentage: drive.usedPct, tint: bayColor)
                                    Text(String(format: "%.0f %%", drive.usedPct))
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                                }
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    Color.white.opacity(0.06),
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                )
                                .accessibilityLabel("Baie \(idx + 1) \(drive.label), utilisé à \(Int(drive.usedPct)) pourcent, SMART \(drive.health)")
                            }
                        }
                    }
                }
            }
        }
    }
}

public struct UsageProgressBar: View {
    @Environment(\.colorScheme) private var colorScheme
    public let percentage: Double
    public var tint: Color?

    public init(percentage: Double, tint: Color? = nil) {
        self.percentage = max(0, min(100, percentage))
        self.tint = tint
    }

    private var resolvedColor: Color {
        if let tint { return tint }
        if percentage >= 90 { return DesignTokens.critical(colorScheme) }
        if percentage >= 75 { return DesignTokens.caution(colorScheme) }
        return DesignTokens.signalTeal(colorScheme)
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.12))
                Capsule()
                    .fill(resolvedColor.gradient)
                    .frame(width: max(4, geo.size.width * (percentage / 100)))
            }
        }
        .frame(height: 6)
        .accessibilityValue("\(Int(percentage)) pourcent")
    }
}

public struct ToastOverlayView: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    public let toast: ToastMessage

    public init(toast: ToastMessage) {
        self.toast = toast
    }

    public var body: some View {
        let iconColor = toast.isError ? DesignTokens.critical(colorScheme) : DesignTokens.nominal(colorScheme)
        let label = HStack(spacing: 10) {
            Image(systemName: toast.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(iconColor)
                .font(.body.weight(.semibold))
            Text(toast.text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(DesignTokens.primaryText(colorScheme))
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)

        if reduceTransparency {
            label
                .background(DesignTokens.surface(colorScheme), in: Capsule())
                .overlay(Capsule().strokeBorder(DesignTokens.hairBorder(colorScheme, highContrast: true), lineWidth: 1.5))
                .padding(.horizontal, 20)
        } else {
            label
                .glassEffect(.regular, in: Capsule())
                .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
                .padding(.horizontal, 20)
        }
    }
}
