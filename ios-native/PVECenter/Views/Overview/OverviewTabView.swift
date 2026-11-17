#if canImport(Charts)
import Charts
#endif
import SwiftUI

private struct ResourceMetricPoint: Identifiable {
    let id: String
    let label: String
    let percentage: Double
    let color: Color
}

private struct ServiceLatencyPoint: Identifiable {
    let id: String
    let name: String
    let latencyMs: Double
    let isOnline: Bool
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
                        #if canImport(Charts)
                        nodeTelemetryChart(pve)
                        #endif
                    }

                    quickStatsGrid
                    #if canImport(Charts)
                    servicesLatencyChartCard
                    #endif
                    servicesAccessCard
                    activeStreamsSection
                }
            }
            .padding(.horizontal, DesignTokens.pageHorizontalPadding)
            .padding(.vertical, DesignTokens.pageVerticalPadding)
        }
        #if os(tvOS)
        .contentMargins(.top, 18, for: .scrollContent)
        .contentMargins(.bottom, 32, for: .scrollContent)
        #else
        .contentMargins(.top, 8, for: .scrollContent)
        .refreshable {
            await viewModel.refreshAll(silent: false)
        }
        #endif
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

    #if canImport(Charts)
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
                    Spacer(minLength: 8)
                    StatusPill(
                        pve.online ? "En ligne" : "Hors ligne",
                        color: pve.online ? DesignTokens.nominal(colorScheme) : DesignTokens.critical(colorScheme),
                        systemImage: pve.online ? "checkmark.circle.fill" : "xmark.octagon.fill"
                    )
                    .lineLimit(1)
                    .fixedSize()
                }

                Chart(points) { item in
                    BarMark(
                        x: .value("Utilisation", item.percentage),
                        y: .value("Métrique", item.label)
                    )
                    .foregroundStyle(item.color)
                    .cornerRadius(6)
                    .annotation(position: .trailing) {
                        Text(String(format: "%.0f %%", item.percentage))
                            #if os(tvOS)
                            .font(.system(.caption, design: .monospaced, weight: .semibold))
                            #else
                            .font(.system(.caption2, design: .monospaced, weight: .semibold))
                            #endif
                            .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                    }
                }
                .chartXScale(domain: 0...100)
                .chartXAxis(.hidden)
                #if os(tvOS)
                .chartYAxis {
                    AxisMarks { _ in
                        AxisValueLabel()
                            .font(.callout.weight(.medium))
                            .foregroundStyle(DesignTokens.primaryText(colorScheme))
                    }
                }
                .frame(height: 210)
                #else
                .frame(height: 108)
                #endif

                HStack {
                    Text("Loadavg \(pve.node.loadavg.prefix(3).joined(separator: " / "))")
                        #if os(tvOS)
                        .font(.system(.caption, design: .monospaced))
                        #else
                        .font(.system(.caption2, design: .monospaced))
                        #endif
                        .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 8)
                    Text("\(ByteFormatters.formatBytes(pve.node.memUsedBytes)) / \(ByteFormatters.formatBytes(pve.node.memTotalBytes)) RAM")
                        #if os(tvOS)
                        .font(.system(.caption, design: .monospaced))
                        #else
                        .font(.system(.caption2, design: .monospaced))
                        #endif
                        .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
        }
    }

    @ViewBuilder
    private var servicesLatencyChartCard: some View {
        let points = mergedLatencyPoints
        if !points.isEmpty {
            let onlinePoints = points.filter(\.isOnline)
            let avgLatency: Int = onlinePoints.isEmpty
                ? 0
                : Int((onlinePoints.map(\.latencyMs).reduce(0, +) / Double(onlinePoints.count)).rounded())
            let displayed = Array(points.prefix(6))
            let maxLatency = max(20.0, (displayed.map(\.latencyMs).max() ?? 20.0) * 1.25)

            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Santé & Latence des services")
                                .font(.headline)
                                .foregroundStyle(DesignTokens.primaryText(colorScheme))
                            Text("Moyenne \(avgLatency) ms • \(onlinePoints.count)/\(points.count) opérationnels")
                                .font(.caption)
                                .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        if viewModel.activeIncidentsCount > 0 {
                            StatusPill(
                                "\(viewModel.activeIncidentsCount) incident\(viewModel.activeIncidentsCount > 1 ? "s" : "")",
                                color: DesignTokens.critical(colorScheme),
                                systemImage: "exclamationmark.octagon.fill"
                            )
                        } else {
                            StatusPill(
                                "Stable",
                                color: DesignTokens.nominal(colorScheme),
                                systemImage: "waveform.path.ecg"
                            )
                        }
                    }

                    Chart(displayed) { item in
                        let barColor: Color = !item.isOnline
                            ? DesignTokens.critical(colorScheme)
                            : (item.latencyMs >= 100
                                ? DesignTokens.caution(colorScheme)
                                : (item.latencyMs >= 40 ? DesignTokens.signalTeal(colorScheme) : DesignTokens.nominal(colorScheme)))

                        BarMark(
                            x: .value("Latence (ms)", item.isOnline ? max(1.0, item.latencyMs) : maxLatency * 0.12),
                            y: .value("Service", item.name)
                        )
                        .foregroundStyle(barColor)
                        .cornerRadius(6)
                        .annotation(position: .trailing) {
                            Text(item.isOnline ? "\(Int(item.latencyMs.rounded())) ms" : "HS")
                                #if os(tvOS)
                                .font(.system(.caption, design: .monospaced, weight: .semibold))
                                #else
                                .font(.system(.caption2, design: .monospaced, weight: .semibold))
                                #endif
                                .foregroundStyle(item.isOnline ? DesignTokens.secondaryText(colorScheme) : DesignTokens.critical(colorScheme))
                        }
                    }
                    .chartXScale(domain: 0...maxLatency)
                    .chartXAxis(.hidden)
                    #if os(tvOS)
                    .chartYAxis {
                        AxisMarks { _ in
                            AxisValueLabel()
                                .font(.callout.weight(.medium))
                                .foregroundStyle(DesignTokens.primaryText(colorScheme))
                        }
                    }
                    .frame(height: CGFloat(max(190, displayed.count * 52)))
                    #else
                    .frame(height: CGFloat(max(96, displayed.count * 26)))
                    #endif
                }
            }
        }
    }
    #endif

    private var mergedLatencyPoints: [ServiceLatencyPoint] {
        var seen: Set<String> = []
        var list: [ServiceLatencyPoint] = []

        for svc in viewModel.customServices {
            if seen.insert(svc.id).inserted {
                list.append(ServiceLatencyPoint(
                    id: svc.id,
                    name: svc.name,
                    latencyMs: Double(svc.latencyMs ?? 0),
                    isOnline: svc.isOnline
                ))
            }
        }
        for svc in viewModel.categories.flatMap(\.services) {
            if seen.insert(svc.id).inserted {
                list.append(ServiceLatencyPoint(
                    id: svc.id,
                    name: svc.name,
                    latencyMs: svc.latencyMs ?? 0,
                    isOnline: svc.online
                ))
            }
        }
        return list
    }

    private var quickStatsColumns: [GridItem] {
        #if os(tvOS)
        return Array(repeating: GridItem(.flexible(), spacing: 20), count: 4)
        #else
        return [GridItem(.adaptive(minimum: 168), spacing: 12)]
        #endif
    }

    private var servicePreviewColumns: [GridItem] {
        #if os(tvOS)
        return [GridItem(.adaptive(minimum: 520), spacing: 18)]
        #else
        return [GridItem(.adaptive(minimum: 145), spacing: 8)]
        #endif
    }

    private var quickStatsGridSpacing: CGFloat {
        #if os(tvOS)
        return 20
        #else
        return 12
        #endif
    }

    private var servicePreviewGridSpacing: CGFloat {
        #if os(tvOS)
        return 16
        #else
        return 8
        #endif
    }

    private var quickStatsGrid: some View {
        let pve = viewModel.pveOverview
        let mergedServices = mergedLatencyPoints
        let onlineServices = mergedServices.filter(\.isOnline).count
        let qbit = viewModel.widgets?.qbittorrent
        let teal = DesignTokens.signalTeal(colorScheme)

        return LazyVGrid(columns: quickStatsColumns, spacing: quickStatsGridSpacing) {
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
                value: "\(onlineServices) / \(mergedServices.count)",
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
            #if os(tvOS)
            GlassCard(padding: 20, cornerRadius: 18, interactive: true) {
                VStack(alignment: .leading, spacing: 8) {
                    Label(title, systemImage: icon)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(accent)
                    Text(value)
                        .font(.system(.title3, design: .monospaced, weight: .bold))
                        .foregroundStyle(DesignTokens.primaryText(colorScheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
            }
            #else
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
            #endif
        }
        .cardButtonStyle(cornerRadius: 18)
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
                        Spacer(minLength: 8)
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
                                    .lineLimit(1)
                            }
                            .fixedSize()
                        } else {
                            Button("Tout voir") { viewModel.selectedTab = .services }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(DesignTokens.signalTeal(colorScheme))
                                .lineLimit(1)
                                .fixedSize()
                        }
                        #else
                        Button("Tout voir") { viewModel.selectedTab = .services }
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                            .adaptivePillButtonStyle(tint: DesignTokens.signalTeal(colorScheme))
                            .fixedSize()
                        #endif
                    }

                    LazyVGrid(columns: servicePreviewColumns, spacing: servicePreviewGridSpacing) {
                        ForEach(services.prefix(6)) { svc in
                            HStack(spacing: 12) {
                                ServiceIconView(
                                    icon: svc.icon,
                                    serviceId: svc.id,
                                    serviceName: svc.name,
                                    widget: svc.widget,
                                    isOnline: svc.online,
                                    size: {
                                        #if os(tvOS)
                                        34
                                        #else
                                        24
                                        #endif
                                    }()
                                )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(svc.name)
                                        #if os(tvOS)
                                        .font(.callout.weight(.semibold))
                                        #else
                                        .font(.caption.weight(.medium))
                                        #endif
                                        .foregroundStyle(DesignTokens.primaryText(colorScheme))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.85)
                                    Text(svc.online ? "En ligne" : "Hors ligne")
                                        #if os(tvOS)
                                        .font(.caption2.weight(.medium))
                                        #else
                                        .font(.system(size: 10, weight: .medium))
                                        #endif
                                        .foregroundStyle(svc.online ? DesignTokens.nominal(colorScheme) : DesignTokens.critical(colorScheme))
                                }
                                Spacer(minLength: 4)
                                if let ms = svc.latencyMs, svc.online {
                                    Text("\(Int(ms)) ms")
                                        #if os(tvOS)
                                        .font(.system(.caption, design: .monospaced))
                                        #else
                                        .font(.system(.caption2, design: .monospaced))
                                        #endif
                                        .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                                        .lineLimit(1)
                                        .fixedSize(horizontal: true, vertical: false)
                                }
                            }
                            #if os(tvOS)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            #else
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            #endif
                            .background(
                                DesignTokens.surfaceElevated(colorScheme),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
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
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        StatusPill(
                            "\(streams.count) actif\(streams.count > 1 ? "s" : "")",
                            color: DesignTokens.signalTeal(colorScheme),
                            systemImage: "play.fill"
                        )
                        .lineLimit(1)
                        .fixedSize()
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
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
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
