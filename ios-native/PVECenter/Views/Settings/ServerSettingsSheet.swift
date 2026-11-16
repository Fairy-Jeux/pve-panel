import SwiftUI

public struct ServerSettingsSheet: View {
    public var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var serverNameInput: String = ""
    @State private var urlInput: String
    @State private var deepLinkInput: String = ""
    @State private var testing: Bool = false
    @State private var statusBanner: (isError: Bool, text: String)?
    @State private var showSetupWizard: Bool = false

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
        _urlInput = State(initialValue: viewModel.serverBaseURL)
    }

    public var body: some View {
        NavigationStack {
            Form {
                if !viewModel.savedServers.isEmpty {
                    savedServersSection
                }

                addServerSection
                deepLinkPairingSection
                serverWizardSection
                demoModeSection
                refreshOptionsSection
            }
            .formStyle(.grouped)
            .navigationTitle("Serveurs & Connexion")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
            .sheet(isPresented: $showSetupWizard) {
                ServerSetupWizardSheet(viewModel: viewModel)
                    .preferredColorScheme(.dark)
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, idealWidth: 580, minHeight: 560)
        #endif
    }

    // MARK: - Sections

    private var savedServersSection: some View {
        Section("Serveurs enregistrés (\(viewModel.savedServers.count))") {
            ForEach(viewModel.savedServers) { server in
                let isActive = !viewModel.isDemoMode
                    && server.baseURL.caseInsensitiveCompare(viewModel.serverBaseURL) == .orderedSame
                HStack(spacing: 12) {
                    Button {
                        Task {
                            await viewModel.addOrSelectServer(name: server.name, baseURL: server.baseURL)
                            dismiss()
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: isActive ? "checkmark.circle.fill" : "server.rack")
                                .foregroundStyle(isActive ? .green : .cyan)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(server.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    if isActive {
                                        Text("Actif")
                                            .font(.caption2.weight(.bold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(.green.opacity(0.2), in: Capsule())
                                            .foregroundStyle(.green)
                                    }
                                }
                                Text(server.baseURL)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button(role: .destructive) {
                        viewModel.removeServer(id: server.id)
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Supprimer \(server.name)")
                }
            }
        }
    }

    private var addServerSection: some View {
        Section("Ajouter ou connecter un serveur") {
            TextField("Nom du serveur (ex: Homelab principal)", text: $serverNameInput)
                .autocorrectionDisabled()

            TextField("https://pve-panel.votre-tailnet.ts.net ou IP locale", text: $urlInput)
                .autocorrectionDisabled()
                #if os(iOS)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                #endif

            Button {
                Task { await verifyAndAddServer() }
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
    }

    private var deepLinkPairingSection: some View {
        Section("Appairage rapide (Deep-Link)") {
            TextField("pvecenter://connect?url=https://...&name=...", text: $deepLinkInput)
                .autocorrectionDisabled()
                #if os(iOS)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                #endif

            Button {
                Task { await importDeepLink() }
            } label: {
                Label("Importer le lien d'appairage", systemImage: "link.badge.plus")
            }
            .disabled(testing || deepLinkInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var serverWizardSection: some View {
        Section("Configuration distante du serveur") {
            Button {
                showSetupWizard = true
            } label: {
                HStack {
                    Label("Configurer les fonctionnalités du serveur…", systemImage: "slider.horizontal.3")
                    Spacer()
                    if let configured = viewModel.setupStatus?.isConfigured, !configured {
                        Text("À configurer")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(viewModel.serverBaseURL.isEmpty && !viewModel.isDemoMode)
        }
    }

    private var demoModeSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label("Mode Démo interactif (App Store Review)", systemImage: "sparkles")
                    .font(.headline)
                    .foregroundStyle(.indigo)
                Text("Explorez toutes les vues SwiftUI, graphiques Swift Charts et l'assistant de configuration hors-ligne sans VPN Tailscale.")
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
    }

    private var refreshOptionsSection: some View {
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

    // MARK: - Actions

    private func verifyAndAddServer() async {
        testing = true
        statusBanner = nil

        var targetURL = urlInput
        var targetName = serverNameInput
        if let parsed = AppViewModel.parseConnectDeepLink(urlInput) {
            targetURL = parsed.url
            if targetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                targetName = parsed.name
            }
        }

        do {
            let user = try await viewModel.testConnection(candidateURL: targetURL)
            statusBanner = (false, "Connecté en tant que \(user.login).")
            await viewModel.addOrSelectServer(name: targetName, baseURL: targetURL)
            dismiss()
        } catch {
            statusBanner = (true, error.localizedDescription)
        }
        testing = false
    }

    private func importDeepLink() async {
        let trimmed = deepLinkInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), AppViewModel.parseConnectDeepLink(url: url) != nil else {
            statusBanner = (true, "Lien pvecenter://connect?url=... invalide.")
            return
        }
        testing = true
        statusBanner = nil
        await viewModel.handleIncomingURL(url)
        testing = false
        if viewModel.connectionError == nil {
            dismiss()
        } else {
            statusBanner = (true, viewModel.connectionError ?? "Connexion impossible.")
        }
    }
}
