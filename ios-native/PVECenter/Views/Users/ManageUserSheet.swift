import SwiftUI

public struct ManageUserSheet: View {
    public var viewModel: AppViewModel
    public let user: UnifiedUser
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var isDisabled: Bool
    @State private var isAdmin: Bool
    @State private var enableAllFolders: Bool
    @State private var selectedFolders: Set<String>
    @State private var enableDownloading: Bool
    @State private var maxActiveSessions: Int
    @State private var autoApprove: Bool

    @State private var newPassword: String = ""
    @State private var isSaving: Bool = false
    @State private var confirmDelete: Bool = false

    public init(viewModel: AppViewModel, user: UnifiedUser) {
        self.viewModel = viewModel
        self.user = user
        _isDisabled = State(initialValue: user.isDisabled)
        _isAdmin = State(initialValue: user.isAdmin)
        _enableAllFolders = State(initialValue: user.enableAllFolders)
        _selectedFolders = State(initialValue: Set(user.enabledFolders))
        _enableDownloading = State(initialValue: user.enableDownloading)
        _maxActiveSessions = State(initialValue: user.maxActiveSessions)
        _autoApprove = State(initialValue: user.autoApprove)
    }

    private var isProtectedOwner: Bool {
        user.isProtected == true
    }

    private var libraries: [JellyfinLibrary] {
        viewModel.usersOverview?.libraries ?? []
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Statut & Rôle") {
                    if isProtectedOwner {
                        Label("Compte propriétaire protégé : suspension, rétrogradation et suppression verrouillées.", systemImage: "shield.checkmark.fill")
                            .font(.caption)
                            .foregroundStyle(.indigo)
                    }
                    Toggle("Compte suspendu (Jellyfin)", isOn: $isDisabled)
                        .disabled(isProtectedOwner)
                    Toggle("Administrateur Jellyfin", isOn: $isAdmin)
                        .disabled(isProtectedOwner)
                }

                Section("Médiathèques & Quotas") {
                    Toggle("Toutes les médiathèques", isOn: $enableAllFolders)
                    if !enableAllFolders {
                        ForEach(libraries) { library in
                            let included = selectedFolders.contains(library.id)
                            Button {
                                if included {
                                    selectedFolders.remove(library.id)
                                } else {
                                    selectedFolders.insert(library.id)
                                }
                            } label: {
                                HStack {
                                    Text(library.name)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if included {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.cyan)
                                    }
                                }
                            }
                        }
                    }

                    Toggle("Téléchargement autorisé", isOn: $enableDownloading)
                    MaxActiveSessionsControl(maxActiveSessions: $maxActiveSessions)
                }

                Section("Jellyseerr") {
                    if user.inJellyseerr {
                        Toggle("Auto-approbation des demandes", isOn: $autoApprove)
                            .disabled(isProtectedOwner)
                        HStack {
                            Text("Demandes effectuées")
                            Spacer()
                            Text("\(user.requestCount)")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Button("Importer dans Jellyseerr maintenant") {
                            Task {
                                await viewModel.syncMissingUsers(userIDs: [user.jellyfinId])
                                dismiss()
                            }
                        }
                    }
                }

                Section("Sécurité") {
                    HStack {
                        SecureField("Nouveau mot de passe (min. 4 car.)", text: $newPassword)
                        Button("Appliquer") {
                            Task {
                                isSaving = true
                                let ok = await viewModel.resetPassword(id: user.jellyfinId, newPassword: newPassword)
                                isSaving = false
                                if ok { newPassword = "" }
                            }
                        }
                        .disabled(newPassword.count < 4 || isSaving)
                    }
                }

                if !isProtectedOwner {
                    Section {
                        Button("Supprimer le compte (Jellyfin + Jellyseerr)", role: .destructive) {
                            confirmDelete = true
                        }
                    }
                }

                #if os(tvOS)
                Section {
                    HStack(spacing: 14) {
                        Button("Fermer") { dismiss() }
                            .adaptivePillButtonStyle()
                        Spacer()
                        Button {
                            guard !isSaving else { return }
                            Task {
                                isSaving = true
                                let payload = UpdateUserRequest(
                                    isDisabled: isProtectedOwner ? nil : isDisabled,
                                    isAdmin: isProtectedOwner ? nil : isAdmin,
                                    enableAllFolders: enableAllFolders,
                                    enabledFolders: enableAllFolders ? [] : Array(selectedFolders),
                                    enableDownloading: enableDownloading,
                                    maxActiveSessions: maxActiveSessions,
                                    autoApprove: user.inJellyseerr && !isProtectedOwner ? autoApprove : nil
                                )
                                let ok = await viewModel.updateUser(id: user.jellyfinId, payload: payload)
                                isSaving = false
                                if ok { dismiss() }
                            }
                        } label: {
                            Text(isSaving ? "Enregistrement…" : "Enregistrer")
                                .opacity(isSaving ? 0.5 : 1.0)
                        }
                        .adaptivePillButtonStyle(tint: DesignTokens.signalTeal(colorScheme), prominent: true)
                    }
                }
                #endif
            }
            .adaptiveTVOSModalFormContainer()
            .navigationTitle(user.name)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Enregistrement…" : "Enregistrer") {
                        Task {
                            isSaving = true
                            let payload = UpdateUserRequest(
                                isDisabled: isProtectedOwner ? nil : isDisabled,
                                isAdmin: isProtectedOwner ? nil : isAdmin,
                                enableAllFolders: enableAllFolders,
                                enabledFolders: enableAllFolders ? [] : Array(selectedFolders),
                                enableDownloading: enableDownloading,
                                maxActiveSessions: maxActiveSessions,
                                autoApprove: user.inJellyseerr && !isProtectedOwner ? autoApprove : nil
                            )
                            let ok = await viewModel.updateUser(id: user.jellyfinId, payload: payload)
                            isSaving = false
                            if ok { dismiss() }
                        }
                    }
                    .disabled(isSaving)
                }
            }
            .confirmationDialog(
                "Supprimer définitivement « \(user.name) » ?",
                isPresented: $confirmDelete,
                titleVisibility: .visible
            ) {
                Button("Supprimer", role: .destructive) {
                    Task {
                        isSaving = true
                        let ok = await viewModel.deleteUser(id: user.jellyfinId, name: user.name)
                        isSaving = false
                        if ok { dismiss() }
                    }
                }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Ce compte sera supprimé de Jellyfin et de Jellyseerr.")
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, idealWidth: 540, minHeight: 500)
        #endif
    }
}
