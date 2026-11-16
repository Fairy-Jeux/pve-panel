import SwiftUI

private enum UserFilter: String, CaseIterable, Identifiable {
    case all = "Tous"
    case synced = "Jellyseerr"
    case unsynced = "À importer"
    case disabled = "Suspendus"

    var id: String { rawValue }
}

public struct UsersTabView: View {
    public var viewModel: AppViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var filter: UserFilter = .all
    @State private var showCreateSheet = false
    @State private var selectedUser: UnifiedUser?
    @State private var isSyncing = false

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    private var displayedUsers: [UnifiedUser] {
        let all = viewModel.usersOverview?.users ?? []
        let q = viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return all.filter { user in
            let matchesSearch = q.isEmpty || user.name.lowercased().contains(q)
            let matchesFilter: Bool = switch filter {
            case .all: true
            case .synced: user.inJellyseerr
            case .unsynced: !user.inJellyseerr
            case .disabled: user.isDisabled
            }
            return matchesSearch && matchesFilter
        }
    }

    private var adaptiveColumns: [GridItem] {
        #if os(macOS)
        return [GridItem(.adaptive(minimum: 310), spacing: 12)]
        #else
        return [GridItem(.flexible())]
        #endif
    }

    public var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                headerActionsCard

                HStack(spacing: 12) {
                    Text("Comptes (\(displayedUsers.count))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                    Spacer()
                    Picker("Filtre des comptes", selection: $filter) {
                        ForEach(UserFilter.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 360)
                }

                LazyVGrid(columns: adaptiveColumns, spacing: 12) {
                    ForEach(displayedUsers) { user in
                        userRow(user)
                    }
                }

                if displayedUsers.isEmpty {
                    GlassCard {
                        ContentUnavailableView(
                            "Aucun utilisateur",
                            systemImage: "person.slash",
                            description: Text("Aucun compte ne correspond à votre recherche ou filtre.")
                        )
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .contentMargins(.top, 8, for: .scrollContent)
        .refreshable {
            await viewModel.refreshAll(silent: false)
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateUserSheet(viewModel: viewModel)
        }
        .sheet(item: $selectedUser) { user in
            ManageUserSheet(viewModel: viewModel, user: user)
        }
    }

    private var headerActionsCard: some View {
        let counts = viewModel.usersOverview?.counts

        return GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Jellyfin ↔ Jellyseerr")
                            .font(.headline)
                            .foregroundStyle(DesignTokens.primaryText(colorScheme))
                        Text("\(counts?.totalJellyfin ?? 0) comptes • \(counts?.syncedJellyseerr ?? 0) synchronisés")
                            .font(.caption)
                            .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                    }
                    Spacer()
                    Button {
                        showCreateSheet = true
                    } label: {
                        Label("Créer", systemImage: "person.badge.plus")
                            .frame(minHeight: 28)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(DesignTokens.signalTeal(colorScheme))
                    .controlSize(.small)
                }

                if let unsynced = counts?.unsyncedCount, unsynced > 0 {
                    Button {
                        Task {
                            isSyncing = true
                            await viewModel.syncMissingUsers()
                            isSyncing = false
                        }
                    } label: {
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text(isSyncing ? "Synchronisation…" : "Importer \(unsynced) compte(s) vers Jellyseerr")
                                .font(.caption.weight(.semibold))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity, minHeight: 30)
                    }
                    .buttonStyle(.glass)
                    .disabled(isSyncing)
                }
            }
        }
    }

    private func userRow(_ user: UnifiedUser) -> some View {
        let teal = DesignTokens.signalTeal(colorScheme)
        let critical = DesignTokens.critical(colorScheme)
        let nominal = DesignTokens.nominal(colorScheme)
        let caution = DesignTokens.caution(colorScheme)

        return Button {
            selectedUser = user
        } label: {
            GlassCard(padding: 14, cornerRadius: 16, interactive: true) {
                HStack(spacing: 12) {
                    Text(String(user.name.prefix(2)).uppercased())
                        .font(.system(.subheadline, design: .monospaced, weight: .bold))
                        .foregroundStyle(user.isDisabled ? critical : (user.isAdmin ? teal : DesignTokens.primaryText(colorScheme)))
                        .frame(width: 40, height: 40)
                        .background(
                            DesignTokens.surfaceElevated(colorScheme),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(user.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(DesignTokens.primaryText(colorScheme))
                            if user.isProtected == true {
                                Image(systemName: "shield.checkmark.fill")
                                    .font(.caption2)
                                    .foregroundStyle(teal)
                                    .accessibilityLabel("Compte propriétaire protégé")
                            }
                            if user.isAdmin {
                                StatusPill("Admin", color: teal, systemImage: "crown.fill")
                            }
                            if user.isDisabled {
                                StatusPill("Suspendu", color: critical, systemImage: "nosign")
                            }
                        }

                        HStack(spacing: 8) {
                            Text(user.inJellyseerr ? "Jellyseerr: \(user.autoApprove ? "Auto" : "Manuel")" : "Non importé")
                                .font(.caption2)
                                .foregroundStyle(user.inJellyseerr ? nominal : caution)
                            Text("•")
                                .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                            Text("Activité: \(ByteFormatters.formatRelativeISO(user.lastActivity))")
                                .font(.caption2)
                                .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                        }
                    }

                    Spacer()

                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                        .font(.subheadline)
                }
                .frame(minHeight: 44)
            }
        }
        .buttonStyle(.plain)
    }
}
