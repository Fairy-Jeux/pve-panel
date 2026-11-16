import SwiftUI

private enum IncidentFilter: String, CaseIterable, Identifiable {
    case all = "Tous"
    case active = "Actifs"

    var id: String { rawValue }
}

public struct OperationsTabView: View {
    public var viewModel: AppViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var scanningTarget: String?
    @State private var incidentFilter: IncidentFilter = .all
    @State private var busyIncidentID: String?
    @State private var busyMuteServiceID: String?

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
                incidentsSection
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
        #if os(iOS)
        .sensoryFeedback(.selection, trigger: incidentFilter)
        #endif
    }

    private var displayedIncidents: [IncidentEvent] {
        let q = viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return viewModel.incidents.filter { incident in
            let matchesFilter = incidentFilter == .all || incident.isActive
            let matchesSearch = q.isEmpty
                || incident.title.lowercased().contains(q)
                || incident.serviceName.lowercased().contains(q)
                || incident.message.lowercased().contains(q)
            return matchesFilter && matchesSearch
        }
    }

    private func isServiceMuted(_ serviceId: String) -> Bool {
        guard let svc = viewModel.customServices.first(where: { $0.id == serviceId }),
              let mutedUntil = svc.mutedUntil,
              !mutedUntil.isEmpty else {
            return false
        }
        let isoFractional = ISO8601DateFormatter()
        isoFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFractional.date(from: mutedUntil) ?? ISO8601DateFormatter().date(from: mutedUntil) {
            return date > Date()
        }
        return false
    }

    private var incidentsSection: some View {
        let activeCount = viewModel.activeIncidentsCount
        let critical = DesignTokens.critical(colorScheme)
        let caution = DesignTokens.caution(colorScheme)
        let nominal = DesignTokens.nominal(colorScheme)
        let teal = DesignTokens.signalTeal(colorScheme)

        return GlassCard(padding: Layout.cardPadding) {
            VStack(alignment: .leading, spacing: Layout.cardSpacing) {
                HStack(spacing: 10) {
                    Label("Incidents & Historique d'alertes", systemImage: "bell.badge.waveform.fill")
                        .font(.headline)
                        .foregroundStyle(DesignTokens.primaryText(colorScheme))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 6)
                    if activeCount > 0 {
                        StatusPill("\(activeCount) actif\(activeCount > 1 ? "s" : "")", color: critical, systemImage: "exclamationmark.octagon.fill")
                    } else {
                        StatusPill("Nominal", color: nominal, systemImage: "checkmark.shield.fill")
                    }
                }

                Picker("Filtrer les incidents", selection: $incidentFilter) {
                    ForEach(IncidentFilter.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)

                if displayedIncidents.isEmpty {
                    Text(
                        incidentFilter == .active
                            ? "Aucun incident actif en cours."
                            : "Aucun incident enregistré dans l'historique."
                    )
                    .font(.caption)
                    .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                } else {
                    ForEach(displayedIncidents) { incident in
                        let muted = isServiceMuted(incident.serviceId)
                        let severityColor: Color = !incident.isActive
                            ? nominal
                            : (incident.severity.lowercased() == "warning" ? caution : critical)

                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: !incident.isActive ? "checkmark.shield.fill" : (incident.severity.lowercased() == "warning" ? "exclamationmark.triangle.fill" : "exclamationmark.octagon.fill"))
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(severityColor)

                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(incident.title)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(DesignTokens.primaryText(colorScheme))
                                            .lineLimit(2)
                                        Spacer(minLength: 4)
                                        StatusPill(
                                            incident.isActive ? "Actif" : "Rétabli",
                                            color: severityColor,
                                            systemImage: incident.isActive ? "dot.radiowaves.left.and.right" : "checkmark.circle.fill"
                                        )
                                    }

                                    if !incident.message.isEmpty {
                                        Text(incident.message)
                                            .font(.caption)
                                            .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                                            .lineLimit(2)
                                    }

                                    HStack(spacing: 8) {
                                        Text(incident.serviceName)
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(teal)
                                        Text("• Début \(ByteFormatters.formatRelativeISO(incident.startedAt))")
                                            .font(.caption2)
                                            .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                                        if let resolvedAt = incident.resolvedAt, !resolvedAt.isEmpty {
                                            Text("• Résolu \(ByteFormatters.formatRelativeISO(resolvedAt))")
                                                .font(.caption2)
                                                .foregroundStyle(nominal)
                                        }
                                    }
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                                }
                            }

                            HStack(spacing: 8) {
                                if incident.acknowledged {
                                    StatusPill("Acquitté", color: teal, systemImage: "checkmark.circle")
                                } else {
                                    Button {
                                        Task {
                                            busyIncidentID = incident.id
                                            await viewModel.acknowledgeIncident(id: incident.id)
                                            busyIncidentID = nil
                                        }
                                    } label: {
                                        Label(
                                            busyIncidentID == incident.id ? "Acquittement…" : "Acquitter",
                                            systemImage: "checkmark.circle"
                                        )
                                        .font(.caption.weight(.semibold))
                                        .lineLimit(1)
                                        .frame(minHeight: Layout.smallButtonMinHeight)
                                    }
                                    #if os(tvOS)
                                    .buttonStyle(.glass)
                                    #else
                                    .buttonStyle(.glassProminent)
                                    .tint(teal)
                                    #endif
                                    .disabled(busyIncidentID == incident.id)
                                    .adaptiveSmallControlSize()
                                }

                                if muted {
                                    Button {
                                        Task {
                                            busyMuteServiceID = incident.serviceId
                                            await viewModel.unmuteServiceAlerts(serviceId: incident.serviceId)
                                            busyMuteServiceID = nil
                                        }
                                    } label: {
                                        Label("Réactiver alertes", systemImage: "bell.badge.fill")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(caution)
                                            .lineLimit(1)
                                            .frame(minHeight: Layout.smallButtonMinHeight)
                                    }
                                    .buttonStyle(.glass)
                                    .disabled(busyMuteServiceID == incident.serviceId)
                                    .adaptiveSmallControlSize()
                                } else if incident.isActive {
                                    Button {
                                        Task {
                                            busyMuteServiceID = incident.serviceId
                                            await viewModel.muteServiceAlerts(serviceId: incident.serviceId, minutes: 60)
                                            busyMuteServiceID = nil
                                        }
                                    } label: {
                                        Label("Sourdine 1h", systemImage: "bell.slash")
                                            .font(.caption.weight(.semibold))
                                            .lineLimit(1)
                                            .frame(minHeight: Layout.smallButtonMinHeight)
                                    }
                                    .buttonStyle(.glass)
                                    .disabled(busyMuteServiceID == incident.serviceId)
                                    .adaptiveSmallControlSize()
                                }

                                Spacer(minLength: 0)
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
