import SwiftUI

/// Native Apple HIG translucent container adapting cleanly to Light and Dark Mode.
public struct GlassCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    private let padding: CGFloat
    private let cornerRadius: CGFloat
    private let content: Content

    public init(
        padding: CGFloat = 16,
        cornerRadius: CGFloat = 22,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.22 : 0.75),
                                Color.white.opacity(colorScheme == .dark ? 0.05 : 0.18),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.08),
                radius: 14,
                x: 0,
                y: 8
            )
    }
}

/// Adaptive subtle ambient background supporting Light & Dark appearances.
public struct AmbientBackgroundView: View {
    @Environment(\.colorScheme) private var colorScheme

    public init() {}

    public var body: some View {
        ZStack {
            (colorScheme == .dark ? Color(red: 0.02, green: 0.03, blue: 0.07) : Color(red: 0.95, green: 0.97, blue: 1.0))
                .ignoresSafeArea()

            RadialGradient(
                colors: [
                    Color.cyan.opacity(colorScheme == .dark ? 0.18 : 0.14),
                    Color.clear,
                ],
                center: .topLeading,
                startRadius: 20,
                endRadius: 420
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [
                    Color.indigo.opacity(colorScheme == .dark ? 0.16 : 0.10),
                    Color.clear,
                ],
                center: .topTrailing,
                startRadius: 10,
                endRadius: 380
            )
            .ignoresSafeArea()
        }
    }
}

public struct StatusPill: View {
    public let title: String
    public let color: Color
    public let systemImage: String?

    public init(_ title: String, color: Color, systemImage: String? = nil) {
        self.title = title
        self.color = color
        self.systemImage = systemImage
    }

    public var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.semibold))
            } else {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
            }
            Text(title)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.14), in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(color.opacity(0.28), lineWidth: 0.75)
        )
    }
}

public struct UsageProgressBar: View {
    public let percentage: Double
    public var tint: Color?

    public init(percentage: Double, tint: Color? = nil) {
        self.percentage = max(0, min(100, percentage))
        self.tint = tint
    }

    private var resolvedColor: Color {
        if let tint { return tint }
        if percentage >= 90 { return .red }
        if percentage >= 75 { return .orange }
        return .cyan
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.10))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [resolvedColor.opacity(0.85), resolvedColor],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(4, geo.size.width * (percentage / 100)))
            }
        }
        .frame(height: 7)
    }
}

public struct ToastOverlayView: View {
    public let toast: ToastMessage

    public init(toast: ToastMessage) {
        self.toast = toast
    }

    public var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(toast.isError ? .red : .green)
                .font(.body.weight(.semibold))
            Text(toast.text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 14, y: 6)
        .padding(.horizontal, 20)
    }
}
