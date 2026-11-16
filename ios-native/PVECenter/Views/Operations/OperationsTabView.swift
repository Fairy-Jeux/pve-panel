import SwiftUI

public struct OperationsTabView: View {
    public var viewModel: AppViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var scanningTarget: String?

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    private enum Layout {
        #if os(tvOS)
        static let sectionSpacing: CGFloat = 22
        static let cardSpacing: CGFloat = 16
        static let actionSpacing: CGFloat = 14
        static let cardPadding: CGFloat = 20
        static let rowPadding: CGFloat = 14
        static let buttonMinHeight: CGFloat = 40
        static let smallButtonMinHeight: CGFloat = 36
        static let taskRowVerticalPadding: CGFloat = 6
        #else
        static let sectionSpacing: CGFloat = 16
        static let cardSpacing: CGFloat = 12
        static let actionSpacing: CGFloat = 10
        static let cardPadding: CGFloat = 16
        static let rowPadding: CGFloat = 10
        static let buttonMinHeight: CGFloat = 32
        static let smallButtonMinHeight: CGFloat = 28
        static let taskRowVerticalPadding: CGFloat = 3
        #endif
    }

    public var body: some View {
        ScrollView {
            LazyVStack(spacing: Layout.sectionSpacing) {
                quickActionsCard
                seerrRequestsSection
                qbitSection
                pveTasksSection
            }
            .padding(.horizontal, DesignTokens.pageHorizontalPadding)
            .padding(.vertical, DesignTokens.pageVerticalPadding)
        }
        .contentMargins(.top, 8, for: .scrollContent)
        .refreshable {
            await viewModel.refreshAll(silent: false)
        }
    }

    private var quickActionsCard: some View {
        GlassCard(padding: Layout.cardPadding) {
            VStack(alignment: .leading, spacing: Layout.cardSpacing) {
                Label("Indexation des médiathèques", systemImage: "bolt.fill")
                    .font(.headline)
                    .foregroundStyle(DesignTokens.primaryText(colorScheme))
                    .lineLimit(1)

                GlassEffectContainer(spacing: Layout.actionSpacing) {
                    HStack(spacing: Layout.actionSpacing) {
                        scanButton(
                            target: "jellyfin",
                            title: "Scanner Jellyfin",
                            systemImage: "arrow.triangle.2.circlepath",
                            prominent: true
                        )
                        scanButton(
                            target: "plex",
                            title: "Scanner Plex",
                            systemImage: "arrow.clockwise",
                            prominent: false
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func scanButton(target: String, title: String, systemImage: String, prominent: Bool) -> some View {
        let button = Button {
            Task {
                scanningTarget = target
                await viewModel.triggerMediaScan(target: target)
                scanningTarget = nil
            }
        } label: {
            Label(
                scanningTarget == target ? "Scan en cours…" : title,
                systemImage: systemImage
            )
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .frame(maxWidth: .infinity, minHeight: Layout.buttonMinHeight)
        }
        .disabled(scanningTarget != nil)

        #if os(tvOS)
        button.buttonStyle(.glass)
        #else
        if prominent {
            button
                .buttonStyle(.glassProminent)
                .tint(DesignTokens.signalTeal(colorScheme))
        } else {
            button.buttonStyle(.glass)
        }
        #endif
    }

    private var seerrRequestsSection: some View {
        let requests = viewModel.opsOverview?.seerrRequests ?? []

        return GlassCard(padding: Layout.cardPadding) {
            VStack(alignment: .leading, spacing: Layout.cardSpacing) {
                HStack {
                    Label("Demandes Jellyseerr", systemImage: "film.stack.fill")
                        .font(.headline)
                        .foregroundStyle(DesignTokens.primaryText(colorScheme))
                        .lineLimit(1)
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
                        VStack(alignment: .leading, spacing: Layout.cardSpacing) {
                            HStack(spacing: 10) {
                                Image(systemName: req.mediaType == "tv" ? "tv" : "film")
                                    .foregroundStyle(DesignTokens.signalTeal(colorScheme))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(req.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(DesignTokens.primaryText(colorScheme))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.85)
                                    Text("Demandé par \(req.requestedBy)")
                                        .font(.caption2)
                                        .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.85)
                                }
                                Spacer(minLength: 6)
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
                                GlassEffectContainer(spacing: Layout.actionSpacing) {
                                    HStack(spacing: Layout.actionSpacing) {
                                        Button {
                                            Task { await viewModel.decideSeerrRequest(id: req.id, approve: true) }
                                        } label: {
                                            Label("Approuver", systemImage: "checkmark")
                                                .lineLimit(1)
                                                .minimumScaleFactor(0.82)
                                                .frame(maxWidth: .infinity, minHeight: Layout.smallButtonMinHeight)
                                        }
                                        #if os(tvOS)
                                        .buttonStyle(.glass)
                                        #else
                                        .buttonStyle(.glassProminent)
                                        .tint(DesignTokens.nominal(colorScheme))
                                        #endif
                                        .adaptiveSmallControlSize()

                                        Button(role: .destructive) {
                                            Task { await viewModel.decideSeerrRequest(id: req.id, approve: false) }
                                        } label: {
                                            Label("Refuser", systemImage: "xmark")
                                                .foregroundStyle(DesignTokens.critical(colorScheme))
                                                .lineLimit(1)
                                                .minimumScaleFactor(0.82)
                                                .frame(maxWidth: .infinity, minHeight: Layout.smallButtonMinHeight)
                                        }
                                        .buttonStyle(.glass)
                                        .adaptiveSmallControlSize()
                                    }
                                }
                            }
                        }
                        .padding(Layout.rowPadding)
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
            GlassCard(padding: Layout.cardPadding) {
                VStack(alignment: .leading, spacing: Layout.cardSpacing) {
                    HStack(spacing: 10) {
                        Label("qBittorrent", systemImage: "arrow.down.circle.fill")
                            .font(.headline)
                            .foregroundStyle(DesignTokens.primaryText(colorScheme))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Spacer(minLength: 6)
                        Button {
                            Task { await viewModel.toggleQbitSpeedMode() }
                        } label: {
                            Label(
                                qbit.altSpeedEnabled ? "Tortue ON" : "Vitesse Max",
                                systemImage: qbit.altSpeedEnabled ? "tortoise.fill" : "hare.fill"
                            )
                            .foregroundStyle(qbit.altSpeedEnabled ? DesignTokens.caution(colorScheme) : DesignTokens.nominal(colorScheme))
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                        }
                        .buttonStyle(.glass)
                        .adaptiveSmallControlSize()
                    }

                    ForEach(qbit.torrents) { torrent in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(torrent.name)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(DesignTokens.primaryText(colorScheme))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.85)
                                    Text("\(String(format: "%.1f %%", torrent.progressPct)) • ↓ \(ByteFormatters.formatSpeed(torrent.dlspeed)) • ↑ \(ByteFormatters.formatSpeed(torrent.upspeed)) • ETA \(ByteFormatters.formatETA(torrent.eta))")
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.82)
                                }
                                Spacer(minLength: 6)
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
                                    .frame(minWidth: Layout.buttonMinHeight, minHeight: Layout.buttonMinHeight)
                                }
                                .buttonStyle(.glass)
                                .adaptiveSmallControlSize()
                            }
                            UsageProgressBar(
                                percentage: torrent.progressPct,
                                tint: torrent.isPaused ? DesignTokens.caution(colorScheme) : DesignTokens.signalTeal(colorScheme)
                            )
                        }
                        .padding(Layout.rowPadding)
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

        return GlassCard(padding: Layout.cardPadding) {
            VStack(alignment: .leading, spacing: Layout.cardSpacing) {
                Label("Journal des tâches Proxmox", systemImage: "list.bullet.clipboard.fill")
                    .font(.headline)
                    .foregroundStyle(DesignTokens.primaryText(colorScheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                if tasks.isEmpty {
                    Text("Aucune tâche récente.")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                } else {
                    ForEach(tasks.prefix(8)) { task in
                        HStack(spacing: 10) {
                            Image(systemName: task.isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(task.isSuccess ? DesignTokens.nominal(colorScheme) : DesignTokens.caution(colorScheme))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(task.type.uppercased()) \(task.vmid.isEmpty ? "" : "#\(task.vmid)")")
                                    .font(.system(.caption, design: .monospaced, weight: .semibold))
                                    .foregroundStyle(DesignTokens.primaryText(colorScheme))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.82)
                                Text("\(task.user) • \(ByteFormatters.formatTimestamp(task.starttime))")
                                    .font(.caption2)
                                    .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                            }
                            Spacer(minLength: 6)
                            if let sec = task.durationSec {
                                Text("\(sec)s")
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                                    .lineLimit(1)
                            }
                        }
                        .padding(.vertical, Layout.taskRowVerticalPadding)
                    }
                }
            }
        }
    }
}
