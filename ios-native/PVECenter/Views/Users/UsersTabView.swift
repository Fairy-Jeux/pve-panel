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

    public var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                headerActionsCard

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(UserFilter.allCases) { item in
                            Button {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                                    filter = item
                                }
                            } label: {
                                Text(item.rawValue)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(filter == item ? .white : .primary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        filter == item ? Color.cyan : Color.primary.opacity(0.08),
                                        in: Capsule()
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                ForEach(displayedUsers) { user in
                    userRow(user)
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
                        Text("\(counts?.totalJellyfin ?? 0) comptes • \(counts?.syncedJellyseerr ?? 0) synchronisés")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        showCreateSheet = true
                    } label: {
                        Label("Créer", systemImage: "person.badge.plus")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.cyan.gradient, in: Capsule())
                    }
                    .buttonStyle(.plain)
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
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isSyncing)
                }
            }
        }
    }

    private func userRow(_ user: UnifiedUser) -> some View {
        Button {
            selectedUser = user
        } label: {
            GlassCard(padding: 14, cornerRadius: 18) {
                HStack(spacing: 12) {
                    Text(String(user.name.prefix(2)).uppercased())
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(user.isDisabled ? .red : (user.isAdmin ? .cyan : .primary))
                        .frame(width: 40, height: 40)
                        .background(
                            (user.isDisabled ? Color.red : (user.isAdmin ? Color.cyan : Color.secondary)).opacity(0.14),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(user.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            if user.isProtected == true {
                                Image(systemName: "shield.checkmark.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.indigo)
                            }
                            if user.isAdmin {
                                StatusPill("Admin", color: .cyan)
                            }
                            if user.isDisabled {
                                StatusPill("Suspendu", color: .red)
                            }
                        }

                        HStack(spacing: 8) {
                            Text(user.inJellyseerr ? "Jellyseerr: \(user.autoApprove ? "Auto" : "Manuel")" : "Non importé")
                                .font(.caption2)
                                .foregroundStyle(user.inJellyseerr ? .green : .orange)
                            Text("•")
                                .foregroundStyle(.secondary)
                            Text("Activité: \(ByteFormatters.formatRelativeISO(user.lastActivity))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
