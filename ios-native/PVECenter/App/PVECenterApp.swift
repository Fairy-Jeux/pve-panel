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
                .onOpenURL { url in
                    Task { await viewModel.handleIncomingURL(url) }
                }
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
                .preferredColorScheme(.dark)
        }

        MenuBarExtra("PVE Center", systemImage: "server.rack") {
            MenuBarPanelView(viewModel: viewModel)
                .preferredColorScheme(.dark)
        }
        .menuBarExtraStyle(.window)
        #endif
    }
}

#if os(macOS)
private struct MenuBarPanelView: View {
    var viewModel: AppViewModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let teal = DesignTokens.signalTeal(colorScheme)
        let nominal = DesignTokens.nominal(colorScheme)
        let caution = DesignTokens.caution(colorScheme)

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("PVE Center", systemImage: "server.rack")
                    .font(.headline)
                Spacer()
                StatusPill(
                    viewModel.isDemoMode ? "Mode Démo" : (viewModel.pveOverview?.online == true ? "En ligne" : "Hors ligne"),
                    color: viewModel.isDemoMode ? teal : (viewModel.pveOverview?.online == true ? nominal : caution),
                    systemImage: viewModel.isDemoMode ? "sparkles" : (viewModel.pveOverview?.online == true ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                )
            }

            Divider()

            if let node = viewModel.pveOverview?.node {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Nœud \(node.name)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                        Spacer()
                        Text("\(viewModel.pveOverview?.counts.running ?? 0)/\(viewModel.pveOverview?.counts.total ?? 0) actifs")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                    }
                    HStack {
                        Text("CPU \(String(format: "%.1f %%", node.cpuPct))")
                            .font(.system(.caption, design: .monospaced))
                        Spacer()
                        Text("RAM \(String(format: "%.0f %%", node.memPct))")
                            .font(.system(.caption, design: .monospaced))
                    }
                    UsageProgressBar(percentage: node.cpuPct, tint: teal)
                    UsageProgressBar(percentage: node.memPct, tint: DesignTokens.secondaryText(colorScheme))
                }
            } else {
                Text("Aucune télémétrie chargée. Ouvrez la fenêtre principale ou activez le Mode Démo.")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.secondaryText(colorScheme))
            }

            if let pool = viewModel.pveOverview?.externalStorage?.pool {
                HStack {
                    Label(pool.name, systemImage: "internaldrive.fill")
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                    Text("\(ByteFormatters.formatDecimalTB(pool.usedBytes)) / \(ByteFormatters.formatDecimalTB(pool.totalBytes))")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                }
            }

            if let qbit = viewModel.widgets?.qbittorrent {
                HStack {
                    Label("qBittorrent", systemImage: "arrow.down.arrow.up.circle")
                        .font(.caption)
                    Spacer()
                    Text("↓ \(ByteFormatters.formatSpeed(qbit.dlSpeedBytes))  ↑ \(ByteFormatters.formatSpeed(qbit.upSpeedBytes))")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                }
            }

            if let streams = viewModel.widgets?.jellyfin?.activeStreamsCount, streams > 0 {
                HStack {
                    Label("Jellyfin", systemImage: "play.tv.fill")
                        .font(.caption)
                        .foregroundStyle(teal)
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

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("Quitter", systemImage: "power")
                        .labelStyle(.iconOnly)
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
