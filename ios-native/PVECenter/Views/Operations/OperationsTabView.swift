import SwiftUI

public struct OperationsTabView: View {
    public var viewModel: AppViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var scanningTarget: String?

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                quickActionsCard
                seerrRequestsSection
                qbitSection
                pveTasksSection
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .refreshable {
            await viewModel.refreshAll(silent: false)
        }
    }

    private var quickActionsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Indexation des médiathèques", systemImage: "bolt.fill")
                    .font(.headline)
                    .foregroundStyle(DesignTokens.primaryText(colorScheme))

                HStack(spacing: 10) {
                    Button {
                        Task {
                            scanningTarget = "jellyfin"
                            await viewModel.triggerMediaScan(target: "jellyfin")
                            scanningTarget = nil
                        }
                    } label: {
                        Label(
                            scanningTarget == "jellyfin" ? "Scan en cours…" : "Scanner Jellyfin",
                            systemImage: "arrow.triangle.2.circlepath"
                        )
                        .frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(scanningTarget != nil)

                    Button {
                        Task {
                            scanningTarget = "plex"
                            await viewModel.triggerMediaScan(target: "plex")
                            scanningTarget = nil
                        }
                    } label: {
                        Label(
                            scanningTarget == "plex" ? "Scan en cours…" : "Scanner Plex",
                            systemImage: "arrow.clockwise"
                        )
                        .frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .buttonStyle(.bordered)
                    .disabled(scanningTarget != nil)
                }
            }
        }
    }

    private var seerrRequestsSection: some View {
        let requests = viewModel.opsOverview?.seerrRequests ?? []

        return GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Demandes Jellyseerr", systemImage: "film.stack.fill")
                        .font(.headline)
                        .foregroundStyle(DesignTokens.primaryText(colorScheme))
                    Spacer()
                    if viewModel.pendingRequestsCount > 0 {
                        StatusPill(
                            "\(viewModel.pendingRequestsCount) en attente",
                            color: DesignTokens.caution(colorScheme),
                            systemImage: "clock.fill"
                        )
                    }
                }

                if requests.isEmpty {
                    Text("Aucune demande récente.")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                } else {
                    ForEach(requests) { req in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: req.mediaType == "tv" ? "tv" : "film")
                                    .foregroundStyle(DesignTokens.signalTeal(colorScheme))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(req.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(DesignTokens.primaryText(colorScheme))
                                    Text("Demandé par \(req.requestedBy)")
                                        .font(.caption2)
                                        .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                                }
                                Spacer()
                                StatusPill(
                                    req.statusLabel,
                                    color: req.status == 1
                                        ? DesignTokens.caution(colorScheme)
                                        : (req.status == 2 ? DesignTokens.nominal(colorScheme) : DesignTokens.critical(colorScheme)),
                                    systemImage: req.status == 1
                                        ? "clock.fill"
                                        : (req.status == 2 ? "checkmark.circle.fill" : "xmark.circle.fill")
                                )
                            }

                            if req.isPending {
                                HStack(spacing: 8) {
                                    Button {
                                        Task { await viewModel.decideSeerrRequest(id: req.id, approve: true) }
                                    } label: {
                                        Label("Approuver", systemImage: "checkmark")
                                            .frame(maxWidth: .infinity, minHeight: 28)
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)

                                    Button(role: .destructive) {
                                        Task { await viewModel.decideSeerrRequest(id: req.id, approve: false) }
                                    } label: {
                                        Label("Refuser", systemImage: "xmark")
                                            .frame(maxWidth: .infinity, minHeight: 28)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                        }
                        .padding(10)
                        .background(
                            DesignTokens.surfaceElevated(colorScheme),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var qbitSection: some View {
        if let qbit = viewModel.opsOverview?.qbitControl, qbit.available {
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("qBittorrent", systemImage: "arrow.down.circle.fill")
                            .font(.headline)
                            .foregroundStyle(DesignTokens.primaryText(colorScheme))
                        Spacer()
                        Button {
                            Task { await viewModel.toggleQbitSpeedMode() }
                        } label: {
                            Label(
                                qbit.altSpeedEnabled ? "Tortue ON" : "Vitesse Max",
                                systemImage: qbit.altSpeedEnabled ? "tortoise.fill" : "hare.fill"
                            )
                        }
                        .buttonStyle(.bordered)
                        .tint(qbit.altSpeedEnabled ? DesignTokens.caution(colorScheme) : DesignTokens.nominal(colorScheme))
                        .controlSize(.small)
                    }

                    ForEach(qbit.torrents) { torrent in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(torrent.name)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(DesignTokens.primaryText(colorScheme))
                                        .lineLimit(1)
                                    Text("\(String(format: "%.1f %%", torrent.progressPct)) • ↓ \(ByteFormatters.formatSpeed(torrent.dlspeed)) • ↑ \(ByteFormatters.formatSpeed(torrent.upspeed)) • ETA \(ByteFormatters.formatETA(torrent.eta))")
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                                }
                                Spacer()
                                Button {
                                    Task {
                                        await viewModel.controlTorrent(
                                            hash: torrent.hash,
                                            pause: !torrent.isPaused
                                        )
                                    }
                                } label: {
                                    Label(
                                        torrent.isPaused ? "Reprendre" : "Pause",
                                        systemImage: torrent.isPaused ? "play.fill" : "pause.fill"
                                    )
                                    .labelStyle(.iconOnly)
                                    .frame(minWidth: 32, minHeight: 32)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            UsageProgressBar(
                                percentage: torrent.progressPct,
                                tint: torrent.isPaused ? DesignTokens.caution(colorScheme) : DesignTokens.signalTeal(colorScheme)
                            )
                        }
                        .padding(10)
                        .background(
                            DesignTokens.surfaceElevated(colorScheme),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                    }
                }
            }
        }
    }

    private var pveTasksSection: some View {
        let tasks = viewModel.opsOverview?.pveTasks ?? []

        return GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("Journal des tâches Proxmox", systemImage: "list.bullet.clipboard.fill")
                    .font(.headline)
                    .foregroundStyle(DesignTokens.primaryText(colorScheme))

                if tasks.isEmpty {
                    Text("Aucune tâche récente.")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                } else {
                    ForEach(tasks.prefix(8)) { task in
                        HStack {
                            Image(systemName: task.isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(task.isSuccess ? DesignTokens.nominal(colorScheme) : DesignTokens.caution(colorScheme))
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(task.type.uppercased()) \(task.vmid.isEmpty ? "" : "#\(task.vmid)")")
                                    .font(.system(.caption, design: .monospaced, weight: .semibold))
                                    .foregroundStyle(DesignTokens.primaryText(colorScheme))
                                Text("\(task.user) • \(ByteFormatters.formatTimestamp(task.starttime))")
                                    .font(.caption2)
                                    .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                            }
                            Spacer()
                            if let sec = task.durationSec {
                                Text("\(sec)s")
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                            }
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
        }
    }
}
