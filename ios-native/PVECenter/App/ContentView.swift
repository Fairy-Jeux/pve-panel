import SwiftUI

public struct ContentView: View {
    @Bindable var viewModel: AppViewModel

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
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

            if let toast = viewModel.toast {
                ToastOverlayView(toast: toast)
                    .padding(.bottom, 64)
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
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .accessibilityLabel("Rafraîchir")
                }
            }
        }
        .tabItem {
            Label(tab.title, systemImage: tab.systemImage)
        }
        .tag(tab)
        .badge(badge)
    }
}
