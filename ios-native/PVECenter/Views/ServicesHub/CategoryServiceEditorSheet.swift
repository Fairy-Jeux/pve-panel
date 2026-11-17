import SwiftUI

public struct CategoryServiceDraft: Identifiable, Hashable, Sendable {
    public let id: String
    public let categoryName: String
    public let service: ServiceItem

    public init(categoryName: String, service: ServiceItem) {
        self.id = service.id
        self.categoryName = categoryName
        self.service = service
    }

    public static func == (lhs: CategoryServiceDraft, rhs: CategoryServiceDraft) -> Bool {
        lhs.id == rhs.id && lhs.categoryName == rhs.categoryName && lhs.service == rhs.service
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(categoryName)
    }
}

private struct WidgetOption: Identifiable {
    let id: String
    let label: String
}

private let WIDGET_OPTIONS: [WidgetOption] = [
    WidgetOption(id: "", label: "Aucun widget"),
    WidgetOption(id: "jellyfin", label: "Jellyfin (flux & médiathèque)"),
    WidgetOption(id: "plex", label: "Plex (flux & librairies)"),
    WidgetOption(id: "radarr", label: "Radarr (films & file)"),
    WidgetOption(id: "sonarr", label: "Sonarr (séries & épisodes)"),
    WidgetOption(id: "prowlarr", label: "Prowlarr (indexeurs & grabs)"),
    WidgetOption(id: "qbittorrent", label: "qBittorrent (débit DL/UP)"),
]

public struct CategoryServiceEditorSheet: View {
    public var viewModel: AppViewModel
    public let draft: CategoryServiceDraft

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var name: String
    @State private var description: String
    @State private var category: String
    @State private var icon: String
    @State private var url: String
    @State private var pingUrl: String
    @State private var widget: String

    @State private var isTesting: Bool = false
    @State private var testResult: CategoryServiceTestResponse?
    @State private var isSaving: Bool = false
    @State private var isDeleting: Bool = false
    @State private var confirmDelete: Bool = false

    public init(viewModel: AppViewModel, draft: CategoryServiceDraft) {
        self.viewModel = viewModel
        self.draft = draft
        _name = State(initialValue: draft.service.name)
        _description = State(initialValue: draft.service.description)
        _category = State(initialValue: draft.categoryName)
        _icon = State(initialValue: draft.service.icon)
        _url = State(initialValue: draft.service.url)
        _pingUrl = State(initialValue: draft.service.pingUrl ?? "")
        _widget = State(initialValue: draft.service.widget ?? "")
    }

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var categorySuggestions: [String] {
        var list = viewModel.categories.map(\.name)
        for fallback in [
            "Médias & Streaming",
            "Téléchargements & Indexeurs",
            "Cloud, Sécurité & Gaming",
            "Infrastructure & Réseau",
            "Services Personnalisés",
        ] where !list.contains(where: { $0.caseInsensitiveCompare(fallback) == .orderedSame }) {
            list.append(fallback)
        }
        return list
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Application") {
                    TextField("Nom affiché", text: $name)
                    TextField("Description", text: $description)
                    TextField("Catégorie", text: $category)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(categorySuggestions, id: \.self) { suggestion in
                                Button(suggestion) {
                                    category = suggestion
                                }
                                .buttonStyle(.bordered)
                                .tint(category == suggestion ? DesignTokens.signalTeal(colorScheme) : .secondary)
                                #if !os(tvOS)
                                .controlSize(.small)
                                #endif
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                ServiceIconPickerSection(
                    selectedIcon: $icon,
                    serviceId: draft.service.id,
                    serviceName: name,
                    widget: widget
                )

                Section("Liens & Supervision") {
                    TextField("URL d'ouverture (https://…)", text: $url)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        #endif

                    TextField("URL Healthcheck interne (ping_url, optionnelle)", text: $pingUrl)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        #endif

                    Picker("Widget temps réel", selection: $widget) {
                        ForEach(WIDGET_OPTIONS) { opt in
                            Text(opt.label).tag(opt.id)
                        }
                    }
                }

                Section("Test de joignabilité") {
                    Button {
                        Task { await runTest() }
                    } label: {
                        HStack {
                            Label(isTesting ? "Test en cours…" : "Tester maintenant", systemImage: "bolt.horizontal.circle")
                            Spacer()
                            if isTesting {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isTesting)

                    if let res = testResult {
                        HStack(spacing: 8) {
                            Image(systemName: res.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(res.ok ? DesignTokens.nominal(colorScheme) : DesignTokens.critical(colorScheme))
                            Text(res.message)
                                .font(.caption)
                            Spacer()
                            if let ms = res.latencyMs {
                                Text("\(ms) ms")
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(DesignTokens.secondaryText(colorScheme))
                            }
                        }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label(isDeleting ? "Suppression…" : "Retirer cette application du panneau", systemImage: "trash")
                    }
                    .disabled(isDeleting)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Personnaliser")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Enregistrement…" : "Enregistrer") {
                        Task { await saveChanges() }
                    }
                    .disabled(!canSubmit || isSaving)
                }
            }
            .confirmationDialog(
                "Retirer « \(draft.service.name) » du panneau ?",
                isPresented: $confirmDelete,
                titleVisibility: .visible
            ) {
                Button("Supprimer", role: .destructive) {
                    Task {
                        isDeleting = true
                        let ok = await viewModel.deleteCategoryService(id: draft.service.id)
                        isDeleting = false
                        if ok {
                            dismiss()
                        }
                    }
                }
                Button("Annuler", role: .cancel) {}
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, idealWidth: 580, minHeight: 560)
        #endif
    }

    private func runTest() async {
        isTesting = true
        defer { isTesting = false }
        let payload = CategoryServiceTestRequest(
            url: url.trimmingCharacters(in: .whitespacesAndNewlines),
            pingUrl: pingUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        testResult = await viewModel.testCategoryService(id: draft.service.id, override: payload)
    }

    private func saveChanges() async {
        isSaving = true
        defer { isSaving = false }
        let payload = CategoryServiceUpdateRequest(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            url: url.trimmingCharacters(in: .whitespacesAndNewlines),
            pingUrl: pingUrl.trimmingCharacters(in: .whitespacesAndNewlines),
            icon: icon.trimmingCharacters(in: .whitespacesAndNewlines),
            widget: widget.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        let ok = await viewModel.updateCategoryService(id: draft.service.id, payload: payload)
        if ok {
            dismiss()
        }
    }
}
