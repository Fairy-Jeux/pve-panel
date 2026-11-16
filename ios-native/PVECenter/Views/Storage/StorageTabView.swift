import Charts
import SwiftUI

private struct PoolSlice: Identifiable {
    let id: String
    let label: String
    let bytes: Double
    let color: Color
}

public struct StorageTabView: View {
    public var viewModel: AppViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var showHealthyOnly = false

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    private var adaptiveColumns: [GridItem] {
        #if os(tvOS)
        return [GridItem(.adaptive(minimum: 420), spacing: 24)]
        #elseif os(macOS)
        return [GridItem(.adaptive(minimum: 320), spacing: 12)]
        #else
        return [GridItem(.flexible())]
        #endif
    }

    public var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if let ext = viewModel.pveOverview?.externalStorage {
                    poolChartCard(ext.pool)

                    if let ssd = ext.systemSsd {
                        systemSsdCard(ssd)
                    }

                    drivesSection(ext.drives)
                }

                if let storages = viewModel.pveOverview?.node.storages, !storages.isEmpty {
                    proxmoxDatastoresSection(storages)
                }
            }
            .padding(.horizontal, DesignTokens.pageHorizontalPadding)
            .padding(.vertical, DesignTokens.pageVerticalPadding)
        }
        .contentMargins(.top, 8, for: .scrollContent)
        .refreshable {
            await viewModel.refreshAll(silent: false)
        }
    }

    private func poolChartCard(_ pool: MergerfsPoolInfo) -> some View {
        let teal = DesignTokens.signalTeal(colorScheme)
        let usedColor = pool.usedPct >= 85 ? DesignTokens.caution(colorScheme) : teal
        let used = max(0, Double(pool.usedBytes))
        let avail = max(0, Double(pool.availBytes))
        let slices: [PoolSlice] = [
            PoolSlice(id: "used", label: "Utilisé", bytes: used, color: usedColor),
            PoolSlice(id: "avail", label: "Disponible", bytes: avail, color: DesignTokens.surfaceElevated(colorScheme)),
        ]

        return GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Label(pool.name, systemImage: "square.stack.3d.up.fill")
                            .font(.headline)
                            .foregroundStyle(DesignTokens.primaryText(colorScheme))
                        Text("\(pool.fstype) • \(pool.policy) • \(pool.drivesCount) disques")
                            .font(.caption)
                            .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                    }
                    Spacer()
                    StatusPill(
                        pool.available ? "Monté" : "Indisponible",
                        color: pool.available ? DesignTokens.nominal(colorScheme) : DesignTokens.critical(colorScheme),
                        systemImage: pool.available ? "checkmark.circle.fill" : "xmark.octagon.fill"
                    )
                }

                HStack(spacing: 18) {
                    ZStack {
                        Chart(slices) { slice in
                            SectorMark(
                                angle: .value("Octets", slice.bytes),
                                innerRadius: .ratio(0.68),
                                angularInset: 2
                            )
                            .foregroundStyle(slice.color)
                            .cornerRadius(4)
                        }
                        .frame(width: 112, height: 112)

                        VStack(spacing: 1) {
                            Text(String(format: "%.0f %%", pool.usedPct))
                                .font(.system(.title3, design: .monospaced, weight: .bold))
                                .foregroundStyle(DesignTokens.primaryText(colorScheme))
                            Text("occupé")
                                .font(.caption2)
                                .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        detailMetric(title: "Capacité totale", value: ByteFormatters.formatDecimalTB(pool.totalBytes), color: DesignTokens.primaryText(colorScheme))
                        detailMetric(title: "Espace utilisé", value: ByteFormatters.formatDecimalTB(pool.usedBytes), color: usedColor)
                        detailMetric(title: "Espace libre", value: ByteFormatters.formatDecimalTB(pool.availBytes), color: DesignTokens.nominal(colorScheme))
                    }
                    Spacer()
                }
            }
        }
    }

    private func detailMetric(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(DesignTokens.secondaryText(colorScheme))
            Text(value)
                .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                .foregroundStyle(color)
        }
    }

    private func systemSsdCard(_ ssd: SystemSsdInfo) -> some View {
        let passed = ssd.health.uppercased() == "PASSED"
        return GlassCard(padding: 14, cornerRadius: 16) {
            HStack(spacing: 12) {
                Image(systemName: "memorychip.fill")
                    .font(.title2)
                    .foregroundStyle(DesignTokens.signalTeal(colorScheme))
                    .frame(width: 40, height: 40)
                    .background(DesignTokens.surfaceElevated(colorScheme), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("SSD Système Proxmox")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DesignTokens.primaryText(colorScheme))
                    Text("\(ssd.model) • \(ssd.devpath) • \(ByteFormatters.formatBytes(ssd.sizeBytes))")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                }
                Spacer()
                StatusPill(
                    ssd.health,
                    color: passed ? DesignTokens.nominal(colorScheme) : DesignTokens.caution(colorScheme),
                    systemImage: passed ? "checkmark.shield.fill" : "exclamationmark.triangle.fill"
                )
            }
        }
    }

    private func drivesSection(_ drives: [PhysicalDriveInfo]) -> some View {
        let q = viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = drives.filter { drive in
            let matchesSearch = q.isEmpty
                || drive.label.lowercased().contains(q)
                || drive.model.lowercased().contains(q)
                || drive.devpath.lowercased().contains(q)
                || drive.mount.lowercased().contains(q)
            let matchesSmart = !showHealthyOnly || drive.isHealthy
            return matchesSearch && matchesSmart
        }

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Disques physiques (\(filtered.count))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                Spacer()
                Toggle("Sains uniquement", isOn: $showHealthyOnly)
                    #if !os(tvOS)
                    .toggleStyle(.button)
                    .controlSize(.small)
                    #endif
            }

            LazyVGrid(columns: adaptiveColumns, spacing: 12) {
                ForEach(Array(filtered.enumerated()), id: \.element.id) { idx, drive in
                    GlassCard(padding: 14, cornerRadius: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(String(format: "BAY %02d", idx + 1))
                                            .font(.system(.caption2, design: .monospaced, weight: .bold))
                                            .foregroundStyle(DesignTokens.signalTeal(colorScheme))
                                        Text(drive.label)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(DesignTokens.primaryText(colorScheme))
                                    }
                                    Text("\(drive.model) • \(drive.type) (\(drive.rpm))")
                                        .font(.caption2)
                                        .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                                }
                                Spacer()
                                StatusPill(
                                    "SMART \(drive.health)",
                                    color: drive.isHealthy ? DesignTokens.nominal(colorScheme) : DesignTokens.critical(colorScheme),
                                    systemImage: drive.isHealthy ? "checkmark.circle.fill" : "exclamationmark.octagon.fill"
                                )
                            }

                            UsageProgressBar(percentage: drive.usedPct)

                            HStack {
                                Text("\(ByteFormatters.formatDecimalTB(drive.usedBytes)) / \(ByteFormatters.formatDecimalTB(drive.totalBytes))")
                                    .font(.system(.caption, design: .monospaced, weight: .medium))
                                    .foregroundStyle(DesignTokens.primaryText(colorScheme))
                                Spacer()
                                Text("\(drive.devpath) • \(drive.mount)")
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                            }
                        }
                    }
                }
            }
        }
    }

    private func proxmoxDatastoresSection(_ storages: [StorageInfo]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Datastores Proxmox VE")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DesignTokens.secondaryText(colorScheme))

            LazyVGrid(columns: adaptiveColumns, spacing: 12) {
                ForEach(storages) { storage in
                    GlassCard(padding: 14, cornerRadius: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label(storage.name, systemImage: "internaldrive.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(DesignTokens.primaryText(colorScheme))
                                Text(storage.type)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                                Spacer()
                                Text(String(format: "%.1f %%", storage.usedPct))
                                    .font(.system(.caption, design: .monospaced, weight: .bold))
                                    .foregroundStyle(DesignTokens.primaryText(colorScheme))
                            }
                            UsageProgressBar(percentage: storage.usedPct, tint: DesignTokens.signalTeal(colorScheme))
                            HStack {
                                Text("\(ByteFormatters.formatBytes(storage.usedBytes)) utilisés")
                                    .font(.caption2)
                                    .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                                Spacer()
                                Text("Total \(ByteFormatters.formatBytes(storage.totalBytes))")
                                    .font(.caption2)
                                    .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                            }
                        }
                    }
                }
            }
        }
    }
}
