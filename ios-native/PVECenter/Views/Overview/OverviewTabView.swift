import Charts
import SwiftUI

private struct ResourceMetricPoint: Identifiable {
    let id: String
    let label: String
    let percentage: Double
    let color: Color
}

public struct OverviewTabView: View {
    public var viewModel: AppViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                AlertsBannerView(alerts: viewModel.smartAlerts) { target in
                    if reduceMotion {
                        viewModel.selectedTab = target
                    } else {
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.85)) {
                            viewModel.selectedTab = target
                        }
                    }
                }

                if viewModel.isInitialLoading && viewModel.pveOverview == nil {
                    loadingSkeleton
                } else {
                    if let pve = viewModel.pveOverview {
                        RackBayMatrixView(
                            node: pve.node,
                            resources: pve.resources,
                            drives: pve.externalStorage?.drives ?? [],
                            onSelectMachines: { viewModel.selectedTab = .proxmox },
                            onSelectStorage: { viewModel.selectedTab = .storage }
                        )
                        nodeTelemetryChart(pve)
                    }

                    quickStatsGrid
                    servicesAccessCard
                    activeStreamsSection
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .contentMargins(.top, 8, for: .scrollContent)
        .refreshable {
            await viewModel.refreshAll(silent: false)
        }
    }

    private var loadingSkeleton: some View {
        GlassCard {
            VStack(spacing: 14) {
                ProgressView("Synchronisation avec l'infrastructure…")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            }
        }
    }

    private func nodeTelemetryChart(_ pve: PveOverview) -> some View {
        let teal = DesignTokens.signalTeal(colorScheme)
        let rootPct = pve.node.rootfsTotalBytes > 0
            ? (Double(pve.node.rootfsUsedBytes) / Double(pve.node.rootfsTotalBytes)) * 100
            : 0
        let points: [ResourceMetricPoint] = [
            ResourceMetricPoint(id: "cpu", label: "CPU", percentage: pve.node.cpuPct, color: teal),
            ResourceMetricPoint(id: "ram", label: "RAM", percentage: pve.node.memPct, color: DesignTokens.secondaryText(colorScheme)),
            ResourceMetricPoint(id: "root", label: "RootFS", percentage: rootPct, color: DesignTokens.nominal(colorScheme)),
        ]

        return GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Charge du nœud")
                            .font(.headline)
                            .foregroundStyle(DesignTokens.primaryText(colorScheme))
                        Text("\(pve.node.cpuModel) • \(pve.node.cpuThreads) threads")
                            .font(.caption)
                            .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                            .lineLimit(1)
                    }
                    Spacer()
                    StatusPill(
                        pve.online ? "En ligne" : "Hors ligne",
                        color: pve.online ? DesignTokens.nominal(colorScheme) : DesignTokens.critical(colorScheme),
                        systemImage: pve.online ? "checkmark.circle.fill" : "xmark.octagon.fill"
                    )
                }

                Chart(points) { item in
                    BarMark(
                        x: .value("Utilisation", item.percentage),
                        y: .value("Métrique", item.label)
                    )
                    .foregroundStyle(item.color)
                    .cornerRadius(5)
                    .annotation(position: .trailing) {
                        Text(String(format: "%.0f %%", item.percentage))
                            .font(.system(.caption2, design: .monospaced, weight: .semibold))
                            .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                    }
                }
                .chartXScale(domain: 0...100)
                .chartXAxis(.hidden)
                .frame(height: 108)

                HStack {
                    Text("Loadavg \(pve.node.loadavg.prefix(3).joined(separator: " / "))")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                    Spacer()
                    Text("\(ByteFormatters.formatBytes(pve.node.memUsedBytes)) / \(ByteFormatters.formatBytes(pve.node.memTotalBytes)) RAM")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                }
            }
        }
    }

    private var quickStatsColumns: [GridItem] {
        #if os(tvOS)
        return [GridItem(.adaptive(minimum: 420), spacing: 24)]
        #else
        return [GridItem(.adaptive(minimum: 168), spacing: 12)]
        #endif
    }

    private var servicePreviewColumns: [GridItem] {
        #if os(tvOS)
        return [GridItem(.adaptive(minimum: 420), spacing: 24)]
        #else
        return [GridItem(.adaptive(minimum: 145), spacing: 8)]
        #endif
    }

    private var quickStatsGrid: some View {
        let pve = viewModel.pveOverview
        let allServices = viewModel.categories.flatMap(\.services)
        let onlineServices = allServices.filter(\.online).count
        let qbit = viewModel.widgets?.qbittorrent
        let teal = DesignTokens.signalTeal(colorScheme)

        return LazyVGrid(columns: quickStatsColumns, spacing: 12) {
            statTile(
                title: "Machines",
                value: "\(pve?.counts.running ?? 0) / \(pve?.counts.total ?? 0)",
                subtitle: "LXC & VMs actives",
                icon: "server.rack",
                accent: teal
            ) {
                viewModel.selectedTab = .proxmox
            }

            statTile(
                title: "Stockage",
                value: ByteFormatters.formatDecimalTB(pve?.externalStorage?.pool.usedBytes ?? 0),
                subtitle: "sur \(ByteFormatters.formatDecimalTB(pve?.externalStorage?.pool.totalBytes ?? 0))",
                icon: "internaldrive.fill",
                accent: teal
            ) {
                viewModel.selectedTab = .storage
            }

            statTile(
                title: "Transferts",
                value: ByteFormatters.formatSpeed(qbit?.dlSpeedBytes),
                subtitle: "↑ \(ByteFormatters.formatSpeed(qbit?.upSpeedBytes))",
                icon: "arrow.down.arrow.up.circle.fill",
                accent: teal
            ) {
                viewModel.selectedTab = .operations
            }

            statTile(
                title: "Services",
                value: "\(onlineServices) / \(allServices.count)",
                subtitle: "En ligne",
                icon: "checkmark.seal.fill",
                accent: DesignTokens.nominal(colorScheme)
            ) {
                #if os(tvOS) || os(macOS)
                viewModel.selectedTab = .services
                #else
                if horizontalSizeClass == .regular {
                    viewModel.selectedTab = .services
                }
                #endif
            }
        }
    }

    private func statTile(
        title: String,
        value: String,
        subtitle: String,
        icon: String,
        accent: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            GlassCard(padding: 14, cornerRadius: 16, interactive: true) {
                VStack(alignment: .leading, spacing: 6) {
                    Label(title, systemImage: icon)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(accent)
                    Text(value)
                        .font(.system(.title3, design: .monospaced, weight: .bold))
                        .foregroundStyle(DesignTokens.primaryText(colorScheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var servicesAccessCard: some View {
        let services = viewModel.categories.flatMap(\.services)
        if !services.isEmpty {
            GlassCard(padding: 14, cornerRadius: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("Services hébergés (\(services.count))", systemImage: "app.connected.to.app.below.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DesignTokens.primaryText(colorScheme))
                        Spacer()
                        #if os(iOS)
                        if horizontalSizeClass == .compact {
                            NavigationLink {
                                ServicesTabView(viewModel: viewModel)
                                    .background { AmbientBackgroundView() }
                                    .navigationTitle("Services")
                            } label: {
                                Label("Tout voir", systemImage: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(DesignTokens.signalTeal(colorScheme))
                            }
                        } else {
                            Button("Tout voir") { viewModel.selectedTab = .services }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(DesignTokens.signalTeal(colorScheme))
                        }
                        #else
                        Button("Tout voir") { viewModel.selectedTab = .services }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(DesignTokens.signalTeal(colorScheme))
                        #endif
                    }

                    LazyVGrid(columns: servicePreviewColumns, spacing: 8) {
                        ForEach(services.prefix(6)) { svc in
                            HStack(spacing: 8) {
                                Image(systemName: svc.online ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(svc.online ? DesignTokens.nominal(colorScheme) : DesignTokens.critical(colorScheme))
                                Text(svc.name)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(DesignTokens.primaryText(colorScheme))
                                    .lineLimit(1)
                                Spacer()
                                if let ms = svc.latencyMs, svc.online {
                                    Text("\(Int(ms))ms")
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                DesignTokens.surfaceElevated(colorScheme),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var activeStreamsSection: some View {
        if let jf = viewModel.widgets?.jellyfin,
           let streams = jf.activeStreams,
           !streams.isEmpty {
            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("Lectures en cours (Jellyfin)", systemImage: "play.tv.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DesignTokens.primaryText(colorScheme))
                        Spacer()
                        StatusPill(
                            "\(streams.count) actif\(streams.count > 1 ? "s" : "")",
                            color: DesignTokens.signalTeal(colorScheme),
                            systemImage: "play.fill"
                        )
                    }

                    ForEach(streams) { stream in
                        HStack(spacing: 10) {
                            Image(systemName: stream.isPaused ? "pause.circle.fill" : "play.circle.fill")
                                .font(.title3)
                                .foregroundStyle(stream.isPaused ? DesignTokens.caution(colorScheme) : DesignTokens.signalTeal(colorScheme))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(stream.title)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(DesignTokens.primaryText(colorScheme))
                                    .lineLimit(1)
                                Text("\(stream.user) • \(stream.device) (\(stream.playMethod))")
                                    .font(.caption2)
                                    .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                            }
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }
}
