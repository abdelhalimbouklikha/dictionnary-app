import Combine
import Foundation

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query = ""
    @Published private(set) var results: [WordSummary] = []
    @Published private(set) var recent: [WordSummary] = []
    @Published private(set) var isSearching = false
    @Published var errorMessage: String?

    private var dictionary: DictionaryRepository?
    private var userStore: UserStore?
    private var searchTask: Task<Void, Never>?
    private var recentTask: Task<Void, Never>?
    private var searchGeneration = 0
    private var configured = false

    func configure(dictionary: DictionaryRepository?, userStore: UserStore?) {
        if !configured {
            configured = true
            self.dictionary = dictionary
            self.userStore = userStore
        }
        if query.isEmpty { loadRecent() }
    }

    func queryChanged() {
        searchTask?.cancel()
        recentTask?.cancel()
        searchGeneration &+= 1
        let generation = searchGeneration
        let value = query
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            results = []
            isSearching = false
            loadRecent()
            return
        }
        isSearching = true
        searchTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(130))
                guard let dictionary = self?.dictionary else { return }
                let matches = try await dictionary.search(value)
                try Task.checkCancellation()
                guard let self else { return }
                guard self.searchGeneration == generation, self.query == value else { return }
                self.results = matches
                self.isSearching = false
            } catch is CancellationError {
                return
            } catch {
                guard let self else { return }
                guard self.searchGeneration == generation else { return }
                self.isSearching = false
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func loadRecent() {
        guard let userStore else { return }
        recentTask?.cancel()
        recentTask = Task { [weak self] in
            do {
                let values = try await userStore.recentWords()
                try Task.checkCancellation()
                guard let self, self.query.isEmpty else { return }
                self.recent = values
            } catch is CancellationError {
                return
            } catch {
                self?.errorMessage = error.localizedDescription
            }
        }
    }

    func cancelOutstandingTasks() {
        searchTask?.cancel()
        recentTask?.cancel()
    }
}
