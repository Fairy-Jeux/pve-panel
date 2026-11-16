import SwiftUI

public struct ServicesTabView: View {
    public var viewModel: AppViewModel
    #if !os(tvOS)
    @Environment(\.openURL) private var openURL
    #endif
    @Environment(\.colorScheme) private var colorScheme

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    private var adaptiveColumns: [GridItem] {
        #if os(tvOS)
        return [GridItem(.adaptive(minimum: 560), spacing: 20)]
        #elseif os(macOS)
        return [GridItem(.adaptive(minimum: 310), spacing: 14)]
        #else
        return [GridItem(.flexible())]
        #endif
    }

    private var gridRowSpacing: CGFloat {
        #if os(tvOS)
        return 20
        #else
        return 14
        #endif
    }

    private var categorySpacing: CGFloat {
        #if os(tvOS)
        return 24
        #else
        return 18
        #endif
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: categorySpacing) {
                ForEach(viewModel.filteredCategories) { category in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(category.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                                .lineLimit(1)
                            Spacer()
                            Text("\(category.services.filter(\.online).count)/\(category.services.count) en ligne")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                                .lineLimit(1)
                        }

                        LazyVGrid(columns: adaptiveColumns, spacing: gridRowSpacing) {
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
            .padding(.horizontal, DesignTokens.pageHorizontalPadding)
            .padding(.vertical, DesignTokens.pageVerticalPadding)
        }
        .contentMargins(.top, 8, for: .scrollContent)
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
        let teal = DesignTokens.signalTeal(colorScheme)
        let nominal = DesignTokens.nominal(colorScheme)
        let critical = DesignTokens.critical(colorScheme)

        return GlassCard(padding: 14, cornerRadius: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: sfSymbol(for: service.icon))
                        .font(.title3)
                        .foregroundStyle(service.online ? teal : critical)
                        .frame(width: 40, height: 40)
                        .background(
                            DesignTokens.surfaceElevated(colorScheme),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(service.name)
                                .font(.headline)
                                .foregroundStyle(DesignTokens.primaryText(colorScheme))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                            Spacer(minLength: 4)
                            if let latency = service.latencyMs, service.online {
                                StatusPill(String(format: "%.0f ms", latency), color: nominal, systemImage: "checkmark.circle.fill")
                            } else {
                                StatusPill(
                                    service.online ? "En ligne" : "Hors ligne",
                                    color: service.online ? nominal : critical,
                                    systemImage: service.online ? "checkmark.circle.fill" : "xmark.octagon.fill"
                                )
                            }
                        }
                        Text(service.description)
                            .font(.caption)
                            .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                            .lineLimit(2)
                    }
                }

                if let widgetKey = service.widget?.lowercased() {
                    widgetStrip(for: widgetKey)
                }

                #if !os(tvOS)
                if let url = URL(string: service.url) {
                    Button {
                        openURL(url)
                    } label: {
                        HStack {
                            Label("Ouvrir l'interface web", systemImage: "safari")
                                .font(.caption.weight(.semibold))
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity, minHeight: 28)
                    }
                    .buttonStyle(.glass)
                }
                #else
                if !service.url.isEmpty {
                    Label(service.url, systemImage: "network")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                #endif
            }
        }
    }

    @ViewBuilder
    private func widgetStrip(for key: String) -> some View {
        switch key {
        case "jellyfin":
            if let jf = viewModel.widgets?.jellyfin {
                HStack(spacing: 8) {
                    miniStat("Flux", "\(jf.activeStreamsCount ?? 0)")
                    miniStat("Films", "\(jf.moviesCount ?? 0)")
                    miniStat("Séries", "\(jf.seriesCount ?? 0)")
                }
            }
        case "plex":
            if let plex = viewModel.widgets?.plex {
                HStack(spacing: 8) {
                    miniStat("Flux", "\(plex.activeStreamsCount ?? 0)")
                    miniStat("Librairies", "\(plex.librariesCount ?? 0)")
                }
            }
        case "radarr":
            if let radarr = viewModel.widgets?.radarr {
                HStack(spacing: 8) {
                    miniStat("Films", "\(radarr.moviesDownloaded ?? 0)/\(radarr.moviesTotal ?? 0)")
                    miniStat("File", "\(radarr.queueCount ?? 0)")
                    miniStat("Manquants", "\(radarr.moviesMissing ?? 0)")
                }
            }
        case "sonarr":
            if let sonarr = viewModel.widgets?.sonarr {
                HStack(spacing: 8) {
                    miniStat("Séries", "\(sonarr.seriesTotal ?? 0)")
                    miniStat("Épisodes", "\(sonarr.episodesDownloaded ?? 0)")
                    miniStat("File", "\(sonarr.queueCount ?? 0)")
                }
            }
        case "prowlarr":
            if let prowlarr = viewModel.widgets?.prowlarr {
                HStack(spacing: 8) {
                    miniStat("Indexeurs", "\(prowlarr.indexersEnabled ?? 0)/\(prowlarr.indexersTotal ?? 0)")
                    miniStat("Grabs", "\(prowlarr.grabs ?? 0)")
                }
            }
        case "qbittorrent":
            if let qbit = viewModel.widgets?.qbittorrent {
                HStack(spacing: 8) {
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
                .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Text(value)
                .font(.system(.caption, design: .monospaced, weight: .semibold))
                .foregroundStyle(DesignTokens.primaryText(colorScheme))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(DesignTokens.surfaceElevated(colorScheme), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
