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
    @Environment(\.colorScheme) private var colorScheme
    #if os(tvOS)
    @FocusState private var isDemoButtonFocused: Bool
    #endif

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
        _urlInput = State(initialValue: viewModel.serverBaseURL)
    }

    public var body: some View {
        #if os(tvOS)
        tvOSBody
            .fullScreenCover(isPresented: $showSetupWizard) {
                ServerSetupWizardSheet(viewModel: viewModel)
                    .preferredColorScheme(.dark)
            }
        #else
        standardBody
        #endif
    }

    #if os(tvOS)
    private var tvOSBody: some View {
        ZStack {
            AmbientBackgroundView()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Serveurs & Connexion")
                                .font(.largeTitle.weight(.bold))
                                .foregroundStyle(DesignTokens.primaryText(colorScheme))
                            Text("Connectez votre serveur PVE Center ou explorez le Mode Démo sur Apple TV.")
                                .font(.callout)
                                .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                        }
                        Spacer()
                        Button {
                            dismiss()
                        } label: {
                            Label("Fermer", systemImage: "xmark.circle.fill")
                                .padding(.horizontal, 12)
                        }
                        .buttonStyle(.glass)
                    }

                    HStack(alignment: .top, spacing: 32) {
                        VStack(spacing: 24) {
                            GlassCard(padding: 24, cornerRadius: 24) {
                                VStack(alignment: .leading, spacing: 14) {
                                    Label("Mode Démo interactif", systemImage: "sparkles")
                                        .font(.title3.weight(.bold))
                                        .foregroundStyle(.indigo)
                                    Text("Explorez toutes les vues SwiftUI, graphiques Swift Charts et la supervision Proxmox hors-ligne sans serveur.")
                                        .font(.callout)
                                        .foregroundStyle(DesignTokens.secondaryText(colorScheme))

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
                                        .font(.headline)
                                        .foregroundStyle(isDemoButtonFocused ? Color.indigo : Color.white)
                                        .frame(maxWidth: .infinity, minHeight: 54)
                                    }
                                    .buttonStyle(.glassProminent)
                                    .tint(.indigo)
                                    .focused($isDemoButtonFocused)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            GlassCard(padding: 24, cornerRadius: 24) {
                                VStack(alignment: .leading, spacing: 14) {
                                    Text("Serveurs enregistrés (\(viewModel.savedServers.count))")
                                        .font(.title3.weight(.semibold))
                                        .foregroundStyle(DesignTokens.primaryText(colorScheme))

                                    if viewModel.savedServers.isEmpty {
                                        Text("Aucun serveur enregistré pour le moment.")
                                            .font(.callout)
                                            .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                                    } else {
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
                                                    HStack(spacing: 12) {
                                                        Image(systemName: isActive ? "checkmark.circle.fill" : "server.rack")
                                                            .foregroundStyle(isActive ? .green : .cyan)
                                                        VStack(alignment: .leading, spacing: 2) {
                                                            Text(server.name)
                                                                .font(.headline)
                                                            Text(server.baseURL)
                                                                .font(.caption)
                                                                .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                                                                .lineLimit(1)
                                                        }
                                                        Spacer()
                                                    }
                                                }
                                                .buttonStyle(.glass)

                                                Button(role: .destructive) {
                                                    viewModel.removeServer(id: server.id)
                                                } label: {
                                                    Image(systemName: "trash")
                                                }
                                                .buttonStyle(.glass)
                                                .accessibilityLabel("Supprimer \(server.name)")
                                            }
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            GlassCard(padding: 24, cornerRadius: 24) {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Actualisation")
                                        .font(.title3.weight(.semibold))
                                        .foregroundStyle(DesignTokens.primaryText(colorScheme))
                                    Toggle(
                                        "Actualisation automatique (5s)",
                                        isOn: Binding(
                                            get: { viewModel.autoRefresh },
                                            set: { _ in viewModel.toggleAutoRefresh() }
                                        )
                                    )
                                    if let last = viewModel.lastUpdated {
                                        Text("Dernière synchronisation : \(last.formatted(date: .omitted, time: .standard))")
                                            .font(.caption)
                                            .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .frame(maxWidth: .infinity)

                        VStack(spacing: 24) {
                            GlassCard(padding: 24, cornerRadius: 24) {
                                VStack(alignment: .leading, spacing: 14) {
                                    Text("Ajouter ou connecter un serveur")
                                        .font(.title3.weight(.semibold))
                                        .foregroundStyle(DesignTokens.primaryText(colorScheme))

                                    TextField("Nom du serveur (ex: Homelab principal)", text: $serverNameInput)
                                        .autocorrectionDisabled()

                                    TextField("https://pve-panel.votre-tailnet.ts.net ou IP locale", text: $urlInput)
                                        .autocorrectionDisabled()

                                    let connectDisabled = testing || urlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
                                        .frame(maxWidth: .infinity, minHeight: 50)
                                    }
                                    .buttonStyle(.glass)
                                    .disabled(connectDisabled)

                                    if let statusBanner {
                                        Label(
                                            statusBanner.text,
                                            systemImage: statusBanner.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                                        )
                                        .font(.callout)
                                        .foregroundStyle(statusBanner.isError ? .red : .green)
                                    }
                                }
                            }

                            GlassCard(padding: 24, cornerRadius: 24) {
                                VStack(alignment: .leading, spacing: 14) {
                                    Text("Appairage rapide (Deep-Link)")
                                        .font(.title3.weight(.semibold))
                                        .foregroundStyle(DesignTokens.primaryText(colorScheme))

                                    TextField("pvecenter://connect?url=https://...&name=...", text: $deepLinkInput)
                                        .autocorrectionDisabled()

                                    Button {
                                        Task { await importDeepLink() }
                                    } label: {
                                        Label("Importer le lien d'appairage", systemImage: "link.badge.plus")
                                            .frame(maxWidth: .infinity, minHeight: 50)
                                    }
                                    .buttonStyle(.glass)
                                    .disabled(testing || deepLinkInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                }
                            }

                            GlassCard(padding: 24, cornerRadius: 24) {
                                VStack(alignment: .leading, spacing: 14) {
                                    Text("Configuration distante du serveur")
                                        .font(.title3.weight(.semibold))
                                        .foregroundStyle(DesignTokens.primaryText(colorScheme))

                                    Button {
                                        showSetupWizard = true
                                    } label: {
                                        HStack {
                                            Label("Configurer le serveur…", systemImage: "slider.horizontal.3")
                                            Spacer()
                                            if let configured = viewModel.setupStatus?.isConfigured, !configured {
                                                Text("À configurer")
                                                    .font(.caption.weight(.semibold))
                                                    .foregroundStyle(.orange)
                                            }
                                            Image(systemName: "chevron.right")
                                        }
                                        .frame(maxWidth: .infinity, minHeight: 50)
                                    }
                                    .buttonStyle(.glass)
                                    .disabled(viewModel.serverBaseURL.isEmpty && !viewModel.isDemoMode)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 48)
                .padding(.vertical, 36)
            }
        }
        .onAppear {
            isDemoButtonFocused = true
        }
    }
    #endif

    private var standardBody: some View {
        NavigationStack {
            Form {
                if !viewModel.savedServers.isEmpty {
                    savedServersSection
                }

                demoModeSection
                addServerSection
                deepLinkPairingSection
                serverWizardSection
                refreshOptionsSection
            }
            .formStyle(.grouped)
            .navigationTitle("Connexion")
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
                    .foregroundStyle(.white)
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
