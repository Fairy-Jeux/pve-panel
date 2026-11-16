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

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                AlertsBannerView(alerts: viewModel.smartAlerts) { target in
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        viewModel.selectedTab = target
                    }
                }

                if viewModel.isInitialLoading && viewModel.pveOverview == nil {
                    loadingSkeleton
                } else {
                    nodeSummaryCard
                    quickStatsGrid
                    activeStreamsSection
                    storagePreviewCard
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .refreshable {
            await viewModel.refreshAll(silent: false)
        }
    }

    private var loadingSkeleton: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.1))
                        .frame(width: 140, height: 20)
                    Spacer()
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: 74, height: 24)
                }
                ProgressView("Synchronisation avec l'infrastructure…")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 18)
            }
        }
    }

    @ViewBuilder
    private var nodeSummaryCard: some View {
        if let pve = viewModel.pveOverview {
            let rootPct = pve.node.rootfsTotalBytes > 0
                ? (Double(pve.node.rootfsUsedBytes) / Double(pve.node.rootfsTotalBytes)) * 100
                : 0
            let points: [ResourceMetricPoint] = [
                ResourceMetricPoint(id: "cpu", label: "CPU", percentage: pve.node.cpuPct, color: .cyan),
                ResourceMetricPoint(id: "ram", label: "RAM", percentage: pve.node.memPct, color: .indigo),
                ResourceMetricPoint(id: "root", label: "Système", percentage: rootPct, color: .mint),
            ]

            GlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Label(pve.node.name.uppercased(), systemImage: "cpu.fill")
                                .font(.headline)
                            Text("\(pve.node.cpuModel) • \(pve.node.cpuThreads) threads")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        StatusPill(
                            pve.online ? "En ligne" : "Hors ligne",
                            color: pve.online ? .green : .red
                        )
                    }

                    Chart(points) { item in
                        BarMark(
                            x: .value("Utilisation", item.percentage),
                            y: .value("Métrique", item.label)
                        )
                        .foregroundStyle(item.color.gradient)
                        .cornerRadius(6)
                        .annotation(position: .trailing) {
                            Text(String(format: "%.0f %%", item.percentage))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .chartXScale(domain: 0...100)
                    .chartXAxis(.hidden)
                    .frame(height: 112)

                    HStack {
                        Label("Uptime \(pve.node.uptimeHuman)", systemImage: "clock")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("Load: \(pve.node.loadavg.prefix(3).joined(separator: " / "))")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var quickStatsGrid: some View {
        let pve = viewModel.pveOverview
        let allServices = viewModel.categories.flatMap(\.services)
        let onlineServices = allServices.filter(\.online).count
        let qbit = viewModel.widgets?.qbittorrent

        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 175), spacing: 12)], spacing: 12) {
            Button {
                viewModel.selectedTab = .proxmox
            } label: {
                GlassCard(padding: 14, cornerRadius: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("LXC & VMs", systemImage: "server.rack")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.cyan)
                        Text("\(pve?.counts.running ?? 0) / \(pve?.counts.total ?? 0)")
                            .font(.title2.weight(.bold).monospacedDigit())
                            .foregroundStyle(.primary)
                        Text("Ressources actives")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.plain)

            Button {
                viewModel.selectedTab = .services
            } label: {
                GlassCard(padding: 14, cornerRadius: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Services", systemImage: "checkmark.seal.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)
                        Text("\(onlineServices) / \(allServices.count)")
                            .font(.title2.weight(.bold).monospacedDigit())
                            .foregroundStyle(.primary)
                        Text("En bonne santé")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.plain)

            Button {
                viewModel.selectedTab = .operations
            } label: {
                GlassCard(padding: 14, cornerRadius: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("qBittorrent", systemImage: "arrow.down.arrow.up.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.indigo)
                        Text(ByteFormatters.formatSpeed(qbit?.dlSpeedBytes))
                            .font(.title3.weight(.bold).monospacedDigit())
                            .foregroundStyle(.primary)
                        Text("Up: \(ByteFormatters.formatSpeed(qbit?.upSpeedBytes))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.plain)

            Button {
                viewModel.selectedTab = .users
            } label: {
                GlassCard(padding: 14, cornerRadius: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Utilisateurs", systemImage: "person.2.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.mint)
                        Text("\(viewModel.usersOverview?.counts.totalJellyfin ?? 0)")
                            .font(.title2.weight(.bold).monospacedDigit())
                            .foregroundStyle(.primary)
                        Text("\(viewModel.usersOverview?.counts.syncedJellyseerr ?? 0) sur Jellyseerr")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.plain)
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
                            .foregroundStyle(.cyan)
                        Spacer()
                        StatusPill("\(streams.count) actif\(streams.count > 1 ? "s" : "")", color: .cyan)
                    }

                    ForEach(streams) { stream in
                        HStack(spacing: 10) {
                            Image(systemName: stream.isPaused ? "pause.circle.fill" : "play.circle.fill")
                                .font(.title3)
                                .foregroundStyle(stream.isPaused ? .orange : .cyan)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(stream.title)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                Text("\(stream.user) • \(stream.device) (\(stream.playMethod))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var storagePreviewCard: some View {
        if let pool = viewModel.pveOverview?.externalStorage?.pool {
            Button {
                viewModel.selectedTab = .storage
            } label: {
                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label(pool.name, systemImage: "externaldrive.connected.to.line.below.fill")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(String(format: "%.1f %%", pool.usedPct))
                                .font(.subheadline.weight(.bold).monospacedDigit())
                                .foregroundStyle(pool.usedPct >= 85 ? .orange : .cyan)
                        }
                        UsageProgressBar(percentage: pool.usedPct)
                        HStack {
                            Text("\(ByteFormatters.formatDecimalTB(pool.usedBytes)) utilisés sur \(ByteFormatters.formatDecimalTB(pool.totalBytes))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }
}
