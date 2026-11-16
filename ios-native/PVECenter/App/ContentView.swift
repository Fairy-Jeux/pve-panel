import SwiftUI

public struct ContentView: View {
    @Bindable var viewModel: AppViewModel

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            #if os(macOS)
            macOSBody
            #else
            iOSBody
            #endif

            if let toast = viewModel.toast {
                ToastOverlayView(toast: toast)
                    .padding(.bottom, toastBottomPadding)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewModel.toast?.id)
        .sheet(isPresented: $viewModel.showServerSettings) {
            ServerSettingsSheet(viewModel: viewModel)
        }
        .sensoryFeedback(.success, trigger: viewModel.hapticSuccessTrigger)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: viewModel.hapticImpactTrigger)
        .task {
            viewModel.start()
        }
    }

    private var toastBottomPadding: CGFloat {
        #if os(macOS)
        return 22
        #else
        return 64
        #endif
    }

    // MARK: - macOS Native Split View Layout

    #if os(macOS)
    private var sidebarSelectionBinding: Binding<AppTab?> {
        Binding(
            get: { viewModel.selectedTab },
            set: { if let tab = $0 { viewModel.selectedTab = tab } }
        )
    }

    private var macOSBody: some View {
        NavigationSplitView {
            List(selection: sidebarSelectionBinding) {
                Section("Supervision") {
                    sidebarRow(for: .overview)
                    sidebarRow(for: .proxmox)
                    sidebarRow(for: .storage)
                    sidebarRow(for: .services)
                }
                Section("Administration") {
                    sidebarRow(for: .operations, badge: viewModel.pendingRequestsCount)
                    sidebarRow(for: .users)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 210, ideal: 235, max: 275)
            .safeAreaInset(edge: .bottom) {
                sidebarFooter
            }
        } detail: {
            NavigationStack {
                ZStack {
                    AmbientBackgroundView()
                    activeTabContent(for: viewModel.selectedTab)
                }
                .navigationTitle(viewModel.selectedTab == .overview ? "PVE Center" : viewModel.selectedTab.title)
                .searchable(
                    text: $viewModel.searchText,
                    placement: .toolbar,
                    prompt: "Filtrer LXC, VM, disques, services…"
                )
                .toolbar {
                    commonToolbarItems
                }
            }
        }
        .tint(.cyan)
    }

    private func sidebarRow(for tab: AppTab, badge: Int = 0) -> some View {
        Label {
            HStack {
                Text(tab.title)
                if badge > 0 {
                    Spacer()
                    Text("\(badge)")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange, in: Capsule())
                }
            }
        } icon: {
            Image(systemName: tab.systemImage)
                .foregroundStyle(.cyan)
        }
        .tag(tab)
    }

    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            HStack(spacing: 8) {
                StatusPill(
                    viewModel.isDemoMode ? "Mode Démo" : (viewModel.user != nil ? "Tailscale SSO" : "Hors ligne"),
                    color: viewModel.isDemoMode ? .indigo : (viewModel.user != nil ? .green : .orange),
                    systemImage: viewModel.isDemoMode ? "sparkles" : "lock.shield.fill"
                )
                Spacer()
                Button {
                    viewModel.showServerSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Connexion Serveur & Mode Démo")
            }

            if let last = viewModel.lastUpdated {
                Text("MàJ \(last.formatted(date: .omitted, time: .standard))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
    }
    #endif

    // MARK: - iOS Native TabView Layout

    #if !os(macOS)
    private var iOSBody: some View {
        TabView(selection: $viewModel.selectedTab) {
            tabScreen(for: .overview) {
                OverviewTabView(viewModel: viewModel)
            }
            tabScreen(for: .proxmox) {
                ProxmoxTabView(viewModel: viewModel)
            }
            tabScreen(for: .storage) {
                StorageTabView(viewModel: viewModel)
            }
            tabScreen(for: .services) {
                ServicesTabView(viewModel: viewModel)
            }
            tabScreen(for: .operations, badge: viewModel.pendingRequestsCount) {
                OperationsTabView(viewModel: viewModel)
            }
            tabScreen(for: .users) {
                UsersTabView(viewModel: viewModel)
            }
        }
        .tint(.cyan)
        .searchable(text: $viewModel.searchText, prompt: "Filtrer LXC, VM, disques, services…")
    }

    @ViewBuilder
    private func tabScreen<Content: View>(
        for tab: AppTab,
        badge: Int = 0,
        @ViewBuilder content: () -> Content
    ) -> some View {
        NavigationStack {
            ZStack {
                AmbientBackgroundView()
                content()
            }
            .navigationTitle(tab == .overview ? "PVE Center" : tab.title)
            .toolbar {
                commonToolbarItems
            }
        }
        .tabItem {
            Label(tab.title, systemImage: tab.systemImage)
        }
        .tag(tab)
        .badge(badge)
    }
    #endif

    // MARK: - Shared Views & Toolbar

    @ViewBuilder
    private func activeTabContent(for tab: AppTab) -> some View {
        switch tab {
        case .overview:
            OverviewTabView(viewModel: viewModel)
        case .proxmox:
            ProxmoxTabView(viewModel: viewModel)
        case .storage:
            StorageTabView(viewModel: viewModel)
        case .services:
            ServicesTabView(viewModel: viewModel)
        case .operations:
            OperationsTabView(viewModel: viewModel)
        case .users:
            UsersTabView(viewModel: viewModel)
        }
    }

    @ToolbarContentBuilder
    private var commonToolbarItems: some ToolbarContent {
        #if os(macOS)
        ToolbarItem(placement: .automatic) {
            Button {
                viewModel.toggleAutoRefresh()
            } label: {
                Label(
                    viewModel.autoRefresh ? "Live 5s" : "En pause",
                    systemImage: viewModel.autoRefresh ? "pause.circle.fill" : "play.circle"
                )
            }
            .tint(viewModel.autoRefresh ? .green : .secondary)
            .help("Activer/désactiver l'actualisation automatique (⌘L)")
        }
        #endif

        ToolbarItem(placement: .primaryAction) {
            Button {
                viewModel.showServerSettings = true
            } label: {
                Image(systemName: viewModel.isDemoMode ? "sparkles" : "server.rack")
                    .symbolRenderingMode(.hierarchical)
            }
            .accessibilityLabel("Connexion Serveur et Mode Démo")
        }

        ToolbarItem(placement: .automatic) {
            Button {
                Task { await viewModel.refreshAll(silent: false) }
            } label: {
                if viewModel.isRefreshing {
                    ProgressView()
                        #if os(macOS)
                        .controlSize(.small)
                        #endif
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .accessibilityLabel("Rafraîchir")
        }
    }
}
