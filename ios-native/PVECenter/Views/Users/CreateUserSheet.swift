import SwiftUI

public struct CreateUserSheet: View {
    public var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var username: String = ""
    @State private var password: String = ""
    @State private var syncJellyseerr: Bool = true
    @State private var autoApprove: Bool = true
    @State private var enableAllFolders: Bool = true
    @State private var selectedFolders: Set<String> = []
    @State private var enableDownloading: Bool = true
    @State private var maxActiveSessions: Int = 2
    @State private var isSubmitting: Bool = false

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    private var libraries: [JellyfinLibrary] {
        viewModel.usersOverview?.libraries ?? []
    }

    private var isValid: Bool {
        username.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 && password.count >= 4
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Identifiants Jellyfin") {
                    TextField("Nom d'utilisateur (min. 2 car.)", text: $username)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                    SecureField("Mot de passe (min. 4 car.)", text: $password)
                }

                Section("Médiathèques autorisées") {
                    Toggle("Accès à toutes les médiathèques", isOn: $enableAllFolders)
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
                }

                Section("Quotas & Téléchargements") {
                    Toggle("Téléchargement hors-ligne autorisé", isOn: $enableDownloading)
                    Stepper(
                        maxActiveSessions == 0 ? "Écrans simultanés : Illimité" : "Écrans simultanés : \(maxActiveSessions)",
                        value: $maxActiveSessions,
                        in: 0...10
                    )
                }

                Section("Synchronisation Jellyseerr") {
                    Toggle("Créer aussi sur Jellyseerr", isOn: $syncJellyseerr)
                    if syncJellyseerr {
                        Toggle("Approbation automatique des demandes", isOn: $autoApprove)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Nouvel utilisateur")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSubmitting ? "Création…" : "Créer") {
                        Task {
                            isSubmitting = true
                            let ok = await viewModel.createUser(
                                CreateUserRequest(
                                    username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                                    password: password,
                                    syncJellyseerr: syncJellyseerr,
                                    autoApprove: autoApprove,
                                    enableAllFolders: enableAllFolders,
                                    enabledFolders: enableAllFolders ? [] : Array(selectedFolders),
                                    enableDownloading: enableDownloading,
                                    maxActiveSessions: maxActiveSessions
                                )
                            )
                            isSubmitting = false
                            if ok { dismiss() }
                        }
                    }
                    .disabled(!isValid || isSubmitting)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, idealWidth: 540, minHeight: 460)
        #endif
    }
}
