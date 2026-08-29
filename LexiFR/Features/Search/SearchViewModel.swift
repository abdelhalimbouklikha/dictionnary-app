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
    private var configured = false

    func configure(dictionary: DictionaryRepository?, userStore: UserStore?) {
        guard !configured else { return }
        configured = true
        self.dictionary = dictionary
        self.userStore = userStore
        loadRecent()
    }

    func queryChanged() {
        searchTask?.cancel()
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
                guard let self, let dictionary = self.dictionary else { return }
                let matches = try await dictionary.search(value)
                try Task.checkCancellation()
                self.results = matches
                self.isSearching = false
            } catch is CancellationError {
                return
            } catch {
                guard let self else { return }
                self.isSearching = false
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func loadRecent() {
        guard let userStore else { return }
        Task { [weak self] in
            do { self?.recent = try await userStore.recentWords() }
            catch { self?.errorMessage = error.localizedDescription }
        }
    }
}
