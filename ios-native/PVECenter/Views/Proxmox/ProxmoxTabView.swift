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
    @Environment(\.colorScheme) private var colorScheme
    @State private var filter: ResourceFilter = .all
    @State private var pendingCommand: PendingPowerCommand?

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

    private var adaptiveColumns: [GridItem] {
        #if os(tvOS)
        return [GridItem(.adaptive(minimum: 420), spacing: 24)]
        #elseif os(macOS)
        return [GridItem(.adaptive(minimum: 340), spacing: 14)]
        #else
        return [GridItem(.flexible())]
        #endif
    }

    public var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                if let node = viewModel.pveOverview?.node {
                    nodeOverviewCard(node)
                }

                HStack(spacing: 12) {
                    Text("Conteneurs & VMs (\(displayedResources.count))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                    Spacer()
                    Picker("Filtre des ressources", selection: $filter) {
                        ForEach(ResourceFilter.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 300)
                }

                LazyVGrid(columns: adaptiveColumns, spacing: 14) {
                    ForEach(displayedResources) { resource in
                        resourceCard(resource)
                    }
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
        .contentMargins(.top, 8, for: .scrollContent)
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
        let teal = DesignTokens.signalTeal(colorScheme)

        return GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(node.name)
                            .font(.headline)
                            .foregroundStyle(DesignTokens.primaryText(colorScheme))
                        Text("PVE \(node.pveVersion) • Uptime \(node.uptimeHuman)")
                            .font(.caption)
                            .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                    }
                    Spacer()
                    StatusPill("CPU \(Int(node.cpuPct)) %", color: teal, systemImage: "cpu")
                }

                VStack(spacing: 10) {
                    metricRow(
                        label: "Processeur",
                        value: String(format: "%.1f %% (%d vCPU)", node.cpuPct, node.cpuThreads),
                        pct: node.cpuPct,
                        tint: teal
                    )
                    metricRow(
                        label: "Mémoire RAM",
                        value: "\(ByteFormatters.formatBytes(node.memUsedBytes)) / \(ByteFormatters.formatBytes(node.memTotalBytes))",
                        pct: node.memPct,
                        tint: DesignTokens.secondaryText(colorScheme)
                    )
                    let rootPct = node.rootfsTotalBytes > 0
                        ? (Double(node.rootfsUsedBytes) / Double(node.rootfsTotalBytes)) * 100
                        : 0
                    metricRow(
                        label: "Disque RootFS",
                        value: "\(ByteFormatters.formatBytes(node.rootfsUsedBytes)) / \(ByteFormatters.formatBytes(node.rootfsTotalBytes))",
                        pct: rootPct,
                        tint: DesignTokens.nominal(colorScheme)
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
                    .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                Spacer()
                Text(value)
                    .font(.system(.caption, design: .monospaced, weight: .semibold))
                    .foregroundStyle(DesignTokens.primaryText(colorScheme))
            }
            UsageProgressBar(percentage: pct, tint: tint)
        }
    }

    private func resourceCard(_ res: PveResource) -> some View {
        let nominal = DesignTokens.nominal(colorScheme)
        let teal = DesignTokens.signalTeal(colorScheme)

        return GlassCard(padding: 14, cornerRadius: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: res.type.symbolName)
                        .font(.title3)
                        .foregroundStyle(res.isRunning ? teal : DesignTokens.secondaryText(colorScheme))
                        .frame(width: 38, height: 38)
                        .background(
                            DesignTokens.surfaceElevated(colorScheme),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(res.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(DesignTokens.primaryText(colorScheme))
                            Text("#\(res.vmid)")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                        }
                        HStack(spacing: 6) {
                            Text(res.type.badgeLabel)
                                .font(.system(.caption2, design: .monospaced, weight: .bold))
                                .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                            Text("•")
                                .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                            Text(res.isRunning ? "Uptime \(res.uptimeHuman)" : "Arrêté")
                                .font(.caption2)
                                .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                        }
                    }

                    Spacer()

                    StatusPill(
                        res.isRunning ? "Actif" : "Stop",
                        color: res.isRunning ? nominal : DesignTokens.secondaryText(colorScheme),
                        systemImage: res.isRunning ? "checkmark.circle.fill" : "pause.circle.fill"
                    )
                }

                if res.isRunning {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("CPU \(String(format: "%.1f %%", res.cpuPct))")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                            UsageProgressBar(percentage: res.cpuPct, tint: teal)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text("RAM \(ByteFormatters.formatBytes(res.memUsedBytes)) / \(ByteFormatters.formatBytes(res.memTotalBytes)) (\(Int(res.memPct)) %)")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                                .lineLimit(1)
                            UsageProgressBar(percentage: res.memPct, tint: DesignTokens.secondaryText(colorScheme))
                        }
                    }
                }

                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        if !res.isRunning {
                            Button {
                                pendingCommand = PendingPowerCommand(resource: res, action: .start)
                            } label: {
                                Label(PveAction.start.shortLabel, systemImage: PveAction.start.systemImage)
                                    .frame(minHeight: 26)
                            }
                            .buttonStyle(.glassProminent)
                            .tint(DesignTokens.signalTeal(colorScheme))
                            .controlSize(.small)
                        } else if !res.isSelf {
                            Button {
                                pendingCommand = PendingPowerCommand(resource: res, action: .reboot)
                            } label: {
                                Label(PveAction.reboot.shortLabel, systemImage: PveAction.reboot.systemImage)
                                    .frame(minHeight: 26)
                            }
                            .buttonStyle(.glass)
                            .controlSize(.small)

                            Button {
                                pendingCommand = PendingPowerCommand(resource: res, action: .shutdown)
                            } label: {
                                Label(PveAction.shutdown.shortLabel, systemImage: PveAction.shutdown.systemImage)
                                    .foregroundStyle(DesignTokens.caution(colorScheme))
                                    .frame(minHeight: 26)
                            }
                            .buttonStyle(.glass)
                            .controlSize(.small)

                            Button(role: .destructive) {
                                pendingCommand = PendingPowerCommand(resource: res, action: .stop)
                            } label: {
                                Label(PveAction.stop.shortLabel, systemImage: PveAction.stop.systemImage)
                                    .foregroundStyle(DesignTokens.critical(colorScheme))
                                    .frame(minHeight: 26)
                            }
                            .buttonStyle(.glass)
                            .controlSize(.small)
                        } else {
                            Label("Protégé contre l'auto-extinction", systemImage: "shield.checkmark.fill")
                                .font(.caption2)
                                .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                        }
                        Spacer()
                    }
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
}
