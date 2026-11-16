import Foundation

// MARK: - Auth & Navigation

public struct AuthUser: Codable, Sendable, Equatable {
    public let login: String
    public let name: String
    public let profilePic: String?
    public let authMode: String?

    public init(login: String, name: String, profilePic: String? = nil, authMode: String? = nil) {
        self.login = login
        self.name = name
        self.profilePic = profilePic
        self.authMode = authMode
    }
}

public enum AppTab: String, CaseIterable, Identifiable, Sendable {
    case overview
    case proxmox
    case storage
    case services
    case operations
    case users

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .overview: "Poste"
        case .proxmox: "Machines"
        case .storage: "Stockage"
        case .services: "Services"
        case .operations: "Activité"
        case .users: "Comptes"
        }
    }

    public var systemImage: String {
        switch self {
        case .overview: "square.grid.2x2.fill"
        case .proxmox: "server.rack"
        case .storage: "internaldrive.fill"
        case .services: "app.connected.to.app.below.fill"
        case .operations: "bolt.circle.fill"
        case .users: "person.2.fill"
        }
    }

    /// 5 onglets maximum en largeur compacte iPhone pour éviter le repli "Plus" (`tab-bars.md`).
    public static var compactTabs: [AppTab] {
        [.overview, .proxmox, .storage, .operations, .users]
    }
}

// MARK: - Proxmox & Storage

public struct StorageInfo: Codable, Sendable, Equatable, Identifiable {
    public var id: String { name }
    public let name: String
    public let type: String
    public let active: Bool
    public let usedBytes: Int64
    public let totalBytes: Int64
    public let usedPct: Double
}

public struct NodeSummary: Codable, Sendable, Equatable {
    public let name: String
    public let cpuPct: Double
    public let cpuModel: String
    public let cpuThreads: Int
    public let loadavg: [String]
    public let memUsedBytes: Int64
    public let memTotalBytes: Int64
    public let memPct: Double
    public let swapUsedBytes: Int64
    public let swapTotalBytes: Int64
    public let rootfsUsedBytes: Int64
    public let rootfsTotalBytes: Int64
    public let uptimeSeconds: Int
    public let uptimeHuman: String
    public let pveVersion: String
    public let storages: [StorageInfo]
}

public struct PveCounts: Codable, Sendable, Equatable {
    public let total: Int
    public let running: Int
    public let stopped: Int
    public let lxc: Int
    public let qemu: Int
}

public enum PveResourceType: String, Codable, Sendable, Equatable {
    case lxc
    case qemu

    public var badgeLabel: String {
        switch self {
        case .lxc: "LXC"
        case .qemu: "VM"
        }
    }

    public var symbolName: String {
        switch self {
        case .lxc: "shippingbox.fill"
        case .qemu: "desktopcomputer"
        }
    }
}

public struct PveResource: Codable, Sendable, Equatable, Identifiable {
    public var id: String { "\(type.rawValue)-\(vmid)" }
    public let vmid: Int
    public var name: String
    public let type: PveResourceType
    public var status: String
    public var cpuPct: Double
    public var cpus: Int
    public var memUsedBytes: Int64
    public var memTotalBytes: Int64
    public var memPct: Double
    public var diskUsedBytes: Int64
    public var diskTotalBytes: Int64
    public var uptimeSeconds: Int
    public var uptimeHuman: String
    public var tags: [String]
    public let isSelf: Bool

    public var isRunning: Bool {
        status.lowercased() == "running"
    }
}

public enum PveAction: String, CaseIterable, Codable, Sendable, Identifiable {
    case start
    case shutdown
    case reboot
    case stop

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .start: "Démarrer"
        case .shutdown: "Éteindre (ACPI)"
        case .reboot: "Redémarrer"
        case .stop: "Forcer l'arrêt"
        }
    }

    public var shortLabel: String {
        switch self {
        case .start: "Démarrer"
        case .shutdown: "Éteindre"
        case .reboot: "Reboot"
        case .stop: "Stop"
        }
    }

    public var systemImage: String {
        switch self {
        case .start: "play.fill"
        case .shutdown: "power"
        case .reboot: "arrow.clockwise"
        case .stop: "stop.fill"
        }
    }

    public var isDestructive: Bool {
        self == .stop || self == .shutdown
    }

    public var warningMessage: String {
        switch self {
        case .start:
            return "Cette ressource va être démarrée sur le nœud Proxmox."
        case .shutdown:
            return "Un arrêt propre (ACPI) va être envoyé à cette machine."
        case .reboot:
            return "La machine va redémarrer immédiatement et interrompre brièvement ses services."
        case .stop:
            return "Attention : l'arrêt forcé coupe l'alimentation instantanément (risque de perte de données non écrites)."
        }
    }
}

public struct MergerfsPoolInfo: Codable, Sendable, Equatable {
    public let name: String
    public let mount: String
    public let fstype: String
    public let policy: String
    public let drivesCount: Int
    public let available: Bool
    public let totalBytes: Int64
    public let usedBytes: Int64
    public let availBytes: Int64
    public let usedPct: Double
}

public struct PhysicalDriveInfo: Codable, Sendable, Equatable, Identifiable {
    public var id: String { "\(devpath)-\(mount)" }
    public let mount: String
    public let label: String
    public let wwn: String
    public let devpath: String
    public let model: String
    public let vendor: String
    public let serial: String
    public let type: String
    public let rpm: String
    public let health: String
    public let sizeBytes: Int64
    public let totalBytes: Int64
    public let usedBytes: Int64
    public let availBytes: Int64
    public let usedPct: Double

    public var isHealthy: Bool {
        health.uppercased() == "PASSED" || health.uppercased() == "OK"
    }
}

public struct SystemSsdInfo: Codable, Sendable, Equatable {
    public let devpath: String
    public let model: String
    public let serial: String
    public let health: String
    public let sizeBytes: Int64
}

public struct ExternalStorageOverview: Codable, Sendable, Equatable {
    public let pool: MergerfsPoolInfo
    public let drives: [PhysicalDriveInfo]
    public let systemSsd: SystemSsdInfo?
}

public struct PveOverview: Codable, Sendable, Equatable {
    public let online: Bool
    public let node: NodeSummary
    public let counts: PveCounts
    public let resources: [PveResource]
    public let externalStorage: ExternalStorageOverview?
}

// MARK: - Services & Widgets

public struct ServiceItem: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let description: String
    public let url: String
    public let pingUrl: String?
    public let icon: String
    public let widget: String?
    public let online: Bool
    public let latencyMs: Double?
    public let statusCode: Int?
}

public struct ServiceCategory: Codable, Sendable, Equatable, Identifiable {
    public var id: String { name }
    public let name: String
    public let services: [ServiceItem]
}

public struct ServicesResponse: Codable, Sendable, Equatable {
    public let categories: [ServiceCategory]
}

public struct JellyfinStream: Codable, Sendable, Equatable, Identifiable {
    public var id: String { "\(user)-\(title)-\(device)" }
    public let user: String
    public let title: String
    public let device: String
    public let playMethod: String
    public let isPaused: Bool
}

public struct JellyfinWidget: Codable, Sendable, Equatable {
    public let status: String
    public let activeStreamsCount: Int?
    public let activeStreams: [JellyfinStream]?
    public let moviesCount: Int?
    public let seriesCount: Int?
    public let episodesCount: Int?
}

public struct PlexWidget: Codable, Sendable, Equatable {
    public let status: String
    public let activeStreamsCount: Int?
    public let librariesCount: Int?
    public let libraries: [String]?
    public let version: String?
}

public struct UpcomingItem: Codable, Sendable, Equatable, Identifiable {
    public var id: String { "\(title)-\(date)" }
    public let title: String
    public let date: String
}

public struct RadarrWidget: Codable, Sendable, Equatable {
    public let status: String
    public let moviesTotal: Int?
    public let moviesDownloaded: Int?
    public let moviesMissing: Int?
    public let queueCount: Int?
    public let upcoming: [UpcomingItem]?
}

public struct SonarrWidget: Codable, Sendable, Equatable {
    public let status: String
    public let seriesTotal: Int?
    public let episodesDownloaded: Int?
    public let queueCount: Int?
    public let upcoming: [UpcomingItem]?
}

public struct ProwlarrWidget: Codable, Sendable, Equatable {
    public let status: String
    public let indexersEnabled: Int?
    public let indexersTotal: Int?
    public let queries: Int?
    public let grabs: Int?
}

public struct QbittorrentWidget: Codable, Sendable, Equatable {
    public let status: String
    public let dlSpeedBytes: Int64?
    public let upSpeedBytes: Int64?
    public let dlTotalBytes: Int64?
    public let upTotalBytes: Int64?
    public let downloadingCount: Int?
    public let seedingCount: Int?
    public let torrentsTotal: Int?
}

public struct WidgetsMap: Codable, Sendable, Equatable {
    public let jellyfin: JellyfinWidget?
    public let plex: PlexWidget?
    public let radarr: RadarrWidget?
    public let sonarr: SonarrWidget?
    public let prowlarr: ProwlarrWidget?
    public let qbittorrent: QbittorrentWidget?
}

// MARK: - Users (Jellyfin <-> Jellyseerr)

public struct JellyfinLibrary: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
}

public struct UnifiedUser: Codable, Sendable, Equatable, Identifiable {
    public var id: String { jellyfinId }
    public let jellyfinId: String
    public var name: String
    public var isAdmin: Bool
    public let isProtected: Bool?
    public var isDisabled: Bool
    public var enableAllFolders: Bool
    public var enabledFolders: [String]
    public var enableDownloading: Bool
    public var maxActiveSessions: Int
    public var lastActivity: String?
    public var inJellyseerr: Bool
    public var jellyseerrId: Int?
    public var requestCount: Int
    public var autoApprove: Bool
}

public struct UsersCounts: Codable, Sendable, Equatable {
    public let totalJellyfin: Int
    public let syncedJellyseerr: Int
    public let unsyncedCount: Int
    public let disabledCount: Int
}

public struct UsersOverview: Codable, Sendable, Equatable {
    public let counts: UsersCounts
    public let libraries: [JellyfinLibrary]
    public let users: [UnifiedUser]
}

public struct CreateUserRequest: Codable, Sendable {
    public let username: String
    public let password: String
    public let syncJellyseerr: Bool
    public let autoApprove: Bool
    public let enableAllFolders: Bool
    public let enabledFolders: [String]
    public let enableDownloading: Bool
    public let maxActiveSessions: Int
}

public struct UpdateUserRequest: Codable, Sendable {
    public var isDisabled: Bool?
    public var isAdmin: Bool?
    public var enableAllFolders: Bool?
    public var enabledFolders: [String]?
    public var enableDownloading: Bool?
    public var maxActiveSessions: Int?
    public var autoApprove: Bool?
}

public struct ResetPasswordRequest: Codable, Sendable {
    public let newPassword: String
}

public struct SyncUsersRequest: Codable, Sendable {
    public let jellyfinUserIds: [String]?
    public let autoApprove: Bool
}

public struct SyncUsersResponse: Codable, Sendable {
    public let ok: Bool
    public let importedCount: Int
}

public struct ActionOKResponse: Codable, Sendable {
    public let ok: Bool
    public let message: String?
    public let altSpeedEnabled: Bool?
}

// MARK: - Operations & Alerts

public struct PveTaskItem: Codable, Sendable, Equatable, Identifiable {
    public var id: String { "\(upid)-\(starttime)" }
    public let upid: String
    public let type: String
    public let vmid: String
    public let user: String
    public let status: String
    public let starttime: Int
    public let endtime: Int
    public let durationSec: Int?

    public var isSuccess: Bool {
        status.uppercased() == "OK"
    }
}

public struct SeerrRequestItem: Codable, Sendable, Equatable, Identifiable {
    public let id: Int
    public var status: Int
    public let mediaType: String
    public let title: String
    public let requestedBy: String
    public let createdAt: String
    public let mediaStatus: Int

    public var isPending: Bool { status == 1 }

    public var statusLabel: String {
        switch status {
        case 1: "En attente"
        case 2: "Approuvée"
        case 3: "Refusée"
        default: "Traitée"
        }
    }
}

public struct QbitTorrentItem: Codable, Sendable, Equatable, Identifiable {
    public var id: String { hash }
    public let hash: String
    public let name: String
    public var state: String
    public let progressPct: Double
    public let dlspeed: Int64
    public let upspeed: Int64
    public let size: Int64
    public let eta: Int

    public var isPaused: Bool {
        state.lowercased().contains("paused") || state.lowercased().contains("stopped")
    }
}

public struct QbitControlOverview: Codable, Sendable, Equatable {
    public let available: Bool
    public var altSpeedEnabled: Bool
    public var torrents: [QbitTorrentItem]
}

public struct OpsOverview: Codable, Sendable, Equatable {
    public let pveTasks: [PveTaskItem]
    public let seerrRequests: [SeerrRequestItem]
    public let qbitControl: QbitControlOverview
}

public struct SmartAlert: Identifiable, Equatable, Sendable {
    public enum Severity: String, Sendable {
        case critical
        case warning
        case info
    }

    public let id: String
    public let severity: Severity
    public let title: String
    public let subtitle: String
    public let targetTab: AppTab
}

public struct ToastMessage: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let isError: Bool
    public let text: String
}

// MARK: - Multi-Server & Setup

public struct SavedServerProfile: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public var name: String
    public var baseURL: String
    public var addedAt: Date

    public init(id: UUID = UUID(), name: String, baseURL: String, addedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.addedAt = addedAt
    }
}

public struct SetupEnvConfig: Codable, Sendable, Equatable {
    public var devAuthBypass: Bool
    public var allowedTailscaleUsers: String
    public var protectedOwnerUsername: String
    public var pveHost: String
    public var pveNode: String
    public var pveTokenId: String
    public var pveTokenSecretSet: Bool
    public var pveVerifySsl: Bool
    public var panelSelfVmid: Int
    public var jellyfinUrl: String
    public var jellyfinApiKeySet: Bool
    public var jellyseerrUrl: String
    public var jellyseerrApiKeySet: Bool
    public var plexUrl: String
    public var plexTokenSet: Bool
    public var radarrUrl: String
    public var radarrApiKeySet: Bool
    public var sonarrUrl: String
    public var sonarrApiKeySet: Bool
    public var prowlarrUrl: String
    public var prowlarrApiKeySet: Bool
    public var qbitUrl: String
    public var qbitUsername: String
    public var qbitPasswordSet: Bool

    public init(
        devAuthBypass: Bool = false,
        allowedTailscaleUsers: String = "",
        protectedOwnerUsername: String = "admin",
        pveHost: String = "",
        pveNode: String = "pve",
        pveTokenId: String = "",
        pveTokenSecretSet: Bool = false,
        pveVerifySsl: Bool = false,
        panelSelfVmid: Int = 116,
        jellyfinUrl: String = "",
        jellyfinApiKeySet: Bool = false,
        jellyseerrUrl: String = "",
        jellyseerrApiKeySet: Bool = false,
        plexUrl: String = "",
        plexTokenSet: Bool = false,
        radarrUrl: String = "",
        radarrApiKeySet: Bool = false,
        sonarrUrl: String = "",
        sonarrApiKeySet: Bool = false,
        prowlarrUrl: String = "",
        prowlarrApiKeySet: Bool = false,
        qbitUrl: String = "",
        qbitUsername: String = "",
        qbitPasswordSet: Bool = false
    ) {
        self.devAuthBypass = devAuthBypass
        self.allowedTailscaleUsers = allowedTailscaleUsers
        self.protectedOwnerUsername = protectedOwnerUsername
        self.pveHost = pveHost
        self.pveNode = pveNode
        self.pveTokenId = pveTokenId
        self.pveTokenSecretSet = pveTokenSecretSet
        self.pveVerifySsl = pveVerifySsl
        self.panelSelfVmid = panelSelfVmid
        self.jellyfinUrl = jellyfinUrl
        self.jellyfinApiKeySet = jellyfinApiKeySet
        self.jellyseerrUrl = jellyseerrUrl
        self.jellyseerrApiKeySet = jellyseerrApiKeySet
        self.plexUrl = plexUrl
        self.plexTokenSet = plexTokenSet
        self.radarrUrl = radarrUrl
        self.radarrApiKeySet = radarrApiKeySet
        self.sonarrUrl = sonarrUrl
        self.sonarrApiKeySet = sonarrApiKeySet
        self.prowlarrUrl = prowlarrUrl
        self.prowlarrApiKeySet = prowlarrApiKeySet
        self.qbitUrl = qbitUrl
        self.qbitUsername = qbitUsername
        self.qbitPasswordSet = qbitPasswordSet
    }
}

public struct SetupServiceConfig: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var description: String?
    public var url: String
    public var pingUrl: String?
    public var icon: String?
    public var widget: String?

    public init(
        id: String,
        name: String,
        description: String? = nil,
        url: String,
        pingUrl: String? = nil,
        icon: String? = nil,
        widget: String? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.url = url
        self.pingUrl = pingUrl
        self.icon = icon
        self.widget = widget
    }
}

public struct SetupCategoryConfig: Codable, Sendable, Equatable, Identifiable {
    public var id: String { name }
    public var name: String
    public var services: [SetupServiceConfig]

    public init(name: String, services: [SetupServiceConfig]) {
        self.name = name
        self.services = services
    }
}

public struct StorageMountConfig: Codable, Sendable, Equatable, Identifiable {
    public var id: String { subpath }
    public var mount: String?
    public var subpath: String
    public var wwn: String?
    public var label: String?

    public init(mount: String? = nil, subpath: String, wwn: String? = nil, label: String? = nil) {
        self.mount = mount
        self.subpath = subpath
        self.wwn = wwn
        self.label = label
    }
}

public struct SetupStatusResponse: Codable, Sendable, Equatable {
    public let isConfigured: Bool
    public let tailscaleUrl: String
    public let pairingDeepLink: String
    public let env: SetupEnvConfig
    public let categories: [SetupCategoryConfig]?
    public let storageMounts: [StorageMountConfig]?

    public init(
        isConfigured: Bool,
        tailscaleUrl: String,
        pairingDeepLink: String,
        env: SetupEnvConfig,
        categories: [SetupCategoryConfig]? = nil,
        storageMounts: [StorageMountConfig]? = nil
    ) {
        self.isConfigured = isConfigured
        self.tailscaleUrl = tailscaleUrl
        self.pairingDeepLink = pairingDeepLink
        self.env = env
        self.categories = categories
        self.storageMounts = storageMounts
    }
}

public struct ServiceTestRequest: Codable, Sendable {
    public let service: String
    public let url: String
    public let node: String?
    public let tokenId: String?
    public let secret: String?
    public let username: String?
    public let verifySsl: Bool?

    public init(
        service: String,
        url: String,
        node: String? = nil,
        tokenId: String? = nil,
        secret: String? = nil,
        username: String? = nil,
        verifySsl: Bool? = nil
    ) {
        self.service = service
        self.url = url
        self.node = node
        self.tokenId = tokenId
        self.secret = secret
        self.username = username
        self.verifySsl = verifySsl
    }
}

public struct ServiceTestResponse: Codable, Sendable, Equatable {
    public let ok: Bool
    public let service: String
    public let message: String
    public let latencyMs: Double?

    public init(ok: Bool, service: String, message: String, latencyMs: Double? = nil) {
        self.ok = ok
        self.service = service
        self.message = message
        self.latencyMs = latencyMs
    }
}

public struct SetupEnvUpdate: Codable, Sendable {
    public var devAuthBypass: Bool?
    public var allowedTailscaleUsers: String?
    public var protectedOwnerUsername: String?
    public var pveHost: String?
    public var pveNode: String?
    public var pveTokenId: String?
    public var pveTokenSecret: String?
    public var pveVerifySsl: Bool?
    public var panelSelfVmid: Int?
    public var jellyfinUrl: String?
    public var jellyfinApiKey: String?
    public var jellyseerrUrl: String?
    public var jellyseerrApiKey: String?
    public var plexUrl: String?
    public var plexToken: String?
    public var radarrUrl: String?
    public var radarrApiKey: String?
    public var sonarrUrl: String?
    public var sonarrApiKey: String?
    public var prowlarrUrl: String?
    public var prowlarrApiKey: String?
    public var qbitUrl: String?
    public var qbitUsername: String?
    public var qbitPassword: String?

    public init(
        devAuthBypass: Bool? = nil,
        allowedTailscaleUsers: String? = nil,
        protectedOwnerUsername: String? = nil,
        pveHost: String? = nil,
        pveNode: String? = nil,
        pveTokenId: String? = nil,
        pveTokenSecret: String? = nil,
        pveVerifySsl: Bool? = nil,
        panelSelfVmid: Int? = nil,
        jellyfinUrl: String? = nil,
        jellyfinApiKey: String? = nil,
        jellyseerrUrl: String? = nil,
        jellyseerrApiKey: String? = nil,
        plexUrl: String? = nil,
        plexToken: String? = nil,
        radarrUrl: String? = nil,
        radarrApiKey: String? = nil,
        sonarrUrl: String? = nil,
        sonarrApiKey: String? = nil,
        prowlarrUrl: String? = nil,
        prowlarrApiKey: String? = nil,
        qbitUrl: String? = nil,
        qbitUsername: String? = nil,
        qbitPassword: String? = nil
    ) {
        self.devAuthBypass = devAuthBypass
        self.allowedTailscaleUsers = allowedTailscaleUsers
        self.protectedOwnerUsername = protectedOwnerUsername
        self.pveHost = pveHost
        self.pveNode = pveNode
        self.pveTokenId = pveTokenId
        self.pveTokenSecret = pveTokenSecret
        self.pveVerifySsl = pveVerifySsl
        self.panelSelfVmid = panelSelfVmid
        self.jellyfinUrl = jellyfinUrl
        self.jellyfinApiKey = jellyfinApiKey
        self.jellyseerrUrl = jellyseerrUrl
        self.jellyseerrApiKey = jellyseerrApiKey
        self.plexUrl = plexUrl
        self.plexToken = plexToken
        self.radarrUrl = radarrUrl
        self.radarrApiKey = radarrApiKey
        self.sonarrUrl = sonarrUrl
        self.sonarrApiKey = sonarrApiKey
        self.prowlarrUrl = prowlarrUrl
        self.prowlarrApiKey = prowlarrApiKey
        self.qbitUrl = qbitUrl
        self.qbitUsername = qbitUsername
        self.qbitPassword = qbitPassword
    }
}

public struct SetupConfigUpdateRequest: Codable, Sendable {
    public var env: SetupEnvUpdate?
    public var categories: [SetupCategoryConfig]?
    public var storageMounts: [StorageMountConfig]?

    public init(
        env: SetupEnvUpdate? = nil,
        categories: [SetupCategoryConfig]? = nil,
        storageMounts: [StorageMountConfig]? = nil
    ) {
        self.env = env
        self.categories = categories
        self.storageMounts = storageMounts
    }
}

public struct SetupConfigUpdateResponse: Codable, Sendable, Equatable {
    public let ok: Bool
    public let isConfigured: Bool
    public let message: String

    public init(ok: Bool, isConfigured: Bool, message: String) {
        self.ok = ok
        self.isConfigured = isConfigured
        self.message = message
    }
}
