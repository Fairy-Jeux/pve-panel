import SwiftUI

private enum SettingsModalRoute: String, Identifiable {
    case setupWizard
    case onboarding
    case yamlEditor
    case notifications
    case appleTVPairing
    case qrScanner

    var id: String { rawValue }
}

public struct ServerSettingsSheet: View {
    public var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var serverNameInput: String = ""
    @State private var urlInput: String
    @State private var tokenInput: String = ""
    @State private var activeTokenEdit: String = ""
    @State private var deepLinkInput: String = ""
    @State private var testing: Bool = false
    @State private var statusBanner: (isError: Bool, text: String)?
    @State private var activeModal: SettingsModalRoute?

    #if os(tvOS)
    @FocusState private var isDemoButtonFocused: Bool
    #endif

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
        _urlInput = State(initialValue: viewModel.serverBaseURL)
    }

    private var appearanceBinding: Binding<AppearanceMode> {
        Binding(
            get: { viewModel.appearanceMode },
            set: { viewModel.setAppearanceMode($0) }
        )
    }

    public var body: some View {
        Group {
            #if os(tvOS)
            tvOSBody
                .fullScreenCover(item: $activeModal) { route in
                    modalView(for: route)
                        .preferredColorScheme(viewModel.preferredColorScheme)
                }
            #else
            standardBody
                .sheet(item: $activeModal) { route in
                    modalView(for: route)
                        .preferredColorScheme(viewModel.preferredColorScheme)
                }
            #endif
        }
        .preferredColorScheme(viewModel.preferredColorScheme)
        .onAppear {
            viewModel.discoveryService.startPVEDiscovery()
            #if os(tvOS)
            isDemoButtonFocused = true
            #endif
        }
    }

    @ViewBuilder
    private func modalView(for route: SettingsModalRoute) -> some View {
        switch route {
        case .setupWizard:
            ServerSetupWizardSheet(viewModel: viewModel)
        case .onboarding:
            OnboardingFlowView(viewModel: viewModel)
        case .yamlEditor:
            YAMLConfigEditorView(viewModel: viewModel)
        case .notifications:
            NotificationsSettingsView(viewModel: viewModel)
        case .appleTVPairing:
            AppleTVPairingView(viewModel: viewModel)
        case .qrScanner:
            QRScannerView { scanned in
                serverURLInputApply(scanned)
            }
        }
    }

    // MARK: - tvOS 10-Foot Body

    #if os(tvOS)
    private var tvOSBody: some View {
        ZStack {
            AmbientBackgroundView()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Paramètres & Connexion")
                                .font(.largeTitle.weight(.bold))
                                .foregroundStyle(DesignTokens.primaryText(colorScheme))
                            Text("Serveurs, apparence, notifications, YAML et appairage Apple TV.")
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
                                    Label("Apparence", systemImage: "circle.lefthalf.filled")
                                        .font(.title3.weight(.bold))
                                        .foregroundStyle(DesignTokens.primaryText(colorScheme))

                                    Picker("Apparence", selection: appearanceBinding) {
                                        ForEach(AppearanceMode.allCases) { mode in
                                            Label(mode.title, systemImage: mode.systemImage).tag(mode)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            GlassCard(padding: 24, cornerRadius: 24) {
                                VStack(alignment: .leading, spacing: 14) {
                                    Label("Outils & Configuration avancée", systemImage: "wrench.and.screwdriver.fill")
                                        .font(.title3.weight(.bold))
                                        .foregroundStyle(DesignTokens.primaryText(colorScheme))

                                    quickLinkButton(
                                        title: "Appairage Apple TV (PIN 6 chiffres)",
                                        systemImage: "appletv.fill",
                                        route: .appleTVPairing
                                    )
                                    quickLinkButton(
                                        title: "Notifications & Webhooks",
                                        systemImage: "bell.badge.fill",
                                        route: .notifications
                                    )
                                    quickLinkButton(
                                        title: "Configuration YAML (lecture)",
                                        systemImage: "doc.text.fill",
                                        route: .yamlEditor
                                    )
                                    quickLinkButton(
                                        title: "Relancer l'assistant d'installation",
                                        systemImage: "wand.and.stars",
                                        route: .onboarding
                                    )
                                }
                            }

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
                        }
                        .frame(maxWidth: .infinity)

                        VStack(spacing: 24) {
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
                                                        await viewModel.setActiveServer(server)
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
                                VStack(alignment: .leading, spacing: 14) {
                                    Text("Ajouter ou connecter un serveur")
                                        .font(.title3.weight(.semibold))
                                        .foregroundStyle(DesignTokens.primaryText(colorScheme))

                                    TextField("Nom du serveur", text: $serverNameInput)
                                        .autocorrectionDisabled()
                                    TextField("https://pve-panel.votre-tailnet.ts.net ou IP locale", text: $urlInput)
                                        .autocorrectionDisabled()
                                    SecureField("Jeton Bearer (optionnel)", text: $tokenInput)

                                    let connectDisabled = testing || urlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    Button {
                                        Task { await verifyAndAddServer() }
                                    } label: {
                                        HStack {
                                            Label("Tester et connecter", systemImage: "checkmark.shield.fill")
                                            Spacer()
                                            if testing { ProgressView() }
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
                                    Text("Proxmox, Tailscale & Actualisation")
                                        .font(.title3.weight(.semibold))
                                        .foregroundStyle(DesignTokens.primaryText(colorScheme))

                                    Button {
                                        activeModal = .setupWizard
                                    } label: {
                                        HStack {
                                            Label("Configurer Proxmox, Tailscale & Médias…", systemImage: "slider.horizontal.3")
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                        }
                                        .frame(maxWidth: .infinity, minHeight: 50)
                                    }
                                    .buttonStyle(.glass)
                                    .disabled(viewModel.serverBaseURL.isEmpty && !viewModel.isDemoMode)

                                    Toggle(
                                        "Actualisation automatique (5s)",
                                        isOn: Binding(
                                            get: { viewModel.autoRefresh },
                                            set: { _ in viewModel.toggleAutoRefresh() }
                                        )
                                    )
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
    }

    private func quickLinkButton(title: String, systemImage: String, route: SettingsModalRoute) -> some View {
        Button {
            activeModal = route
        } label: {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                Image(systemName: "chevron.right")
            }
            .frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(.glass)
    }
    #endif

    // MARK: - iOS & macOS Form Body

    private var standardBody: some View {
        NavigationStack {
            Form {
                appearanceSection
                quickLinksSection

                if !viewModel.savedServers.isEmpty {
                    savedServersSection
                }

                if !viewModel.discoveryService.pveServers.isEmpty {
                    bonjourDiscoverySection
                }

                addServerSection
                deepLinkPairingSection
                proxmoxTailscaleQuickSection
                demoModeSection
                refreshOptionsSection
            }
            .formStyle(.grouped)
            .navigationTitle("Paramètres & Connexion")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 560, idealWidth: 620, minHeight: 600)
        #endif
    }

    // MARK: - Sections

    private var appearanceSection: some View {
        Section("Apparence") {
            Picker("Apparence", selection: appearanceBinding) {
                ForEach(AppearanceMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.systemImage).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var quickLinksSection: some View {
        Section("Outils & Configuration avancée") {
            Button {
                activeModal = .notifications
            } label: {
                quickLinkRow(
                    title: "Notifications & Alertes (APNs / Webhooks)",
                    subtitle: "Permissions Apple, APNs serveur, Discord, Telegram, ntfy",
                    systemImage: "bell.badge.fill",
                    tint: .orange
                )
            }
            .buttonStyle(.plain)

            Button {
                activeModal = .yamlEditor
            } label: {
                quickLinkRow(
                    title: "Éditeur YAML & Rechargement à chaud",
                    subtitle: "Consulter, valider, modifier et exporter config.yaml",
                    systemImage: "doc.text.magnifyingglass",
                    tint: DesignTokens.signalTeal(colorScheme)
                )
            }
            .buttonStyle(.plain)
            .disabled(viewModel.serverBaseURL.isEmpty && !viewModel.isDemoMode)

            Button {
                activeModal = .appleTVPairing
            } label: {
                quickLinkRow(
                    title: "Appairage Apple TV (PIN 6 chiffres)",
                    subtitle: "Transfert chiffré CryptoKit P-256 + AES-GCM",
                    systemImage: "appletv.fill",
                    tint: .cyan
                )
            }
            .buttonStyle(.plain)

            Button {
                activeModal = .onboarding
            } label: {
                quickLinkRow(
                    title: "Relancer l'assistant d'installation",
                    subtitle: "Assistant en 4 étapes (Bonjour, Sécurité, Services, Résumé)",
                    systemImage: "wand.and.stars",
                    tint: .indigo
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func quickLinkRow(title: String, subtitle: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    private var savedServersSection: some View {
        Section("Serveurs enregistrés (\(viewModel.savedServers.count))") {
            ForEach(viewModel.savedServers) { server in
                let isActive = !viewModel.isDemoMode
                    && server.baseURL.caseInsensitiveCompare(viewModel.serverBaseURL) == .orderedSame
                let hasToken = viewModel.keychainStore.readBearerToken(profileID: server.id) != nil

                HStack(spacing: 12) {
                    Button {
                        Task {
                            await viewModel.setActiveServer(server)
                            dismiss()
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: isActive ? "checkmark.circle.fill" : "server.rack")
                                .foregroundStyle(isActive ? .green : .cyan)
                            VStack(alignment: .leading, spacing: 3) {
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
                                    if server.usesTailscaleSSO {
                                        Text("SSO")
                                            .font(.caption2.weight(.semibold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(.cyan.opacity(0.16), in: Capsule())
                                            .foregroundStyle(.cyan)
                                    }
                                    if hasToken {
                                        Image(systemName: "key.fill")
                                            .font(.caption2)
                                            .foregroundStyle(.orange)
                                            .accessibilityLabel("Jeton stocké dans le Trousseau")
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

            if viewModel.activeServerProfile != nil && !viewModel.isDemoMode {
                HStack(spacing: 8) {
                    SecureField(
                        viewModel.hasActiveToken ? "Mettre à jour le jeton Bearer actif" : "Ajouter un jeton Bearer (Trousseau)",
                        text: $activeTokenEdit
                    )
                    Button("Appliquer") {
                        Task {
                            await viewModel.saveBearerToken(activeTokenEdit)
                            activeTokenEdit = ""
                            await viewModel.refreshAll(silent: false)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(activeTokenEdit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if viewModel.hasActiveToken {
                        Button(role: .destructive) {
                            Task { await viewModel.clearBearerToken() }
                        } label: {
                            Image(systemName: "key.slash")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Effacer le jeton du Trousseau")
                    }
                }
            }
        }
    }

    private var bonjourDiscoverySection: some View {
        Section("Découverte locale Bonjour (_pvecenter._tcp)") {
            ForEach(viewModel.discoveryService.pveServers) { server in
                Button {
                    urlInput = server.resolvedBaseUrl
                    serverNameInput = server.name
                    Task { await verifyAndAddServer() }
                } label: {
                    HStack {
                        Image(systemName: "bonjour")
                            .foregroundStyle(DesignTokens.signalTeal(colorScheme))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(server.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(server.resolvedBaseUrl)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text("Connecter")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(DesignTokens.signalTeal(colorScheme))
                    }
                }
                .buttonStyle(.plain)
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

            SecureField("Jeton Bearer API (optionnel si Tailscale SSO)", text: $tokenInput)

            #if os(iOS)
            Button {
                activeModal = .qrScanner
            } label: {
                Label("Scanner un QR Code de connexion", systemImage: "qrcode.viewfinder")
            }
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

    private var proxmoxTailscaleQuickSection: some View {
        Section("Proxmox VE & Tailscale (Configuration rapide)") {
            if let status = viewModel.setupStatus {
                if !status.env.pveHost.isEmpty {
                    LabeledContent("Hôte Proxmox", value: status.env.pveHost)
                        .font(.caption)
                }
                if !status.env.pveNode.isEmpty {
                    LabeledContent("Nœud PVE", value: status.env.pveNode)
                        .font(.caption)
                }
                if !status.tailscaleUrl.isEmpty {
                    LabeledContent("Tailscale Serve", value: status.tailscaleUrl)
                        .font(.caption)
                }
                if !status.env.allowedTailscaleUsers.isEmpty {
                    LabeledContent("Utilisateurs autorisés", value: status.env.allowedTailscaleUsers)
                        .font(.caption)
                }
            }

            Button {
                activeModal = .setupWizard
            } label: {
                HStack {
                    Label("Configurer Proxmox, Tailscale & Médias…", systemImage: "slider.horizontal.3")
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
        Section("Synchronisation & Temps réel") {
            LabeledContent("Flux temps réel", value: viewModel.realtimeState.label)
                .font(.caption)

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

    private func serverURLInputApply(_ scanned: QRScannedConnection) {
        urlInput = scanned.baseURL
        if serverNameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            serverNameInput = scanned.serverName
        }
        if let token = scanned.token, !token.isEmpty {
            tokenInput = token
        }
        Task { await verifyAndAddServer() }
    }

    private func verifyAndAddServer() async {
        testing = true
        statusBanner = nil

        var targetURL = urlInput
        var targetName = serverNameInput
        var targetToken: String? = tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if targetToken?.isEmpty == true { targetToken = nil }

        if let url = URL(string: urlInput.trimmingCharacters(in: .whitespacesAndNewlines)),
           let parsed = AppViewModel.parseConnectDeepLinkPayload(url: url) {
            targetURL = parsed.url
            if targetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                targetName = parsed.name
            }
            if targetToken == nil {
                targetToken = parsed.token
            }
        }

        do {
            let user = try await viewModel.testConnection(candidateURL: targetURL, bearerToken: targetToken)
            statusBanner = (false, "Connecté en tant que \(user.login).")
            await viewModel.addOrSelectServer(
                name: targetName,
                baseURL: targetURL,
                bearerToken: targetToken,
                usesTailscaleSSO: targetToken == nil
            )
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
