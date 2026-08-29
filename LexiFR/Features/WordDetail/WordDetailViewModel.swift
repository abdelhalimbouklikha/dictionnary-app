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
    private var loadedSummaryID: String?
    private var photoTask: Task<Void, Never>?

    func load(
        summary: WordSummary,
        dictionary: DictionaryRepository?,
        userStore: UserStore?,
        imageStore: WordImageStore?
    ) async {
        let isNewSummary = loadedSummaryID != summary.id
        guard isNewSummary || entry == nil else { return }
        loadedSummaryID = summary.id
        isLoading = true
        entry = nil
        if isNewSummary {
            isFavorite = false
            collections = []
            memberships = []
            image = nil
            errorMessage = nil
        }
        self.summary = summary
        self.dictionary = dictionary
        self.userStore = userStore
        self.imageStore = imageStore
        guard let dictionary, let userStore else {
            isLoading = false
            return
        }
        do {
            async let loadedEntry = dictionary.entry(id: summary.id)
            async let favorite = userStore.isFavorite(summary.id)
            async let loadedCollections = userStore.collections()
            async let loadedImage = userStore.image(for: summary.id)
            async let loadedMemberships = userStore.collectionMemberships(for: summary.id)
            let values = try await (
                loadedEntry, favorite, loadedCollections, loadedImage, loadedMemberships
            )
            try Task.checkCancellation()
            guard loadedSummaryID == summary.id else { return }
            entry = values.0
            isFavorite = values.1
            collections = values.2
            image = values.3
            memberships = values.4
            try await userStore.saveRecent(summary)
        } catch is CancellationError {
            if loadedSummaryID == summary.id, entry == nil {
                loadedSummaryID = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        if loadedSummaryID == summary.id {
            isLoading = false
        }
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
        photoTask?.cancel()
        let oldRecord = image
        photoTask = Task { [weak self] in
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw WordImageError.invalidImage
                }
                try Task.checkCancellation()
                let newRecord = try await imageStore.save(data: data, wordID: summary.id)
                if Task.isCancelled {
                    if oldRecord?.originalPath != newRecord.originalPath {
                        try? await imageStore.delete(newRecord)
                    }
                    return
                }
                do {
                    try await userStore.setImage(newRecord, for: summary.id)
                } catch {
                    if oldRecord?.originalPath != newRecord.originalPath {
                        try? await imageStore.delete(newRecord)
                    }
                    throw error
                }
                self?.image = newRecord
                if let oldRecord, oldRecord.originalPath != newRecord.originalPath {
                    try? await imageStore.delete(oldRecord)
                }
            } catch is CancellationError {
                return
            } catch {
                self?.errorMessage = error.localizedDescription
            }
        }
    }

    func deletePhoto() {
        guard let image, let summary, let imageStore, let userStore else { return }
        photoTask?.cancel()
        Task {
            do {
                try await userStore.setImage(nil, for: summary.id)
                self.image = nil
                try await imageStore.delete(image)
            } catch { errorMessage = error.localizedDescription }
        }
    }
}
