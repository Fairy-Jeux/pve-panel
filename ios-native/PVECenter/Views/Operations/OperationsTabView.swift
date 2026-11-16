import SwiftUI

public struct OperationsTabView: View {
    public var viewModel: AppViewModel
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
                Label("Actions rapides multimédia", systemImage: "bolt.fill")
                    .font(.headline)
                    .foregroundStyle(.cyan)

                HStack(spacing: 10) {
                    Button {
                        Task {
                            scanningTarget = "jellyfin"
                            await viewModel.triggerMediaScan(target: "jellyfin")
                            scanningTarget = nil
                        }
                    } label: {
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text(scanningTarget == "jellyfin" ? "Scan…" : "Scan Jellyfin")
                                .font(.caption.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.cyan.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(scanningTarget != nil)

                    Button {
                        Task {
                            scanningTarget = "plex"
                            await viewModel.triggerMediaScan(target: "plex")
                            scanningTarget = nil
                        }
                    } label: {
                        HStack {
                            Image(systemName: "sparkles")
                            Text(scanningTarget == "plex" ? "Scan…" : "Scan Plex")
                                .font(.caption.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.indigo.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
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
                    Spacer()
                    if viewModel.pendingRequestsCount > 0 {
                        StatusPill("\(viewModel.pendingRequestsCount) en attente", color: .orange)
                    }
                }

                if requests.isEmpty {
                    Text("Aucune demande récente.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(requests) { req in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: req.mediaType == "tv" ? "tv" : "film")
                                    .foregroundStyle(.cyan)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(req.title)
                                        .font(.subheadline.weight(.semibold))
                                    Text("Demandé par \(req.requestedBy)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                StatusPill(
                                    req.statusLabel,
                                    color: req.status == 1 ? .orange : (req.status == 2 ? .green : .red)
                                )
                            }

                            if req.isPending {
                                HStack(spacing: 8) {
                                    Button {
                                        Task { await viewModel.decideSeerrRequest(id: req.id, approve: true) }
                                    } label: {
                                        Label("Approuver", systemImage: "checkmark.circle.fill")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.green)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 7)
                                            .background(Color.green.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        Task { await viewModel.decideSeerrRequest(id: req.id, approve: false) }
                                    } label: {
                                        Label("Refuser", systemImage: "xmark.circle.fill")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.red)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 7)
                                            .background(Color.red.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(10)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                        Spacer()
                        Button {
                            Task { await viewModel.toggleQbitSpeedMode() }
                        } label: {
                            Label(
                                qbit.altSpeedEnabled ? "Tortue ON" : "Vitesse Max",
                                systemImage: qbit.altSpeedEnabled ? "tortoise.fill" : "hare.fill"
                            )
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(qbit.altSpeedEnabled ? .orange : .green)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                (qbit.altSpeedEnabled ? Color.orange : Color.green).opacity(0.15),
                                in: Capsule()
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    ForEach(qbit.torrents) { torrent in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(torrent.name)
                                        .font(.caption.weight(.semibold))
                                        .lineLimit(1)
                                    Text("\(String(format: "%.1f %%", torrent.progressPct)) • ↓ \(ByteFormatters.formatSpeed(torrent.dlspeed)) • ↑ \(ByteFormatters.formatSpeed(torrent.upspeed)) • ETA \(ByteFormatters.formatETA(torrent.eta))")
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.secondary)
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
                                    Image(systemName: torrent.isPaused ? "play.circle.fill" : "pause.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(torrent.isPaused ? .green : .orange)
                                }
                                .buttonStyle(.plain)
                            }
                            UsageProgressBar(percentage: torrent.progressPct, tint: torrent.isPaused ? .orange : .cyan)
                        }
                        .padding(10)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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

                if tasks.isEmpty {
                    Text("Aucune tâche récente.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(tasks.prefix(8)) { task in
                        HStack {
                            Image(systemName: task.isSuccess ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                .foregroundStyle(task.isSuccess ? .green : .orange)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(task.type.uppercased()) \(task.vmid.isEmpty ? "" : "#\(task.vmid)")")
                                    .font(.caption.weight(.semibold))
                                Text("\(task.user) • \(ByteFormatters.formatTimestamp(task.starttime))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let sec = task.durationSec {
                                Text("\(sec)s")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
        }
    }
}
