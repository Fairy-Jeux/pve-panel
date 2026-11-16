import SwiftUI

public struct ServicesTabView: View {
    public var viewModel: AppViewModel
    @Environment(\.openURL) private var openURL

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    private var adaptiveColumns: [GridItem] {
        #if os(macOS)
        return [GridItem(.adaptive(minimum: 310), spacing: 14)]
        #else
        return [GridItem(.flexible())]
        #endif
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                ForEach(viewModel.filteredCategories) { category in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(category.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(category.services.filter(\.online).count)/\(category.services.count) en ligne")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        LazyVGrid(columns: adaptiveColumns, spacing: 14) {
                            ForEach(category.services) { service in
                                serviceCard(service)
                            }
                        }
                    }
                }

                if viewModel.filteredCategories.isEmpty {
                    GlassCard {
                        ContentUnavailableView(
                            "Aucun service trouvé",
                            systemImage: "magnifyingglass",
                            description: Text("Essayez un autre mot-clé dans la barre de recherche.")
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
    }

    private func sfSymbol(for icon: String) -> String {
        switch icon.lowercased() {
        case "film", "tv": return "play.tv.fill"
        case "clapperboard": return "film.stack.fill"
        case "sparkles": return "sparkles"
        case "search": return "magnifyingglass.circle.fill"
        case "download": return "arrow.down.circle.fill"
        case "server": return "server.rack"
        case "shield": return "lock.shield.fill"
        case "database": return "cylinder.split.1x2.fill"
        default: return "app.connected.to.app.below.fill"
        }
    }

    private func serviceCard(_ service: ServiceItem) -> some View {
        GlassCard(padding: 14, cornerRadius: 20) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: sfSymbol(for: service.icon))
                        .font(.title3)
                        .foregroundStyle(service.online ? .cyan : .red)
                        .frame(width: 40, height: 40)
                        .background(
                            (service.online ? Color.cyan : Color.red).opacity(0.13),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(service.name)
                                .font(.headline)
                            Spacer()
                            if let latency = service.latencyMs, service.online {
                                StatusPill(String(format: "%.0f ms", latency), color: .green)
                            } else {
                                StatusPill(service.online ? "En ligne" : "Hors ligne", color: service.online ? .green : .red)
                            }
                        }
                        Text(service.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                if let widgetKey = service.widget?.lowercased() {
                    widgetStrip(for: widgetKey)
                }

                if let url = URL(string: service.url) {
                    Button {
                        openURL(url)
                    } label: {
                        HStack {
                            Text("Ouvrir l'interface web")
                                .font(.caption.weight(.semibold))
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(.cyan)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.cyan.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func widgetStrip(for key: String) -> some View {
        switch key {
        case "jellyfin":
            if let jf = viewModel.widgets?.jellyfin {
                HStack(spacing: 12) {
                    miniStat("Flux", "\(jf.activeStreamsCount ?? 0)")
                    miniStat("Films", "\(jf.moviesCount ?? 0)")
                    miniStat("Séries", "\(jf.seriesCount ?? 0)")
                }
            }
        case "plex":
            if let plex = viewModel.widgets?.plex {
                HStack(spacing: 12) {
                    miniStat("Flux", "\(plex.activeStreamsCount ?? 0)")
                    miniStat("Librairies", "\(plex.librariesCount ?? 0)")
                }
            }
        case "radarr":
            if let radarr = viewModel.widgets?.radarr {
                HStack(spacing: 12) {
                    miniStat("Films", "\(radarr.moviesDownloaded ?? 0)/\(radarr.moviesTotal ?? 0)")
                    miniStat("File", "\(radarr.queueCount ?? 0)")
                    miniStat("Manquants", "\(radarr.moviesMissing ?? 0)")
                }
            }
        case "sonarr":
            if let sonarr = viewModel.widgets?.sonarr {
                HStack(spacing: 12) {
                    miniStat("Séries", "\(sonarr.seriesTotal ?? 0)")
                    miniStat("Épisodes", "\(sonarr.episodesDownloaded ?? 0)")
                    miniStat("File", "\(sonarr.queueCount ?? 0)")
                }
            }
        case "prowlarr":
            if let prowlarr = viewModel.widgets?.prowlarr {
                HStack(spacing: 12) {
                    miniStat("Indexeurs", "\(prowlarr.indexersEnabled ?? 0)/\(prowlarr.indexersTotal ?? 0)")
                    miniStat("Grabs", "\(prowlarr.grabs ?? 0)")
                }
            }
        case "qbittorrent":
            if let qbit = viewModel.widgets?.qbittorrent {
                HStack(spacing: 12) {
                    miniStat("DL", ByteFormatters.formatSpeed(qbit.dlSpeedBytes))
                    miniStat("UP", ByteFormatters.formatSpeed(qbit.upSpeedBytes))
                    miniStat("Torrents", "\(qbit.torrentsTotal ?? 0)")
                }
            }
        default:
            EmptyView()
        }
    }

    private func miniStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
