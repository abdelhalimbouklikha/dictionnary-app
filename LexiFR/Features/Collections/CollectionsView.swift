import SwiftUI

struct CollectionsView: View {
    @EnvironmentObject private var app: AppModel
    @State private var collections: [WordCollection] = []
    @State private var showingCreate = false
    @State private var editingCollection: WordCollection?
    @State private var collectionToDelete: WordCollection?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                ForEach(collections) { collection in
                    NavigationLink(value: collection) {
                        HStack(spacing: 12) {
                            Image(systemName: "square.stack")
                                .font(.title3)
                                .foregroundStyle(.tint)
                                .frame(width: 30)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(collection.name).font(.body.weight(.medium))
                                Text("\(collection.wordCount) mot\(collection.wordCount == 1 ? "" : "s")")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .contextMenu {
                        Button { editingCollection = collection } label: {
                            Label("Renommer", systemImage: "pencil")
                        }
                        Button(role: .destructive) { collectionToDelete = collection } label: {
                            Label("Supprimer", systemImage: "trash")
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) { collectionToDelete = collection } label: {
                            Label("Supprimer", systemImage: "trash")
                        }
                    }
                }
            }
            .overlay {
                if collections.isEmpty {
                    ContentUnavailableView {
                        Label("Aucune collection", systemImage: "square.stack")
                    } description: {
                        Text("Créez une collection pour organiser votre vocabulaire.")
                    } actions: {
                        Button("Créer une collection") { showingCreate = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("Collections")
            .navigationDestination(for: WordCollection.self) { collection in
                CollectionDetailView(collection: collection)
            }
            .toolbar {
                Button { showingCreate = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Créer une collection")
            }
            .onAppear { Task { await load() } }
            .refreshable { await load() }
            .sheet(isPresented: $showingCreate) {
                CollectionNameSheet(title: "Nouvelle collection", initialName: "") { name in
                    Task { await create(name) }
                }
            }
            .sheet(item: $editingCollection) { collection in
                CollectionNameSheet(title: "Renommer", initialName: collection.name) { name in
                    Task { await rename(collection, name: name) }
                }
            }
            .confirmationDialog(
                "Supprimer cette collection ?",
                isPresented: Binding(
                    get: { collectionToDelete != nil },
                    set: { if !$0 { collectionToDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Supprimer", role: .destructive) {
                    if let collectionToDelete { Task { await delete(collectionToDelete) } }
                }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Les mots resteront disponibles dans le dictionnaire et dans vos autres collections.")
            }
            .alert("Une erreur est survenue", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
        }
    }

    private func load() async {
        do { collections = try await app.userStore?.collections() ?? [] }
        catch { errorMessage = error.localizedDescription }
    }

    private func create(_ name: String) async {
        do { _ = try await app.userStore?.createCollection(name: name); await load() }
        catch { errorMessage = error.localizedDescription }
    }

    private func rename(_ collection: WordCollection, name: String) async {
        do { try await app.userStore?.renameCollection(id: collection.id, name: name); await load() }
        catch { errorMessage = error.localizedDescription }
    }

    private func delete(_ collection: WordCollection) async {
        do {
            try await app.userStore?.deleteCollection(id: collection.id)
            collectionToDelete = nil
            await load()
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct CollectionNameSheet: View {
    let title: String
    @State var initialName: String
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nom", text: $initialName)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit(save)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer", action: save)
                        .disabled(initialName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.height(190)])
    }

    private func save() {
        let name = initialName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        onSave(name)
        dismiss()
    }
}
