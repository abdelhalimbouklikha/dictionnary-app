import SwiftUI

struct FavoritesView: View {
    @EnvironmentObject private var app: AppModel
    @State private var words: [SavedWord] = []
    @State private var sort: WordSort = .alphabeticalAscending
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                ForEach(words) { savedWord in
                    NavigationLink(value: savedWord.summary) {
                        WordRow(word: savedWord.summary)
                    }
                    .swipeActions {
                        Button(role: .destructive) { remove(savedWord) } label: {
                            Label("Retirer", systemImage: "heart.slash")
                        }
                    }
                }
            }
            .overlay {
                if words.isEmpty {
                    ContentUnavailableView(
                        "Aucun favori",
                        systemImage: "heart",
                        description: Text("Les mots que vous marquez apparaîtront ici.")
                    )
                }
            }
            .navigationTitle("Favoris")
            .navigationDestination(for: WordSummary.self) { WordDetailView(summary: $0) }
            .toolbar { sortMenu }
            .refreshable { await load() }
            .task { await load() }
            .onChange(of: sort) { _, _ in
                Task {
                    try? await app.userStore?.setPreference(sort.rawValue, key: "favorites.sort")
                    await loadWords()
                }
            }
            .alert("Une erreur est survenue", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
        }
    }

    private var sortMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Tri", selection: $sort) {
                    ForEach(WordSort.allCases) { option in
                        Label(option.title, systemImage: option.systemImage).tag(option)
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .accessibilityLabel("Trier les favoris")
        }
    }

    private func load() async {
        if let userStore = app.userStore {
            do {
                if let stored = try await userStore.preference("favorites.sort"),
                   let value = WordSort(rawValue: stored) {
                    sort = value
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        await loadWords()
    }

    private func loadWords() async {
        do { words = try await app.userStore?.favorites(sort: sort) ?? [] }
        catch { errorMessage = error.localizedDescription }
    }

    private func remove(_ word: SavedWord) {
        Task {
            do {
                _ = try await app.userStore?.toggleFavorite(word.summary)
                await loadWords()
            } catch { errorMessage = error.localizedDescription }
        }
    }
}
