import SwiftUI

// MARK: - Studio Token System (Aluminium / Rack Obsidian)

public enum DesignTokens {
    public static func canvas(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.043, green: 0.047, blue: 0.055) : Color(red: 0.961, green: 0.961, blue: 0.969)
    }

    public static func surface(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.082, green: 0.090, blue: 0.110) : Color.white
    }

    public static func surfaceElevated(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.114, green: 0.125, blue: 0.157) : Color(red: 0.933, green: 0.933, blue: 0.949)
    }

    public static func primaryText(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.949, green: 0.957, blue: 0.973) : Color(red: 0.067, green: 0.071, blue: 0.082)
    }

    public static func secondaryText(_ scheme: ColorScheme, highContrast: Bool = false) -> Color {
        if highContrast {
            return primaryText(scheme).opacity(0.85)
        }
        return scheme == .dark ? Color(red: 0.608, green: 0.639, blue: 0.706) : Color(red: 0.322, green: 0.345, blue: 0.400)
    }

    public static func hairBorder(_ scheme: ColorScheme, highContrast: Bool = false) -> Color {
        if highContrast {
            return scheme == .dark ? Color.white.opacity(0.32) : Color.black.opacity(0.28)
        }
        return scheme == .dark ? Color.white.opacity(0.11) : Color.black.opacity(0.09)
    }

    /// Teal technique à contraste WCAG AA vérifié (> 6.4:1 en clair, > 10:1 en sombre).
    public static func signalTeal(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.220, green: 0.824, blue: 0.910) : Color(red: 0.000, green: 0.400, blue: 0.467)
    }

    public static func nominal(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.239, green: 0.839, blue: 0.549) : Color(red: 0.078, green: 0.424, blue: 0.263)
    }

    public static func caution(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.961, green: 0.651, blue: 0.137) : Color(red: 0.561, green: 0.322, blue: 0.000)
    }

    public static func critical(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 1.000, green: 0.420, blue: 0.420) : Color(red: 0.769, green: 0.137, blue: 0.137)
    }
}

// MARK: - Content Surface Card (Opaque Rack Surface — zero glass in content layer)

/// Conteneur structuré de la couche de contenu, conforme à `liquid-glass.md`
/// (aucun matériau verre dans les cartes ou rangées de liste).
public struct GlassCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    private let padding: CGFloat
    private let cornerRadius: CGFloat
    private let elevated: Bool
    private let content: Content

    public init(
        padding: CGFloat = 16,
        cornerRadius: CGFloat = 16,
        elevated: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.elevated = elevated
        self.content = content()
    }

    private var isHighContrast: Bool {
        contrast == .increased
    }

    public var body: some View {
        content
            .padding(padding)
            .background(
                elevated ? DesignTokens.surfaceElevated(colorScheme) : DesignTokens.surface(colorScheme),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        DesignTokens.hairBorder(colorScheme, highContrast: isHighContrast),
                        lineWidth: isHighContrast ? 1.5 : 1
                    )
            )
    }
}

/// Fond plein opaque haute précision sans dégradé parasite (`liquid-glass.md`).
public struct AmbientBackgroundView: View {
    @Environment(\.colorScheme) private var colorScheme

    public init() {}

    public var body: some View {
        DesignTokens.canvas(colorScheme)
            .ignoresSafeArea()
    }
}

// MARK: - Accessible Status Badge (Never color alone)

public struct StatusPill: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    public let title: String
    public let color: Color
    public let systemImage: String

    public init(_ title: String, color: Color, systemImage: String = "circle.fill") {
        self.title = title
        self.color = color
        self.systemImage = systemImage
    }

    public var body: some View {
        Label {
            Text(title)
                .font(.caption.weight(.semibold))
        } icon: {
            Image(systemName: systemImage)
                .font(.caption2.weight(.bold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(color.opacity(colorScheme == .dark ? 0.16 : 0.10), in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(color.opacity(contrast == .increased ? 0.70 : 0.30), lineWidth: 1)
        )
    }
}

// MARK: - Signature Component : Baie Télémétrique Rack 2U

/// Élément signature identitaire de PVE Center : représente le châssis matériel
/// des ressources actives (LXC/VM) et disques physiques en typographie tabulaire `SF Mono`.
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

        GlassCard(padding: 16, cornerRadius: 18) {
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

                // Tiroirs Machines (LXC / VM)
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
                            .frame(minHeight: 28)
                        }
                        .buttonStyle(.plain)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 6)], spacing: 6) {
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
                                    DesignTokens.surfaceElevated(colorScheme),
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                )
                                .accessibilityLabel("\(res.type.badgeLabel) \(res.vmid) \(res.name), \(res.isRunning ? "en ligne" : "arrêté")")
                            }
                        }
                    }
                }

                // Tiroirs Disques Physiques (S.M.A.R.T.)
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
                            .frame(minHeight: 28)
                        }
                        .buttonStyle(.plain)

                        HStack(spacing: 6) {
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
                                    DesignTokens.surfaceElevated(colorScheme),
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
                    .fill(DesignTokens.primaryText(colorScheme).opacity(0.11))
                Capsule()
                    .fill(resolvedColor)
                    .frame(width: max(4, geo.size.width * (percentage / 100)))
            }
        }
        .frame(height: 6)
        .accessibilityValue("\(Int(percentage)) pourcent")
    }
}

/// Toast appartenant à la couche fonctionnelle flottante (matériau régulier avec repli Reduce Transparency).
public struct ToastOverlayView: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    public let toast: ToastMessage

    public init(toast: ToastMessage) {
        self.toast = toast
    }

    public var body: some View {
        let iconColor = toast.isError ? DesignTokens.critical(colorScheme) : DesignTokens.nominal(colorScheme)
        HStack(spacing: 10) {
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
        .background {
            if reduceTransparency {
                Capsule().fill(DesignTokens.surface(colorScheme))
            } else {
                Capsule().fill(.regularMaterial)
            }
        }
        .overlay(
            Capsule()
                .strokeBorder(DesignTokens.hairBorder(colorScheme, highContrast: reduceTransparency), lineWidth: 1)
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.45 : 0.12), radius: 14, y: 6)
        .padding(.horizontal, 20)
    }
}
