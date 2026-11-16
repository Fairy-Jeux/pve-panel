import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
public final class AppViewModel {
    private enum StorageKeys {
        static let serverURL = "pve_native_server_url"
        static let savedServers = "pve_native_saved_servers"
        static let demoMode = "pve_native_demo_mode"
        static let autoRefresh = "pve_native_auto_refresh"
    }

    private let api = APIClient()
    private var pollingTask: Task<Void, Never>?

    // MARK: - Connection & UI State
    public var serverBaseURL: String
    public var savedServers: [SavedServerProfile] = []
    public var isDemoMode: Bool
    public var autoRefresh: Bool
    public var showServerSettings: Bool = false
    public var showServerSetupWizard: Bool = false
    public var pendingOpenSetupWizard: Bool = false

    public var selectedTab: AppTab = .overview
    public var searchText: String = ""

    public var isInitialLoading: Bool = true
    public var isRefreshing: Bool = false
    public var connectionError: String?
    public var lastUpdated: Date?

    public var toast: ToastMessage?
    public var hapticSuccessTrigger: Int = 0
    public var hapticImpactTrigger: Int = 0

    // MARK: - Domain State
    public var user: AuthUser?
    public var pveOverview: PveOverview?
    public var categories: [ServiceCategory] = []
    public var widgets: WidgetsMap?
    public var usersOverview: UsersOverview?
    public var opsOverview: OpsOverview?
    public var setupStatus: SetupStatusResponse?

    public init() {
        let defaults = UserDefaults.standard
        let savedURL = APIClient.normalizeBaseURL(defaults.string(forKey: StorageKeys.serverURL) ?? "")
        let savedDemo = defaults.bool(forKey: StorageKeys.demoMode)
        let savedAutoRefresh = defaults.object(forKey: StorageKeys.autoRefresh) as? Bool ?? true

        self.serverBaseURL = savedURL
        self.isDemoMode = savedDemo
        self.autoRefresh = savedAutoRefresh

        if let data = defaults.data(forKey: StorageKeys.savedServers),
           let decoded = try? JSONDecoder().decode([SavedServerProfile].self, from: data) {
            self.savedServers = decoded
        } else if !savedURL.isEmpty {
            let migrated = SavedServerProfile(
                name: Self.defaultServerName(for: savedURL),
                baseURL: savedURL
            )
            self.savedServers = [migrated]
            persistSavedServers()
        }

        if savedURL.isEmpty && !savedDemo {
            self.isInitialLoading = false
            self.showServerSettings = true
        }
    }

    public var activeServerName: String {
        if isDemoMode { return "Mode Démo" }
        if let profile = savedServers.first(where: {
            $0.baseURL.caseInsensitiveCompare(serverBaseURL) == .orderedSame
        }) {
            return profile.name
        }
        return serverBaseURL.isEmpty ? "Aucun serveur" : Self.defaultServerName(for: serverBaseURL)
    }

    private static func defaultServerName(for baseURL: String) -> String {
        if let host = URL(string: baseURL)?.host, !host.isEmpty {
            return host.split(separator: ".").first.map(String.init) ?? host
        }
        return baseURL.isEmpty ? "Serveur PVE" : baseURL
    }

    private func persistSavedServers() {
        if let data = try? JSONEncoder().encode(savedServers) {
            UserDefaults.standard.set(data, forKey: StorageKeys.savedServers)
        }
    }

    private func resetDomainState() {
        user = nil
        pveOverview = nil
        categories = []
        widgets = nil
        usersOverview = nil
        opsOverview = nil
        setupStatus = nil
        lastUpdated = nil
        connectionError = nil
    }

    // MARK: - Lifecycle & Polling

    public func start() {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshAll(silent: false)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { break }
                if self.autoRefresh && !self.showServerSettings && !self.showServerSetupWizard {
                    await self.refreshAll(silent: true)
                }
            }
        }
    }

    public func toggleAutoRefresh() {
        autoRefresh.toggle()
        UserDefaults.standard.set(autoRefresh, forKey: StorageKeys.autoRefresh)
        hapticImpactTrigger += 1
    }

    public func configureConnection(baseURL: String, demoMode: Bool) async {
        let normalized = APIClient.normalizeBaseURL(baseURL)
        if serverBaseURL != normalized || isDemoMode != demoMode {
            resetDomainState()
        }
        self.serverBaseURL = normalized
        self.isDemoMode = demoMode
        self.connectionError = nil

        let defaults = UserDefaults.standard
        defaults.set(normalized, forKey: StorageKeys.serverURL)
        defaults.set(demoMode, forKey: StorageKeys.demoMode)

        showServerSettings = false
        hapticSuccessTrigger += 1
        await refreshAll(silent: false)
    }

    public func addOrSelectServer(name: String, baseURL: String) async {
        let normalized = APIClient.normalizeBaseURL(baseURL)
        guard !normalized.isEmpty else {
            showToast("L'URL du serveur est invalide.", isError: true)
            return
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmedName.isEmpty ? Self.defaultServerName(for: normalized) : trimmedName

        if let existingIndex = savedServers.firstIndex(where: {
            $0.baseURL.caseInsensitiveCompare(normalized) == .orderedSame
        }) {
            if !trimmedName.isEmpty {
                savedServers[existingIndex].name = resolvedName
            }
            let existing = savedServers.remove(at: existingIndex)
            savedServers.insert(existing, at: 0)
        } else {
            savedServers.insert(SavedServerProfile(name: resolvedName, baseURL: normalized), at: 0)
        }
        persistSavedServers()
        await configureConnection(baseURL: normalized, demoMode: false)
    }

    public func removeServer(id: UUID) {
        let removed = savedServers.first(where: { $0.id == id })
        savedServers.removeAll { $0.id == id }
        persistSavedServers()

        if let removed,
           !isDemoMode,
           removed.baseURL.caseInsensitiveCompare(serverBaseURL) == .orderedSame {
            serverBaseURL = ""
            UserDefaults.standard.set("", forKey: StorageKeys.serverURL)
            resetDomainState()
        }
        hapticImpactTrigger += 1
    }

    public func openSetupWizard() {
        if showServerSettings {
            pendingOpenSetupWizard = true
            showServerSettings = false
        } else {
            showServerSetupWizard = true
        }
    }

    public static func parseConnectDeepLink(_ raw: String) -> (url: String, name: String)? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else { return nil }
        return parseConnectDeepLink(url: url)
    }

    public static func parseConnectDeepLink(url: URL) -> (url: String, name: String)? {
        guard url.scheme?.lowercased() == "pvecenter" else { return nil }
        let host = url.host?.lowercased() ?? ""
        let path = url.path.lowercased()
        guard host == "connect" || path == "/connect" else { return nil }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let rawTarget = components.queryItems?.first(where: { $0.name == "url" })?.value else {
            return nil
        }

        let normalized = APIClient.normalizeBaseURL(rawTarget)
        guard !normalized.isEmpty,
              let parsedTarget = URL(string: normalized),
              let scheme = parsedTarget.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let targetHost = parsedTarget.host,
              !targetHost.isEmpty else {
            return nil
        }

        let rawName = components.queryItems?.first(where: { $0.name == "name" })?.value?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolvedName = rawName.isEmpty ? defaultServerName(for: normalized) : rawName
        return (normalized, resolvedName)
    }

    public func handleIncomingURL(_ url: URL) async {
        guard let parsed = Self.parseConnectDeepLink(url: url) else {
            showToast("Lien d'appairage pvecenter:// invalide.", isError: true)
            return
        }

        await addOrSelectServer(name: parsed.name, baseURL: parsed.url)

        do {
            let status = try await api.fetchSetupStatus(baseURL: parsed.url, demoMode: false)
            self.setupStatus = status
            if !status.isConfigured {
                openSetupWizard()
                showToast("Serveur « \(parsed.name) » connecté — terminez la configuration.", isError: false)
            } else {
                showToast("Serveur « \(parsed.name) » appairé et connecté.", isError: false)
            }
        } catch {
            showToast("Serveur « \(parsed.name) » ajouté (\(error.localizedDescription)).", isError: true)
        }
    }

    public func testConnection(candidateURL: String) async throws -> AuthUser {
        try await api.testConnection(baseURL: candidateURL)
    }

    public func fetchSetupStatus() async throws -> SetupStatusResponse {
        let status = try await api.fetchSetupStatus(baseURL: serverBaseURL, demoMode: isDemoMode)
        self.setupStatus = status
        return status
    }

    public func testSetupService(_ request: ServiceTestRequest) async throws -> ServiceTestResponse {
        try await api.testServiceConnection(baseURL: serverBaseURL, demoMode: isDemoMode, payload: request)
    }

    public func saveSetupConfig(_ request: SetupConfigUpdateRequest) async throws -> SetupConfigUpdateResponse {
        let response = try await api.saveSetupConfig(baseURL: serverBaseURL, demoMode: isDemoMode, payload: request)
        hapticSuccessTrigger += 1
        showToast(response.message, isError: false)
        await refreshAll(silent: false)
        return response
    }

    public func refreshAll(silent: Bool = false) async {
        guard isDemoMode || !serverBaseURL.isEmpty else {
            isInitialLoading = false
            return
        }

        if !silent && pveOverview == nil {
            isInitialLoading = true
        }
        isRefreshing = true
        defer {
            isInitialLoading = false
            isRefreshing = false
        }

        do {
            let me = try await api.fetchMe(baseURL: serverBaseURL, demoMode: isDemoMode)
            self.user = me
            self.connectionError = nil

            async let pveReq = api.fetchPveOverview(baseURL: serverBaseURL, demoMode: isDemoMode)
            async let svcReq = api.fetchServices(baseURL: serverBaseURL, demoMode: isDemoMode)
            async let widReq = api.fetchWidgets(baseURL: serverBaseURL, demoMode: isDemoMode)
            async let opsReq = api.fetchOpsOverview(baseURL: serverBaseURL, demoMode: isDemoMode)
            async let usrReq = api.fetchUsers(baseURL: serverBaseURL, demoMode: isDemoMode)
            async let setupReq = api.fetchSetupStatus(baseURL: serverBaseURL, demoMode: isDemoMode)

            let (pve, svc, wid, ops, usr, setup) = await (
                try? pveReq,
                try? svcReq,
                try? widReq,
                try? opsReq,
                try? usrReq,
                try? setupReq
            )

            if let pve { self.pveOverview = pve }
            if let svc { self.categories = svc.categories }
            if let wid { self.widgets = wid }
            if let ops { self.opsOverview = ops }
            if let usr { self.usersOverview = usr }
            if let setup { self.setupStatus = setup }

            self.lastUpdated = Date()
        } catch {
            self.connectionError = error.localizedDescription
            if !silent {
                showToast(error.localizedDescription, isError: true)
            }
        }
    }

    public func refreshOpsOnly() async {
        guard isDemoMode || !serverBaseURL.isEmpty else { return }
        if let ops = try? await api.fetchOpsOverview(baseURL: serverBaseURL, demoMode: isDemoMode) {
            self.opsOverview = ops
        }
    }

    public func refreshUsersOnly() async {
        guard isDemoMode || !serverBaseURL.isEmpty else { return }
        if let usr = try? await api.fetchUsers(baseURL: serverBaseURL, demoMode: isDemoMode) {
            self.usersOverview = usr
        }
    }

    // MARK: - Filtered Collections

    public var filteredResources: [PveResource] {
        let list = pveOverview?.resources ?? []
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return list }
        return list.filter {
            $0.name.lowercased().contains(q)
            || String($0.vmid).contains(q)
            || $0.tags.contains { $0.lowercased().contains(q) }
        }
    }

    public var filteredCategories: [ServiceCategory] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return categories }
        return categories.compactMap { category in
            if category.name.lowercased().contains(q) {
                return category
            }
            let matching = category.services.filter {
                $0.name.lowercased().contains(q) || $0.description.lowercased().contains(q)
            }
            return matching.isEmpty ? nil : ServiceCategory(name: category.name, services: matching)
        }
    }

    // MARK: - Smart Alerts

    public var smartAlerts: [SmartAlert] {
        var alerts: [SmartAlert] = []

        if let pve = pveOverview {
            if !pve.online {
                alerts.append(SmartAlert(
                    id: "pve-offline",
                    severity: .critical,
                    title: "Hôte Proxmox hors ligne",
                    subtitle: "L'API Proxmox VE ne répond pas sur \(pve.node.name).",
                    targetTab: .proxmox
                ))
            }

            if let drives = pve.externalStorage?.drives {
                let unhealthy = drives.filter { !$0.isHealthy }
                if !unhealthy.isEmpty {
                    alerts.append(SmartAlert(
                        id: "smart-warn",
                        severity: .critical,
                        title: "Alerte S.M.A.R.T. sur \(unhealthy.count) disque(s)",
                        subtitle: unhealthy.map(\.label).joined(separator: ", "),
                        targetTab: .storage
                    ))
                }
                let nearFullDrives = drives.filter { $0.usedPct >= 90 }
                if !nearFullDrives.isEmpty {
                    alerts.append(SmartAlert(
                        id: "drives-full",
                        severity: .warning,
                        title: "\(nearFullDrives.count) disque(s) ≥ 90 %",
                        subtitle: nearFullDrives.map { "\($0.label) (\(Int($0.usedPct)) %)" }.joined(separator: " • "),
                        targetTab: .storage
                    ))
                }
            }

            let highStorages = pve.node.storages.filter { $0.usedPct >= 80 }
            if !highStorages.isEmpty {
                alerts.append(SmartAlert(
                    id: "pve-storage-high",
                    severity: .warning,
                    title: "Datastore Proxmox ≥ 80 %",
                    subtitle: highStorages.map { "\($0.name) (\(Int($0.usedPct)) %)" }.joined(separator: ", "),
                    targetTab: .storage
                ))
            }
        }

        let offlineServices = categories.flatMap(\.services).filter { !$0.online }
        if !offlineServices.isEmpty {
            alerts.append(SmartAlert(
                id: "services-offline",
                severity: .critical,
                title: "\(offlineServices.count) service(s) hors ligne",
                subtitle: offlineServices.map(\.name).joined(separator: ", "),
                targetTab: .services
            ))
        }

        let pendingRequests = (opsOverview?.seerrRequests ?? []).filter(\.isPending)
        if !pendingRequests.isEmpty {
            alerts.append(SmartAlert(
                id: "seerr-pending",
                severity: .info,
                title: "\(pendingRequests.count) demande(s) Jellyseerr en attente",
                subtitle: pendingRequests.prefix(2).map(\.title).joined(separator: " • "),
                targetTab: .operations
            ))
        }

        if let unsynced = usersOverview?.counts.unsyncedCount, unsynced > 0 {
            alerts.append(SmartAlert(
                id: "users-unsynced",
                severity: .info,
                title: "\(unsynced) compte(s) Jellyfin non importé(s)",
                subtitle: "Synchronisation disponible vers Jellyseerr en un toucher.",
                targetTab: .users
            ))
        }

        return alerts
    }

    public var pendingRequestsCount: Int {
        (opsOverview?.seerrRequests ?? []).filter(\.isPending).count
    }

    // MARK: - Actions

    public func executePveAction(resource: PveResource, action: PveAction) async {
        do {
            try await api.performPveAction(
                baseURL: serverBaseURL,
                demoMode: isDemoMode,
                type: resource.type,
                vmid: resource.vmid,
                action: action
            )
            hapticSuccessTrigger += 1
            showToast("Commande « \(action.shortLabel) » envoyée à \(resource.name).", isError: false)
            await refreshAll(silent: true)
        } catch {
            showToast(error.localizedDescription, isError: true)
        }
    }

    public func decideSeerrRequest(id: Int, approve: Bool) async {
        do {
            try await api.decideSeerrRequest(
                baseURL: serverBaseURL,
                demoMode: isDemoMode,
                requestId: id,
                approve: approve
            )
            hapticSuccessTrigger += 1
            showToast(approve ? "Demande approuvée." : "Demande refusée.", isError: false)
            await refreshOpsOnly()
        } catch {
            showToast(error.localizedDescription, isError: true)
        }
    }

    public func toggleQbitSpeedMode() async {
        do {
            let enabled = try await api.toggleQbitSpeedMode(baseURL: serverBaseURL, demoMode: isDemoMode)
            hapticImpactTrigger += 1
            showToast(enabled ? "Mode Tortue activé." : "Vitesse normale rétablie.", isError: false)
            await refreshOpsOnly()
        } catch {
            showToast(error.localizedDescription, isError: true)
        }
    }

    public func controlTorrent(hash: String, pause: Bool) async {
        do {
            try await api.controlTorrent(
                baseURL: serverBaseURL,
                demoMode: isDemoMode,
                hash: hash,
                pause: pause
            )
            hapticImpactTrigger += 1
            await refreshOpsOnly()
        } catch {
            showToast(error.localizedDescription, isError: true)
        }
    }

    public func triggerMediaScan(target: String) async {
        do {
            try await api.triggerMediaScan(baseURL: serverBaseURL, demoMode: isDemoMode, target: target)
            hapticSuccessTrigger += 1
            showToast("Scan \(target.capitalized) déclenché.", isError: false)
        } catch {
            showToast(error.localizedDescription, isError: true)
        }
    }

    public func createUser(_ payload: CreateUserRequest) async -> Bool {
        do {
            try await api.createUser(baseURL: serverBaseURL, demoMode: isDemoMode, payload: payload)
            hapticSuccessTrigger += 1
            showToast("Compte « \(payload.username) » créé.", isError: false)
            await refreshUsersOnly()
            return true
        } catch {
            showToast(error.localizedDescription, isError: true)
            return false
        }
    }

    public func syncMissingUsers(userIDs: [String]? = nil) async {
        do {
            let imported = try await api.syncUsers(
                baseURL: serverBaseURL,
                demoMode: isDemoMode,
                payload: SyncUsersRequest(jellyfinUserIds: userIDs, autoApprove: true)
            )
            hapticSuccessTrigger += 1
            showToast("\(imported) compte(s) importé(s) vers Jellyseerr.", isError: false)
            await refreshUsersOnly()
        } catch {
            showToast(error.localizedDescription, isError: true)
        }
    }

    public func updateUser(id: String, payload: UpdateUserRequest) async -> Bool {
        do {
            try await api.updateUser(baseURL: serverBaseURL, demoMode: isDemoMode, jellyfinId: id, payload: payload)
            hapticSuccessTrigger += 1
            showToast("Permissions mises à jour.", isError: false)
            await refreshUsersOnly()
            return true
        } catch {
            showToast(error.localizedDescription, isError: true)
            return false
        }
    }

    public func resetPassword(id: String, newPassword: String) async -> Bool {
        do {
            try await api.resetPassword(
                baseURL: serverBaseURL,
                demoMode: isDemoMode,
                jellyfinId: id,
                newPassword: newPassword
            )
            hapticSuccessTrigger += 1
            showToast("Mot de passe réinitialisé.", isError: false)
            return true
        } catch {
            showToast(error.localizedDescription, isError: true)
            return false
        }
    }

    public func deleteUser(id: String, name: String) async -> Bool {
        do {
            try await api.deleteUser(baseURL: serverBaseURL, demoMode: isDemoMode, jellyfinId: id)
            hapticSuccessTrigger += 1
            showToast("Compte « \(name) » supprimé.", isError: false)
            await refreshUsersOnly()
            return true
        } catch {
            showToast(error.localizedDescription, isError: true)
            return false
        }
    }

    // MARK: - Toast Helper

    public func showToast(_ text: String, isError: Bool) {
        let message = ToastMessage(isError: isError, text: text)
        toast = message
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3.5))
            if self?.toast?.id == message.id {
                self?.toast = nil
            }
        }
    }
}
