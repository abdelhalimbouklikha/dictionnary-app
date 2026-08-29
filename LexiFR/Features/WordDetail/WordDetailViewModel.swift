import Combine
import Foundation
import PhotosUI
import SwiftUI
import UIKit

@MainActor
final class WordDetailViewModel: ObservableObject {
    @Published private(set) var entry: WordEntry?
    @Published private(set) var isFavorite = false
    @Published private(set) var collections: [WordCollection] = []
    @Published private(set) var memberships: Set<String> = []
    @Published private(set) var image: WordImageRecord?
    @Published private(set) var isLoading = true
    @Published var errorMessage: String?

    private var dictionary: DictionaryRepository?
    private var userStore: UserStore?
    private var imageStore: WordImageStore?
    private var summary: WordSummary?
    private var loaded = false

    func load(
        summary: WordSummary,
        dictionary: DictionaryRepository?,
        userStore: UserStore?,
        imageStore: WordImageStore?
    ) async {
        guard !loaded else { return }
        loaded = true
        self.summary = summary
        self.dictionary = dictionary
        self.userStore = userStore
        self.imageStore = imageStore
        do {
            guard let dictionary, let userStore else { return }
            async let loadedEntry = dictionary.entry(id: summary.id)
            async let favorite = userStore.isFavorite(summary.id)
            async let loadedCollections = userStore.collections()
            async let loadedImage = userStore.image(for: summary.id)
            entry = try await loadedEntry
            isFavorite = try await favorite
            collections = try await loadedCollections
            image = try await loadedImage
            var currentMemberships: Set<String> = []
            for collection in collections {
                if try await userStore.collectionContains(collectionID: collection.id, wordID: summary.id) {
                    currentMemberships.insert(collection.id)
                }
            }
            memberships = currentMemberships
            try await userStore.saveRecent(summary)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func toggleFavorite() {
        guard let summary, let userStore else { return }
        Task {
            do {
                isFavorite = try await userStore.toggleFavorite(summary)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func setMembership(collectionID: String, included: Bool) {
        guard let summary, let userStore else { return }
        Task {
            do {
                try await userStore.setWord(summary, in: collectionID, included: included)
                if included { memberships.insert(collectionID) } else { memberships.remove(collectionID) }
                UISelectionFeedbackGenerator().selectionChanged()
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func importPhoto(_ item: PhotosPickerItem?) {
        guard let item, let summary, let imageStore, let userStore else { return }
        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw WordImageError.invalidImage
                }
                let oldRecord = image
                let newRecord = try await imageStore.save(data: data, wordID: summary.id)
                try await userStore.setImage(newRecord, for: summary.id)
                image = newRecord
                if let oldRecord, oldRecord.originalPath != newRecord.originalPath {
                    try? await imageStore.delete(oldRecord)
                }
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func deletePhoto() {
        guard let image, let summary, let imageStore, let userStore else { return }
        Task {
            do {
                try await imageStore.delete(image)
                try await userStore.setImage(nil, for: summary.id)
                self.image = nil
            } catch { errorMessage = error.localizedDescription }
        }
    }
}
