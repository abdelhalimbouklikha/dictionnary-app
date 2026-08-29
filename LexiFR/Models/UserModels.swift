import Foundation

enum WordSort: String, CaseIterable, Codable, Identifiable, Sendable, Hashable {
    case alphabeticalAscending
    case alphabeticalDescending
    case newest
    case oldest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .alphabeticalAscending: "A → Z"
        case .alphabeticalDescending: "Z → A"
        case .newest: "Plus récent"
        case .oldest: "Plus ancien"
        }
    }

    var systemImage: String {
        switch self {
        case .alphabeticalAscending: "text.line.first.and.arrowtriangle.forward"
        case .alphabeticalDescending: "text.line.last.and.arrowtriangle.forward"
        case .newest: "clock.arrow.circlepath"
        case .oldest: "clock"
        }
    }
}

struct SavedWord: Identifiable, Hashable, Sendable {
    let id: String
    let word: String
    let partOfSpeech: String
    let savedAt: Date
    let thumbnailPath: String?

    var summary: WordSummary {
        WordSummary(id: id, word: word, partOfSpeech: partOfSpeech, thumbnailPath: thumbnailPath)
    }
}

struct WordCollection: Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    let createdAt: Date
    var wordCount: Int
    var sort: WordSort
}

struct WordImageRecord: Sendable {
    let originalPath: String
    let thumbnailPath: String
}
