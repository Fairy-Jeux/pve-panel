import SwiftUI
#if os(macOS)
import AppKit
#endif

@main
public struct PVECenterApp: App {
    @State private var viewModel = AppViewModel()

    public init() {}

    public var body: some Scene {
        WindowGroup("PVE Center", id: "main") {
            ContentView(viewModel: viewModel)
                #if os(macOS)
                .frame(minWidth: 880, minHeight: 580)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 1120, height: 760)
        .commands {
            CommandMenu("Supervision") {
                Button("Rafraîchir maintenant") {
                    Task { await viewModel.refreshAll(silent: false) }
                }
                .keyboardShortcut("r", modifiers: .command)

                Button(viewModel.autoRefresh ? "Mettre l'actualisation auto en pause" : "Activer l'actualisation auto (5s)") {
                    viewModel.toggleAutoRefresh()
                }
                .keyboardShortcut("l", modifiers: .command)

                Button("Connexion Serveur & Mode Démo…") {
                    viewModel.showServerSettings = true
                }
                .keyboardShortcut(";", modifiers: .command)

                Divider()

                ForEach(Array(AppTab.allCases.enumerated()), id: \.element.id) { index, tab in
                    Button(tab.title) {
                        viewModel.selectedTab = tab
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                }
            }
        }
        #endif

        #if os(macOS)
        Settings {
            ServerSettingsSheet(viewModel: viewModel)
        }

        MenuBarExtra("PVE Center", systemImage: "server.rack") {
            MenuBarPanelView(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)
        #endif
    }
}

#if os(macOS)
private struct MenuBarPanelView: View {
    var viewModel: AppViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("PVE Center", systemImage: "server.rack")
                    .font(.headline)
                Spacer()
                StatusPill(
                    viewModel.isDemoMode ? "Mode Démo" : (viewModel.pveOverview?.online == true ? "En ligne" : "Hors ligne"),
                    color: viewModel.isDemoMode ? .indigo : (viewModel.pveOverview?.online == true ? .green : .orange)
                )
            }

            Divider()

            if let node = viewModel.pveOverview?.node {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Nœud \(node.name)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(viewModel.pveOverview?.counts.running ?? 0)/\(viewModel.pveOverview?.counts.total ?? 0) actifs")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("CPU \(String(format: "%.1f %%", node.cpuPct))")
                            .font(.caption.monospacedDigit())
                        Spacer()
                        Text("RAM \(String(format: "%.0f %%", node.memPct))")
                            .font(.caption.monospacedDigit())
                    }
                    UsageProgressBar(percentage: node.cpuPct, tint: .cyan)
                    UsageProgressBar(percentage: node.memPct, tint: .indigo)
                }
            } else {
                Text("Aucune télémétrie chargée. Ouvrez la fenêtre principale ou activez le Mode Démo.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let pool = viewModel.pveOverview?.externalStorage?.pool {
                HStack {
                    Label(pool.name, systemImage: "internaldrive.fill")
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                    Text("\(ByteFormatters.formatDecimalTB(pool.usedBytes)) / \(ByteFormatters.formatDecimalTB(pool.totalBytes))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if let qbit = viewModel.widgets?.qbittorrent {
                HStack {
                    Label("qBittorrent", systemImage: "arrow.down.arrow.up.circle")
                        .font(.caption)
                    Spacer()
                    Text("↓ \(ByteFormatters.formatSpeed(qbit.dlSpeedBytes))  ↑ \(ByteFormatters.formatSpeed(qbit.upSpeedBytes))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if let streams = viewModel.widgets?.jellyfin?.activeStreamsCount, streams > 0 {
                HStack {
                    Label("Jellyfin", systemImage: "play.tv.fill")
                        .font(.caption)
                        .foregroundStyle(.cyan)
                    Spacer()
                    Text("\(streams) flux actif\(streams > 1 ? "s" : "")")
                        .font(.caption2.weight(.semibold))
                }
            }

            Divider()

            HStack(spacing: 8) {
                Button {
                    Task { await viewModel.refreshAll(silent: false) }
                } label: {
                    Label("Actualiser", systemImage: "arrow.clockwise")
                }

                if viewModel.opsOverview?.qbitControl.available == true {
                    let turtle = viewModel.opsOverview?.qbitControl.altSpeedEnabled == true
                    Button {
                        Task { await viewModel.toggleQbitSpeedMode() }
                    } label: {
                        Label(turtle ? "Tortue ON" : "Tortue", systemImage: "tortoise.fill")
                    }
                    .tint(turtle ? .orange : .secondary)
                }

                Spacer()

                Button("Ouvrir") {
                    openWindow(id: "main")
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .help("Quitter PVE Center")
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 320)
    }
}
#endif
