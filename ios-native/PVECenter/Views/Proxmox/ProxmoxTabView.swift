import SwiftUI

private enum ResourceFilter: String, CaseIterable, Identifiable {
    case all = "Tous"
    case running = "Actifs"
    case lxc = "LXC"
    case qemu = "VMs"

    var id: String { rawValue }
}

private struct PendingPowerCommand: Identifiable {
    let id = UUID()
    let resource: PveResource
    let action: PveAction
}

public struct ProxmoxTabView: View {
    public var viewModel: AppViewModel
    @State private var filter: ResourceFilter = .all
    @State private var pendingCommand: PendingPowerCommand?
    @Namespace private var filterNamespace

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    private var displayedResources: [PveResource] {
        viewModel.filteredResources.filter { item in
            switch filter {
            case .all: return true
            case .running: return item.isRunning
            case .lxc: return item.type == .lxc
            case .qemu: return item.type == .qemu
            }
        }
    }

    public var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                if let node = viewModel.pveOverview?.node {
                    nodeOverviewCard(node)
                }

                filterBar

                ForEach(displayedResources) { resource in
                    resourceCard(resource)
                }

                if displayedResources.isEmpty {
                    GlassCard {
                        ContentUnavailableView(
                            "Aucune ressource",
                            systemImage: "server.rack",
                            description: Text("Aucun conteneur LXC ou VM ne correspond à votre filtre.")
                        )
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .refreshable {
            await viewModel.refreshAll(silent: false)
        }
        .confirmationDialog(
            pendingCommand.map { "\($0.action.label) \($0.resource.name) (#\($0.resource.vmid)) ?" } ?? "",
            isPresented: Binding(
                get: { pendingCommand != nil },
                set: { if !$0 { pendingCommand = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let cmd = pendingCommand {
                Button(
                    cmd.action.label,
                    role: cmd.action.isDestructive ? .destructive : nil
                ) {
                    Task {
                        await viewModel.executePveAction(resource: cmd.resource, action: cmd.action)
                    }
                }
                Button("Annuler", role: .cancel) {}
            }
        } message: {
            if let cmd = pendingCommand {
                Text(cmd.action.warningMessage)
            }
        }
    }

    private func nodeOverviewCard(_ node: NodeSummary) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(node.name)
                            .font(.headline)
                        Text("PVE \(node.pveVersion) • Uptime \(node.uptimeHuman)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusPill("CPU \(Int(node.cpuPct)) %", color: .cyan, systemImage: "cpu")
                }

                VStack(spacing: 10) {
                    metricRow(
                        label: "Processeur",
                        value: String(format: "%.1f %% (%d vCPU)", node.cpuPct, node.cpuThreads),
                        pct: node.cpuPct,
                        tint: .cyan
                    )
                    metricRow(
                        label: "Mémoire RAM",
                        value: "\(ByteFormatters.formatBytes(node.memUsedBytes)) / \(ByteFormatters.formatBytes(node.memTotalBytes))",
                        pct: node.memPct,
                        tint: .indigo
                    )
                    let rootPct = node.rootfsTotalBytes > 0
                        ? (Double(node.rootfsUsedBytes) / Double(node.rootfsTotalBytes)) * 100
                        : 0
                    metricRow(
                        label: "Disque RootFS",
                        value: "\(ByteFormatters.formatBytes(node.rootfsUsedBytes)) / \(ByteFormatters.formatBytes(node.rootfsTotalBytes))",
                        pct: rootPct,
                        tint: .mint
                    )
                }
            }
        }
    }

    private func metricRow(label: String, value: String, pct: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value)
                    .font(.caption.weight(.semibold).monospacedDigit())
            }
            UsageProgressBar(percentage: pct, tint: tint)
        }
    }

    private var filterBar: some View {
        HStack(spacing: 6) {
            ForEach(ResourceFilter.allCases) { item in
                let selected = filter == item
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                        filter = item
                    }
                } label: {
                    Text(item.rawValue)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(selected ? .primary : .secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background {
                            if selected {
                                Capsule()
                                    .fill(.regularMaterial)
                                    .matchedGeometryEffect(id: "pveFilterPill", in: filterNamespace)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(4)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private func resourceCard(_ res: PveResource) -> some View {
        GlassCard(padding: 14, cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: res.type.symbolName)
                        .font(.title3)
                        .foregroundStyle(res.isRunning ? .cyan : .secondary)
                        .frame(width: 36, height: 36)
                        .background(
                            (res.isRunning ? Color.cyan : Color.secondary).opacity(0.14),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(res.name)
                                .font(.subheadline.weight(.semibold))
                            Text("#\(res.vmid)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            if res.isSelf {
                                StatusPill("Hôte Panel", color: .indigo, systemImage: "lock.fill")
                            }
                        }
                        HStack(spacing: 8) {
                            Text(res.type.badgeLabel)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary)
                            Text("•")
                                .foregroundStyle(.secondary)
                            Text(res.isRunning ? "Uptime \(res.uptimeHuman)" : "Arrêté")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    StatusPill(
                        res.isRunning ? "Actif" : "Stop",
                        color: res.isRunning ? .green : .secondary
                    )
                }

                if res.isRunning {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("CPU \(String(format: "%.1f %%", res.cpuPct))")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                            UsageProgressBar(percentage: res.cpuPct, tint: .cyan)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text("RAM \(ByteFormatters.formatBytes(res.memUsedBytes))")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                            UsageProgressBar(percentage: res.memPct, tint: .indigo)
                        }
                    }
                }

                HStack(spacing: 8) {
                    if !res.isRunning {
                        actionButton(resource: res, action: .start, tint: .green)
                    } else if !res.isSelf {
                        actionButton(resource: res, action: .reboot, tint: .cyan)
                        actionButton(resource: res, action: .shutdown, tint: .orange)
                        actionButton(resource: res, action: .stop, tint: .red)
                    } else {
                        Label("Protégé contre l'auto-extinction", systemImage: "shield.checkmark.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        }
        .contextMenu {
            if !res.isRunning {
                Button {
                    pendingCommand = PendingPowerCommand(resource: res, action: .start)
                } label: {
                    Label("Démarrer", systemImage: "play.fill")
                }
            } else if !res.isSelf {
                Button {
                    pendingCommand = PendingPowerCommand(resource: res, action: .reboot)
                } label: {
                    Label("Redémarrer", systemImage: "arrow.clockwise")
                }
                Button(role: .destructive) {
                    pendingCommand = PendingPowerCommand(resource: res, action: .shutdown)
                } label: {
                    Label("Éteindre proprement", systemImage: "power")
                }
                Button(role: .destructive) {
                    pendingCommand = PendingPowerCommand(resource: res, action: .stop)
                } label: {
                    Label("Forcer l'arrêt", systemImage: "stop.fill")
                }
            }
        }
    }

    private func actionButton(resource: PveResource, action: PveAction, tint: Color) -> some View {
        Button {
            pendingCommand = PendingPowerCommand(resource: resource, action: action)
        } label: {
            Label(action.shortLabel, systemImage: action.systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(tint.opacity(0.14), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
