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
    @State private var showHealthyOnly = false

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
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
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .refreshable {
            await viewModel.refreshAll(silent: false)
        }
    }

    private func poolChartCard(_ pool: MergerfsPoolInfo) -> some View {
        let used = max(0, Double(pool.usedBytes))
        let avail = max(0, Double(pool.availBytes))
        let slices: [PoolSlice] = [
            PoolSlice(id: "used", label: "Utilisé", bytes: used, color: pool.usedPct >= 85 ? .orange : .cyan),
            PoolSlice(id: "avail", label: "Disponible", bytes: avail, color: .secondary.opacity(0.28)),
        ]

        return GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Label(pool.name, systemImage: "square.stack.3d.up.fill")
                            .font(.headline)
                        Text("\(pool.fstype) • \(pool.policy) • \(pool.drivesCount) disques")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusPill(pool.available ? "Monté" : "Indisponible", color: pool.available ? .green : .red)
                }

                HStack(spacing: 18) {
                    ZStack {
                        Chart(slices) { slice in
                            SectorMark(
                                angle: .value("Octets", slice.bytes),
                                innerRadius: .ratio(0.66),
                                angularInset: 2
                            )
                            .foregroundStyle(slice.color)
                            .cornerRadius(4)
                        }
                        .frame(width: 112, height: 112)

                        VStack(spacing: 1) {
                            Text(String(format: "%.0f %%", pool.usedPct))
                                .font(.title3.weight(.bold).monospacedDigit())
                            Text("occupé")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        detailMetric(title: "Capacité totale", value: ByteFormatters.formatDecimalTB(pool.totalBytes), color: .primary)
                        detailMetric(title: "Espace utilisé", value: ByteFormatters.formatDecimalTB(pool.usedBytes), color: .cyan)
                        detailMetric(title: "Espace libre", value: ByteFormatters.formatDecimalTB(pool.availBytes), color: .green)
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
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(color)
        }
    }

    private func systemSsdCard(_ ssd: SystemSsdInfo) -> some View {
        GlassCard(padding: 14, cornerRadius: 18) {
            HStack(spacing: 12) {
                Image(systemName: "memorychip.fill")
                    .font(.title2)
                    .foregroundStyle(.indigo)
                    .frame(width: 40, height: 40)
                    .background(Color.indigo.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("SSD Système Proxmox")
                        .font(.subheadline.weight(.semibold))
                    Text("\(ssd.model) • \(ssd.devpath) • \(ByteFormatters.formatBytes(ssd.sizeBytes))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusPill(ssd.health, color: ssd.health.uppercased() == "PASSED" ? .green : .orange)
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
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle("Sains", isOn: $showHealthyOnly)
                    .toggleStyle(.button)
                    .font(.caption2.weight(.semibold))
            }

            ForEach(filtered) { drive in
                GlassCard(padding: 14, cornerRadius: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(drive.label)
                                    .font(.subheadline.weight(.semibold))
                                Text("\(drive.model) • \(drive.type) (\(drive.rpm))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            StatusPill(
                                "SMART \(drive.health)",
                                color: drive.isHealthy ? .green : .red
                            )
                        }

                        UsageProgressBar(percentage: drive.usedPct)

                        HStack {
                            Text("\(ByteFormatters.formatDecimalTB(drive.usedBytes)) / \(ByteFormatters.formatDecimalTB(drive.totalBytes))")
                                .font(.caption.weight(.medium).monospacedDigit())
                            Spacer()
                            Text("\(drive.devpath) • \(drive.mount)")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
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
                .foregroundStyle(.secondary)

            ForEach(storages) { storage in
                GlassCard(padding: 14, cornerRadius: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label(storage.name, systemImage: "internaldrive.fill")
                                .font(.subheadline.weight(.semibold))
                            Text(storage.type)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: "%.1f %%", storage.usedPct))
                                .font(.caption.weight(.bold).monospacedDigit())
                        }
                        UsageProgressBar(percentage: storage.usedPct, tint: .indigo)
                        HStack {
                            Text("\(ByteFormatters.formatBytes(storage.usedBytes)) utilisés")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("Total \(ByteFormatters.formatBytes(storage.totalBytes))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}
