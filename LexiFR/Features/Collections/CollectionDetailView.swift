import SwiftUI

struct CollectionDetailView: View {
    @EnvironmentObject private var app: AppModel
    @State var collection: WordCollection
    @State private var words: [SavedWord] = []
    @State private var errorMessage: String?

    var body: some View {
        List {
            ForEach(words) { savedWord in
                NavigationLink(value: savedWord.summary) { WordRow(word: savedWord.summary) }
                    .swipeActions {
                        Button(role: .destructive) { remove(savedWord) } label: {
                            Label("Retirer", systemImage: "minus.circle")
                        }
                    }
            }
        }
        .overlay {
            if words.isEmpty {
                ContentUnavailableView(
                    "Collection vide",
                    systemImage: "square.stack",
                    description: Text("Ajoutez des mots depuis leur fiche.")
                )
            }
        }
        .navigationTitle(collection.name)
        .navigationDestination(for: WordSummary.self) { WordDetailView(summary: $0) }
        .toolbar {
            Menu {
                Picker("Tri", selection: $collection.sort) {
                    ForEach(WordSort.allCases) { option in
                        Label(option.title, systemImage: option.systemImage).tag(option)
                    }
                }
            } label: { Image(systemName: "arrow.up.arrow.down") }
            .accessibilityLabel("Trier la collection")
        }
        .onAppear { Task { await load() } }
        .onChange(of: collection.sort) { _, value in
            Task {
                do {
                    try await app.userStore?.setCollectionSort(id: collection.id, sort: value)
                    await load()
                } catch { errorMessage = error.localizedDescription }
            }
        }
        .refreshable { await load() }
        .alert("Une erreur est survenue", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
    }

    private func load() async {
        do { words = try await app.userStore?.words(in: collection.id, sort: collection.sort) ?? [] }
        catch { errorMessage = error.localizedDescription }
    }

    private func remove(_ word: SavedWord) {
        Task {
            do {
                try await app.userStore?.setWord(word.summary, in: collection.id, included: false)
                await load()
            } catch { errorMessage = error.localizedDescription }
        }
    }
}
