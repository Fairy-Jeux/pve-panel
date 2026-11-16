import SwiftUI

public struct ServerSettingsSheet: View {
    public var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var urlInput: String
    @State private var testing: Bool = false
    @State private var statusBanner: (isError: Bool, text: String)?

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
        _urlInput = State(initialValue: viewModel.serverBaseURL)
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Mode Démo interactif (App Store Review)", systemImage: "sparkles")
                            .font(.headline)
                            .foregroundStyle(.indigo)
                        Text("Explorez toutes les vues SwiftUI, graphiques Swift Charts et mutations (start/stop LXC, Jellyseerr, qBittorrent, utilisateurs) hors-ligne sans VPN Tailscale.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button {
                            Task {
                                await viewModel.configureConnection(baseURL: urlInput, demoMode: true)
                                dismiss()
                            }
                        } label: {
                            Label(
                                viewModel.isDemoMode ? "Mode Démo déjà actif" : "Activer le Mode Démo",
                                systemImage: "play.fill"
                            )
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.indigo)
                    }
                    .padding(.vertical, 4)
                }

                Section("Serveur Tailscale Serve privé") {
                    TextField("https://pve-panel.votre-tailnet.ts.net", text: $urlInput)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        #endif

                    Button {
                        Task { await verifyAndConnect() }
                    } label: {
                        HStack {
                            Label("Tester et connecter", systemImage: "checkmark.shield.fill")
                            Spacer()
                            if testing {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(testing || urlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if let statusBanner {
                        Label(
                            statusBanner.text,
                            systemImage: statusBanner.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(statusBanner.isError ? .red : .green)
                    }
                }

                Section("Options d'actualisation") {
                    Toggle(
                        "Actualisation automatique (5s)",
                        isOn: Binding(
                            get: { viewModel.autoRefresh },
                            set: { _ in viewModel.toggleAutoRefresh() }
                        )
                    )
                    if let last = viewModel.lastUpdated {
                        HStack {
                            Text("Dernière synchronisation")
                            Spacer()
                            Text(last.formatted(date: .omitted, time: .standard))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
            }
            .navigationTitle("Serveur & Connexion")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }

    private func verifyAndConnect() async {
        testing = true
        statusBanner = nil
        do {
            let user = try await viewModel.testConnection(candidateURL: urlInput)
            statusBanner = (false, "Connecté en tant que \(user.login).")
            await viewModel.configureConnection(baseURL: urlInput, demoMode: false)
            dismiss()
        } catch {
            statusBanner = (true, error.localizedDescription)
        }
        testing = false
    }
}
