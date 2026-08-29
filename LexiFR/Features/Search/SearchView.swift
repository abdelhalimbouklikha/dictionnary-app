import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var app: AppModel
    @StateObject private var viewModel = SearchViewModel()
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationStack {
            List {
                Section {
                    searchField
                        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                }
                if viewModel.query.isEmpty {
                    if !viewModel.recent.isEmpty {
                        Section("Consultés récemment") {
                            wordLinks(viewModel.recent)
                        }
                    } else {
                        Section {
                            Text("Recherchez un mot, une variante ou une forme fléchie.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .listRowBackground(Color.clear)
                        }
                    }
                } else if viewModel.results.isEmpty, !viewModel.isSearching {
                    ContentUnavailableView.search(text: viewModel.query)
                        .listRowBackground(Color.clear)
                } else {
                    Section {
                        wordLinks(viewModel.results)
                    } footer: {
                        if viewModel.isSearching {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("Recherche…")
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("LexiFR")
            .navigationDestination(for: WordSummary.self) { summary in
                WordDetailView(summary: summary)
            }
            .task {
                viewModel.configure(dictionary: app.dictionary, userStore: app.userStore)
                searchFocused = true
            }
            .onChange(of: viewModel.query) { _, _ in viewModel.queryChanged() }
            .alert("Une erreur est survenue", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) { Button("OK", role: .cancel) {} } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Rechercher un mot…", text: $viewModel.query)
                .focused($searchFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !viewModel.query.isEmpty {
                Button {
                    viewModel.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Effacer la recherche")
            }
        }
        .font(.body)
    }

    @ViewBuilder
    private func wordLinks(_ words: [WordSummary]) -> some View {
        ForEach(words) { word in
            NavigationLink(value: word) { WordRow(word: word) }
        }
    }
}
