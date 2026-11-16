import Foundation

public enum APIError: LocalizedError, Sendable {
    case invalidBaseURL
    case forbidden(String)
    case serverError(statusCode: Int, detail: String)
    case decodingError(String)
    case transportError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "L'URL du serveur est invalide. Vérifiez le format https://..."
        case .forbidden(let detail):
            return detail
        case .serverError(_, let detail):
            return detail
        case .decodingError(let msg):
            return "Réponse serveur inattendue (\(msg))."
        case .transportError(let msg):
            return msg
        }
    }
}

private struct ErrorDetailBody: Codable {
    let detail: String?
}

public actor APIClient {
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let demoStore: DemoDataStore

    public init(demoStore: DemoDataStore = .shared) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 15
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)

        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = dec

        let enc = JSONEncoder()
        enc.keyEncodingStrategy = .convertToSnakeCase
        self.encoder = enc

        self.demoStore = demoStore
    }

    public static func normalizeBaseURL(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let withScheme = trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://")
            ? trimmed
            : "https://\(trimmed)"
        return withScheme.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    // MARK: - Reads

    public func testConnection(baseURL: String) async throws -> AuthUser {
        let normalized = Self.normalizeBaseURL(baseURL)
        return try await send(path: "/api/me", baseURL: normalized)
    }

    public func fetchMe(baseURL: String, demoMode: Bool) async throws -> AuthUser {
        if demoMode {
            return await demoStore.currentUser()
        }
        return try await send(path: "/api/me", baseURL: baseURL)
    }

    public func fetchPveOverview(baseURL: String, demoMode: Bool) async throws -> PveOverview {
        if demoMode {
            return await demoStore.pveOverview()
        }
        return try await send(path: "/api/pve/overview", baseURL: baseURL)
    }

    public func fetchServices(baseURL: String, demoMode: Bool) async throws -> ServicesResponse {
        if demoMode {
            let categories = await demoStore.servicesCategories()
            return ServicesResponse(categories: categories)
        }
        return try await send(path: "/api/services", baseURL: baseURL)
    }

    public func fetchWidgets(baseURL: String, demoMode: Bool) async throws -> WidgetsMap {
        if demoMode {
            return await demoStore.widgets()
        }
        return try await send(path: "/api/widgets/all", baseURL: baseURL)
    }

    public func fetchOpsOverview(baseURL: String, demoMode: Bool) async throws -> OpsOverview {
        if demoMode {
            return await demoStore.opsOverview()
        }
        return try await send(path: "/api/ops/overview", baseURL: baseURL)
    }

    public func fetchUsers(baseURL: String, demoMode: Bool) async throws -> UsersOverview {
        if demoMode {
            return await demoStore.usersOverview()
        }
        return try await send(path: "/api/users", baseURL: baseURL)
    }

    public func fetchSetupStatus(baseURL: String, demoMode: Bool) async throws -> SetupStatusResponse {
        if demoMode {
            return await demoStore.setupStatus()
        }
        return try await send(path: "/api/setup/status", baseURL: baseURL)
    }

    // MARK: - Mutations

    public func performPveAction(
        baseURL: String,
        demoMode: Bool,
        type: PveResourceType,
        vmid: Int,
        action: PveAction
    ) async throws {
        if demoMode {
            try await demoStore.performPveAction(type: type, vmid: vmid, action: action)
            return
        }
        let _: ActionOKResponse = try await send(
            path: "/api/pve/\(type.rawValue)/\(vmid)/\(action.rawValue)",
            method: "POST",
            baseURL: baseURL
        )
    }

    public func decideSeerrRequest(
        baseURL: String,
        demoMode: Bool,
        requestId: Int,
        approve: Bool
    ) async throws {
        if demoMode {
            try await demoStore.decideSeerrRequest(id: requestId, approve: approve)
            return
        }
        let decision = approve ? "approve" : "decline"
        let _: ActionOKResponse = try await send(
            path: "/api/ops/seerr/\(requestId)/\(decision)",
            method: "POST",
            baseURL: baseURL
        )
    }

    public func toggleQbitSpeedMode(baseURL: String, demoMode: Bool) async throws -> Bool {
        if demoMode {
            return await demoStore.toggleQbitSpeedMode()
        }
        let res: ActionOKResponse = try await send(
            path: "/api/ops/qbit/toggle-speed-mode",
            method: "POST",
            baseURL: baseURL
        )
        return res.altSpeedEnabled ?? false
    }

    public func controlTorrent(
        baseURL: String,
        demoMode: Bool,
        hash: String,
        pause: Bool
    ) async throws {
        if demoMode {
            try await demoStore.controlTorrent(hash: hash, pause: pause)
            return
        }
        let action = pause ? "pause" : "resume"
        let _: ActionOKResponse = try await send(
            path: "/api/ops/qbit/torrent/\(hash)/\(action)",
            method: "POST",
            baseURL: baseURL
        )
    }

    public func triggerMediaScan(
        baseURL: String,
        demoMode: Bool,
        target: String
    ) async throws {
        if demoMode { return }
        let _: ActionOKResponse = try await send(
            path: "/api/ops/media/scan/\(target)",
            method: "POST",
            baseURL: baseURL
        )
    }

    public func createUser(
        baseURL: String,
        demoMode: Bool,
        payload: CreateUserRequest
    ) async throws {
        if demoMode {
            _ = try await demoStore.createUser(payload)
            return
        }
        let _: ActionOKResponse = try await send(
            path: "/api/users",
            method: "POST",
            body: payload,
            baseURL: baseURL
        )
    }

    public func syncUsers(
        baseURL: String,
        demoMode: Bool,
        payload: SyncUsersRequest
    ) async throws -> Int {
        if demoMode {
            return await demoStore.syncUsers(payload)
        }
        let res: SyncUsersResponse = try await send(
            path: "/api/users/sync",
            method: "POST",
            body: payload,
            baseURL: baseURL
        )
        return res.importedCount
    }

    public func updateUser(
        baseURL: String,
        demoMode: Bool,
        jellyfinId: String,
        payload: UpdateUserRequest
    ) async throws {
        if demoMode {
            try await demoStore.updateUser(id: jellyfinId, req: payload)
            return
        }
        let _: ActionOKResponse = try await send(
            path: "/api/users/\(jellyfinId)",
            method: "PATCH",
            body: payload,
            baseURL: baseURL
        )
    }

    public func resetPassword(
        baseURL: String,
        demoMode: Bool,
        jellyfinId: String,
        newPassword: String
    ) async throws {
        if demoMode { return }
        let _: ActionOKResponse = try await send(
            path: "/api/users/\(jellyfinId)/password",
            method: "POST",
            body: ResetPasswordRequest(newPassword: newPassword),
            baseURL: baseURL
        )
    }

    public func deleteUser(
        baseURL: String,
        demoMode: Bool,
        jellyfinId: String
    ) async throws {
        if demoMode {
            try await demoStore.deleteUser(id: jellyfinId)
            return
        }
        let _: ActionOKResponse = try await send(
            path: "/api/users/\(jellyfinId)",
            method: "DELETE",
            baseURL: baseURL
        )
    }

    // MARK: - Setup Wizard

    public func testServiceConnection(
        baseURL: String,
        demoMode: Bool,
        payload: ServiceTestRequest
    ) async throws -> ServiceTestResponse {
        if demoMode {
            return await demoStore.testServiceConnection(payload)
        }
        return try await send(
            path: "/api/setup/test-service",
            method: "POST",
            body: payload,
            baseURL: baseURL
        )
    }

    public func saveSetupConfig(
        baseURL: String,
        demoMode: Bool,
        payload: SetupConfigUpdateRequest
    ) async throws -> SetupConfigUpdateResponse {
        if demoMode {
            return await demoStore.saveSetupConfig(payload)
        }
        return try await send(
            path: "/api/setup/config",
            method: "PUT",
            body: payload,
            baseURL: baseURL
        )
    }

    // MARK: - Core HTTP Transport

    private func send<ResponseType: Decodable>(
        path: String,
        method: String = "GET",
        baseURL: String
    ) async throws -> ResponseType {
        try await sendRequest(path: path, method: method, bodyData: nil, baseURL: baseURL)
    }

    private func send<BodyType: Encodable, ResponseType: Decodable>(
        path: String,
        method: String = "POST",
        body: BodyType,
        baseURL: String
    ) async throws -> ResponseType {
        let data = try encoder.encode(body)
        return try await sendRequest(path: path, method: method, bodyData: data, baseURL: baseURL)
    }

    private func sendRequest<ResponseType: Decodable>(
        path: String,
        method: String,
        bodyData: Data?,
        baseURL: String
    ) async throws -> ResponseType {
        let normalized = Self.normalizeBaseURL(baseURL)
        guard !normalized.isEmpty, let url = URL(string: "\(normalized)\(path)") else {
            throw APIError.invalidBaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let bodyData {
            request.httpBody = bodyData
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.transportError("Connexion impossible au serveur (\(error.localizedDescription)).")
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.transportError("Réponse réseau invalide.")
        }

        if http.statusCode == 403 {
            let errBody = try? decoder.decode(ErrorDetailBody.self, from: data)
            throw APIError.forbidden(errBody?.detail ?? "Accès refusé par Tailscale SSO (403).")
        }

        if http.statusCode >= 400 {
            let errBody = try? decoder.decode(ErrorDetailBody.self, from: data)
            let detail = errBody?.detail ?? "Erreur serveur HTTP \(http.statusCode)."
            throw APIError.serverError(statusCode: http.statusCode, detail: detail)
        }

        do {
            return try decoder.decode(ResponseType.self, from: data)
        } catch {
            throw APIError.decodingError(error.localizedDescription)
        }
    }
}
