import SwiftUI

// MARK: - Studio Dark & Luminous Palette for Apple Liquid Glass (.glassEffect)

public enum DesignTokens {
    public static func canvas(_ scheme: ColorScheme) -> Color {
        switch scheme {
        case .light:
            return Color(red: 0.945, green: 0.961, blue: 0.984)
        default:
            return Color(red: 0.020, green: 0.031, blue: 0.067)
        }
    }

    public static func surface(_ scheme: ColorScheme) -> Color {
        switch scheme {
        case .light:
            return Color(red: 0.992, green: 0.996, blue: 1.000)
        default:
            return Color(red: 0.075, green: 0.094, blue: 0.145)
        }
    }

    public static func surfaceElevated(_ scheme: ColorScheme) -> Color {
        switch scheme {
        case .light:
            return Color(red: 0.067, green: 0.110, blue: 0.212).opacity(0.055)
        default:
            return Color.white.opacity(0.065)
        }
    }

    public static func primaryText(_ scheme: ColorScheme) -> Color {
        switch scheme {
        case .light:
            return Color(red: 0.067, green: 0.098, blue: 0.173)
        default:
            return Color(red: 0.949, green: 0.957, blue: 0.973)
        }
    }

    public static func secondaryText(_ scheme: ColorScheme, highContrast: Bool = false) -> Color {
        if highContrast {
            return primaryText(scheme).opacity(0.88)
        }
        switch scheme {
        case .light:
            return Color(red: 0.275, green: 0.337, blue: 0.431)
        default:
            return Color(red: 0.620, green: 0.667, blue: 0.753)
        }
    }

    public static func hairBorder(_ scheme: ColorScheme, highContrast: Bool = false) -> Color {
        switch scheme {
        case .light:
            return Color(red: 0.067, green: 0.098, blue: 0.173).opacity(highContrast ? 0.28 : 0.10)
        default:
            return Color.white.opacity(highContrast ? 0.34 : 0.14)
        }
    }

    public static func signalTeal(_ scheme: ColorScheme) -> Color {
        switch scheme {
        case .light:
            return Color(red: 0.008, green: 0.486, blue: 0.592)
        default:
            return Color(red: 0.220, green: 0.824, blue: 0.910)
        }
    }

    public static func accent(_ theme: AccentTheme, _ scheme: ColorScheme) -> Color {
        switch theme {
        case .cyan:
            return signalTeal(scheme)
        case .cider:
            return scheme == .light
                ? Color(red: 0.855, green: 0.094, blue: 0.216)
                : Color(red: 0.980, green: 0.137, blue: 0.231)
        case .indigo:
            return scheme == .light
                ? Color(red: 0.310, green: 0.275, blue: 0.898)
                : Color(red: 0.498, green: 0.514, blue: 0.996)
        case .emerald:
            return nominal(scheme)
        case .amber:
            return caution(scheme)
        case .purple:
            return scheme == .light
                ? Color(red: 0.576, green: 0.200, blue: 0.918)
                : Color(red: 0.753, green: 0.518, blue: 0.988)
        }
    }

    public static func secondaryAccent(_ theme: AccentTheme, _ scheme: ColorScheme) -> Color {
        switch theme {
        case .cyan:
            return accent(.indigo, scheme)
        case .cider:
            return Color(red: 0.925, green: 0.282, blue: 0.600)
        case .indigo:
            return accent(.cyan, scheme)
        case .emerald:
            return accent(.cyan, scheme)
        case .amber:
            return Color(red: 0.937, green: 0.267, blue: 0.267)
        case .purple:
            return Color(red: 0.925, green: 0.282, blue: 0.600)
        }
    }

    public static func nominal(_ scheme: ColorScheme) -> Color {
        switch scheme {
        case .light:
            return Color(red: 0.039, green: 0.490, blue: 0.286)
        default:
            return Color(red: 0.239, green: 0.839, blue: 0.549)
        }
    }

    public static func caution(_ scheme: ColorScheme) -> Color {
        switch scheme {
        case .light:
            return Color(red: 0.690, green: 0.373, blue: 0.000)
        default:
            return Color(red: 0.961, green: 0.651, blue: 0.137)
        }
    }

    public static func critical(_ scheme: ColorScheme) -> Color {
        switch scheme {
        case .light:
            return Color(red: 0.776, green: 0.157, blue: 0.157)
        default:
            return Color(red: 1.000, green: 0.420, blue: 0.420)
        }
    }

    public static var pageHorizontalPadding: CGFloat {
        #if os(tvOS)
        return 48
        #else
        return 16
        #endif
    }

    public static var pageVerticalPadding: CGFloat {
        #if os(tvOS)
        return 24
        #else
        return 12
        #endif
    }
}

public extension View {
    @ViewBuilder
    func cardButtonStyle(cornerRadius: CGFloat = 16) -> some View {
        #if os(tvOS)
        self.buttonStyle(TVGlassCardButtonStyle(cornerRadius: cornerRadius))
        #else
        self.buttonStyle(.plain)
        #endif
    }

    @ViewBuilder
    func adaptiveSmallControlSize() -> some View {
        #if os(tvOS)
        self
        #else
        self.controlSize(.small)
        #endif
    }

    @ViewBuilder
    func adaptivePillButtonStyle(
        tint: Color? = nil,
        prominent: Bool = false,
        cornerRadius: CGFloat? = nil
    ) -> some View {
        #if os(tvOS)
        self.buttonStyle(
            TVGlassPillButtonStyle(
                tint: tint,
                prominent: prominent,
                cornerRadius: cornerRadius
            )
        )
        #else
        if prominent {
            if let tint {
                self.buttonStyle(.glassProminent).tint(tint)
            } else {
                self.buttonStyle(.glassProminent)
            }
        } else {
            if let tint {
                self.buttonStyle(.glass).tint(tint)
            } else {
                self.buttonStyle(.glass)
            }
        }
        #endif
    }

    @ViewBuilder
    func adaptiveIconTileButtonStyle(
        isSelected: Bool,
        accent: Color,
        cornerRadius: CGFloat = 12
    ) -> some View {
        #if os(tvOS)
        self.buttonStyle(
            TVIconTileButtonStyle(
                isSelected: isSelected,
                accent: accent,
                cornerRadius: cornerRadius
            )
        )
        #else
        self.buttonStyle(.plain)
        #endif
    }

    @ViewBuilder
    func adaptiveTVOSModalFormContainer(maxWidth: CGFloat = 1160) -> some View {
        #if os(tvOS)
        self
            .frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { AmbientBackgroundView() }
        #else
        self.formStyle(.grouped)
        #endif
    }
}

#if os(tvOS)
/// Custom dark-glass focus style replacing tvOS `.buttonStyle(.card)` so card
/// buttons keep deep dark contrast and show a luminous cyan focus ring.
public struct TVGlassCardButtonStyle: ButtonStyle {
    public var cornerRadius: CGFloat

    public init(cornerRadius: CGFloat = 16) {
        self.cornerRadius = cornerRadius
    }

    public func makeBody(configuration: Configuration) -> some View {
        TVGlassCardButtonBody(
            configuration: configuration,
            cornerRadius: cornerRadius
        )
    }
}

private struct TVGlassCardButtonBody: View {
    @Environment(\.isFocused) private var isFocused
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let configuration: ButtonStyleConfiguration
    let cornerRadius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let teal = DesignTokens.signalTeal(colorScheme)
        let fillColor: Color = reduceTransparency
            ? (isFocused ? Color(red: 0.082, green: 0.118, blue: 0.196) : DesignTokens.surface(colorScheme))
            : (isFocused
                ? Color(red: 0.055, green: 0.095, blue: 0.175).opacity(0.92)
                : Color(red: 0.038, green: 0.056, blue: 0.106).opacity(0.76))

        configuration.label
            .background(shape.fill(fillColor))
            .overlay(
                shape.strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.22),
                            Color.white.opacity(0.06),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
                .opacity(isFocused ? 0 : 1)
            )
            .overlay(
                shape.strokeBorder(teal, lineWidth: 3)
                    .opacity(isFocused ? 1 : 0)
            )
            .contentShape(shape)
            .shadow(
                color: isFocused ? teal.opacity(0.45) : .clear,
                radius: isFocused ? 14 : 0,
                x: 0,
                y: isFocused ? 4 : 0
            )
            .scaleEffect(configuration.isPressed ? 0.985 : (isFocused ? 1.02 : 1.0))
            .animation(
                reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.82),
                value: isFocused
            )
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.12),
                value: configuration.isPressed
            )
    }
}

/// High-contrast dark-glass pill button style for tvOS actions so focus never
/// washes colored labels into white-on-white.
public struct TVGlassPillButtonStyle: ButtonStyle {
    public var tint: Color?
    public var prominent: Bool
    public var cornerRadius: CGFloat?

    public init(tint: Color? = nil, prominent: Bool = false, cornerRadius: CGFloat? = nil) {
        self.tint = tint
        self.prominent = prominent
        self.cornerRadius = cornerRadius
    }

    public func makeBody(configuration: Configuration) -> some View {
        TVGlassPillButtonBody(
            configuration: configuration,
            tint: tint,
            prominent: prominent,
            cornerRadius: cornerRadius
        )
    }
}

private struct TVGlassPillButtonBody: View {
    @Environment(\.isFocused) private var isFocused
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let configuration: ButtonStyleConfiguration
    let tint: Color?
    let prominent: Bool
    let cornerRadius: CGFloat?

    var body: some View {
        let resolvedTint = tint ?? DesignTokens.signalTeal(colorScheme)
        let shape = RoundedRectangle(cornerRadius: cornerRadius ?? 999, style: .continuous)

        let restFill: Color = prominent
            ? resolvedTint.opacity(reduceTransparency ? 0.42 : 0.30)
            : Color.white.opacity(reduceTransparency ? 0.14 : 0.085)
        let focusFill: Color = prominent
            ? resolvedTint.opacity(0.88)
            : resolvedTint.opacity(0.32)
        let restForeground: Color = prominent ? .white : (tint ?? Color.white.opacity(0.94))
        let restBorder: Color = prominent ? resolvedTint.opacity(0.65) : Color.white.opacity(0.20)
        let focusBorder: Color = prominent ? Color.white.opacity(0.85) : resolvedTint

        configuration.label
            .foregroundStyle(isFocused ? Color.white : restForeground)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(
                ZStack {
                    shape.fill(Color(red: 0.04, green: 0.06, blue: 0.12).opacity(0.92))
                    shape.fill(isFocused ? focusFill : restFill)
                }
            )
            .overlay(
                shape.strokeBorder(
                    isFocused ? focusBorder : restBorder,
                    lineWidth: isFocused ? 2.5 : 1
                )
            )
            .contentShape(shape)
            .shadow(
                color: isFocused ? resolvedTint.opacity(0.45) : .clear,
                radius: isFocused ? 12 : 0,
                x: 0,
                y: isFocused ? 4 : 0
            )
            .scaleEffect(configuration.isPressed ? 0.96 : (isFocused ? 1.04 : 1.0))
            .animation(
                reduceMotion ? nil : .spring(response: 0.20, dampingFraction: 0.82),
                value: isFocused
            )
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.10),
                value: configuration.isPressed
            )
    }
}

/// Focusable tile style for tvOS icon grids and theme swatch selectors.
public struct TVIconTileButtonStyle: ButtonStyle {
    public var isSelected: Bool
    public var accent: Color
    public var cornerRadius: CGFloat

    public init(isSelected: Bool, accent: Color, cornerRadius: CGFloat = 12) {
        self.isSelected = isSelected
        self.accent = accent
        self.cornerRadius = cornerRadius
    }

    public func makeBody(configuration: Configuration) -> some View {
        TVIconTileButtonBody(
            configuration: configuration,
            isSelected: isSelected,
            accent: accent,
            cornerRadius: cornerRadius
        )
    }
}

private struct TVIconTileButtonBody: View {
    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let configuration: ButtonStyleConfiguration
    let isSelected: Bool
    let accent: Color
    let cornerRadius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        configuration.label
            .background(
                shape.fill(
                    isFocused
                        ? accent.opacity(isSelected ? 0.36 : 0.24)
                        : (isSelected ? accent.opacity(0.20) : Color.white.opacity(0.06))
                )
            )
            .overlay(
                shape.strokeBorder(
                    isFocused ? accent : (isSelected ? accent.opacity(0.85) : Color.white.opacity(0.14)),
                    lineWidth: isFocused ? 3 : (isSelected ? 1.75 : 1)
                )
            )
            .contentShape(shape)
            .shadow(
                color: isFocused ? accent.opacity(0.50) : .clear,
                radius: isFocused ? 10 : 0,
                x: 0,
                y: isFocused ? 3 : 0
            )
            .scaleEffect(configuration.isPressed ? 0.95 : (isFocused ? 1.06 : 1.0))
            .animation(
                reduceMotion ? nil : .spring(response: 0.20, dampingFraction: 0.82),
                value: isFocused
            )
    }
}
#endif

// MARK: - Native Apple Liquid Glass Panel Container (`macOS 26` / `iOS 26`)

public struct GlassCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private let padding: CGFloat
    private let cornerRadius: CGFloat
    private let elevated: Bool
    private let interactive: Bool
    private let content: Content

    public init(
        padding: CGFloat = 16,
        cornerRadius: CGFloat = 20,
        elevated: Bool = false,
        interactive: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.elevated = elevated
        self.interactive = interactive
        self.content = content()
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        #if os(tvOS)
        if interactive {
            // TVGlassCardButtonStyle already draws surface, specular stroke, and focus halo.
            content
                .padding(padding)
        } else {
            let fill = reduceTransparency
                ? DesignTokens.surface(colorScheme)
                : Color(red: 0.042, green: 0.062, blue: 0.118).opacity(elevated ? 0.90 : 0.78)
            content
                .padding(padding)
                .background(shape.fill(fill))
                .overlay(
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(elevated ? 0.24 : 0.18),
                                Color.white.opacity(0.05),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                )
                .shadow(
                    color: Color.black.opacity(elevated ? 0.36 : 0.22),
                    radius: elevated ? 16 : 10,
                    x: 0,
                    y: 6
                )
        }
        #else
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
        } else if colorScheme == .light {
            content
                .padding(padding)
                .background(.ultraThinMaterial, in: shape)
                .background(Color.white.opacity(elevated ? 0.46 : 0.30), in: shape)
                .glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
                .overlay(
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.92),
                                Color(red: 0.067, green: 0.098, blue: 0.173).opacity(contrast == .increased ? 0.24 : 0.09),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: contrast == .increased ? 1.25 : 0.85
                    )
                )
                .shadow(
                    color: Color(red: 0.067, green: 0.098, blue: 0.173).opacity(elevated ? 0.09 : 0.05),
                    radius: elevated ? 14 : 9,
                    x: 0,
                    y: 4
                )
        } else {
            content
                .padding(padding)
                .background(Color.white.opacity(elevated ? 0.05 : 0.025), in: shape)
                .glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
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
        #endif
    }
}

/// Arrière-plan atmosphérique profond (sombre) ou nacré ardoise (clair) permettant aux surfaces
/// Liquid Glass de réfracter naturellement lumière et couleur sans jamais masquer le contenu.
public struct AmbientBackgroundView: View {
    @Environment(\.colorScheme) private var colorScheme

    public init() {}

    public var body: some View {
        #if os(tvOS)
        let isLight = false
        #else
        let isLight = colorScheme == .light
        #endif

        ZStack {
            DesignTokens.canvas(isLight ? .light : .dark)

            if isLight {
                RadialGradient(
                    colors: [
                        Color(red: 0.055, green: 0.647, blue: 0.914).opacity(0.11),
                        Color.clear,
                    ],
                    center: .topLeading,
                    startRadius: 20,
                    endRadius: 560
                )

                RadialGradient(
                    colors: [
                        Color(red: 0.388, green: 0.400, blue: 0.945).opacity(0.08),
                        Color.clear,
                    ],
                    center: .topTrailing,
                    startRadius: 20,
                    endRadius: 520
                )

                RadialGradient(
                    colors: [
                        Color(red: 0.063, green: 0.725, blue: 0.506).opacity(0.06),
                        Color.clear,
                    ],
                    center: .bottom,
                    startRadius: 20,
                    endRadius: 480
                )
            } else {
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
        #if os(tvOS)
        let base = HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .fixedSize(horizontal: true, vertical: false)
        .foregroundStyle(color)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)

        base
            .background(color.opacity(reduceTransparency ? 0.24 : 0.16), in: Capsule())
            .overlay(Capsule().strokeBorder(color.opacity(reduceTransparency ? 0.55 : 0.38), lineWidth: 1))
        #else
        let base = HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.caption2.weight(.bold))
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .fixedSize(horizontal: true, vertical: false)
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)

        if reduceTransparency {
            base
                .background(color.opacity(0.18), in: Capsule())
                .overlay(Capsule().strokeBorder(color.opacity(0.45), lineWidth: 1))
        } else {
            base
                .background(color.opacity(0.14), in: Capsule())
                .glassEffect(.regular.interactive(), in: Capsule())
                .overlay(Capsule().strokeBorder(color.opacity(0.32), lineWidth: 0.75))
        }
        #endif
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

    private var resourceColumns: [GridItem] {
        #if os(tvOS)
        return [GridItem(.adaptive(minimum: 195), spacing: 12)]
        #else
        return [GridItem(.adaptive(minimum: 92), spacing: 6)]
        #endif
    }

    private var driveColumns: [GridItem] {
        #if os(tvOS)
        return [GridItem(.adaptive(minimum: 195), spacing: 12)]
        #else
        return [GridItem(.adaptive(minimum: 84), spacing: 6)]
        #endif
    }

    private func sectionHeaderButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    #if os(tvOS)
                    .font(.system(.caption, design: .monospaced, weight: .semibold))
                    #else
                    .font(.system(.caption2, design: .monospaced, weight: .semibold))
                    #endif
                    .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer()
                Image(systemName: "chevron.right")
                    #if os(tvOS)
                    .font(.caption.weight(.semibold))
                    #else
                    .font(.caption2.weight(.semibold))
                    #endif
                    .foregroundStyle(DesignTokens.secondaryText(colorScheme))
            }
            #if os(tvOS)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 42)
            #else
            .frame(minHeight: 26)
            #endif
            .contentShape(Rectangle())
        }
        .cardButtonStyle(cornerRadius: 12)
    }

    public var body: some View {
        let teal = DesignTokens.signalTeal(colorScheme)
        let nominal = DesignTokens.nominal(colorScheme)
        let caution = DesignTokens.caution(colorScheme)
        let critical = DesignTokens.critical(colorScheme)

        #if os(tvOS)
        let cardPadding: CGFloat = 24
        let badgeFont: Font = .system(.caption2, design: .monospaced, weight: .bold)
        let cellHPad: CGFloat = 12
        let cellVPad: CGFloat = 10
        #else
        let cardPadding: CGFloat = 16
        let badgeFont: Font = .system(size: 9, weight: .bold, design: .monospaced)
        let cellHPad: CGFloat = 8
        let cellVPad: CGFloat = 6
        #endif

        GlassCard(padding: cardPadding, cornerRadius: 22) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("BAIE PROXMOX • \(node.name.uppercased())")
                            .font(.system(.caption, design: .monospaced, weight: .bold))
                            .foregroundStyle(teal)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Text("PVE \(node.pveVersion) • Uptime \(node.uptimeHuman)")
                            .font(.caption)
                            .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    Spacer()
                    StatusPill("Nominal", color: nominal, systemImage: "checkmark.circle.fill")
                }

                if !resources.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        sectionHeaderButton(
                            "NŒUDS & CONTENEURS (\(resources.filter(\.isRunning).count)/\(resources.count))",
                            action: onSelectMachines
                        )

                        LazyVGrid(columns: resourceColumns, spacing: 10) {
                            ForEach(resources) { res in
                                HStack(spacing: 6) {
                                    Image(systemName: res.isRunning ? "power.circle.fill" : "pause.circle")
                                        .font(.caption2)
                                        .foregroundStyle(res.isRunning ? nominal : DesignTokens.secondaryText(colorScheme))
                                    Text("#\(res.vmid)")
                                        .font(.system(.caption2, design: .monospaced, weight: .semibold))
                                        .foregroundStyle(DesignTokens.primaryText(colorScheme))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                    Spacer(minLength: 0)
                                    Text(res.type.badgeLabel)
                                        .font(badgeFont)
                                        .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                }
                                .padding(.horizontal, cellHPad)
                                .padding(.vertical, cellVPad)
                                .background(
                                    DesignTokens.surfaceElevated(colorScheme),
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                )
                                .accessibilityLabel("\(res.type.badgeLabel) \(res.vmid) \(res.name), \(res.isRunning ? "en ligne" : "arrêté")")
                            }
                        }
                    }
                }

                if !drives.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        sectionHeaderButton(
                            "BAIES DISQUES (\(drives.count) MONTÉS)",
                            action: onSelectStorage
                        )

                        LazyVGrid(columns: driveColumns, spacing: 10) {
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
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.8)
                                    }
                                    UsageProgressBar(percentage: drive.usedPct, tint: bayColor)
                                    Text(String(format: "%.0f %%", drive.usedPct))
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                }
                                .padding(cellVPad + 2)
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
                    .fill(
                        colorScheme == .light
                            ? Color(red: 0.067, green: 0.098, blue: 0.173).opacity(0.11)
                            : Color.white.opacity(0.12)
                    )
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
        } else if colorScheme == .light {
            label
                .background(.ultraThinMaterial, in: Capsule())
                .glassEffect(.regular, in: Capsule())
                .overlay(Capsule().strokeBorder(DesignTokens.hairBorder(colorScheme), lineWidth: 0.85))
                .shadow(color: .black.opacity(0.14), radius: 12, y: 5)
                .padding(.horizontal, 20)
        } else {
            label
                .glassEffect(.regular, in: Capsule())
                .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
                .padding(.horizontal, 20)
        }
    }
}
