import Foundation

struct WordSummary: Identifiable, Hashable, Sendable {
    let id: String
    let word: String
    let partOfSpeech: String
    var thumbnailPath: String?
}

struct WordEntry: Identifiable, Sendable {
    let id: String
    let word: String
    let partOfSpeech: String
    let gender: String?
    let etymology: String?
    let pronunciations: [Pronunciation]
    let senses: [WordSense]
    let forms: [WordForm]
    let relations: [WordRelation]
    let relationSections: [WordRelationSection]

    var summary: WordSummary {
        WordSummary(id: id, word: word, partOfSpeech: partOfSpeech)
    }
}

struct WordRelationSection: Identifiable, Sendable {
    var id: RelationKind { kind }
    let kind: RelationKind
    let relations: [WordRelation]
}

struct Pronunciation: Identifiable, Sendable {
    let id: Int64
    let ipa: String
    let region: String?
}

struct WordSense: Identifiable, Sendable {
    let id: Int64
    let ordinal: Int
    let definition: String
    let tags: [String]
    let examples: [WordExample]
}

struct WordExample: Identifiable, Sendable {
    let id: Int64
    let text: String
    let source: String?
}

struct WordForm: Identifiable, Sendable {
    let id: Int64
    let form: String
    let tags: [String]
}

struct WordRelation: Identifiable, Sendable {
    let id: Int64
    let kind: RelationKind
    let word: String
}

enum RelationKind: String, Sendable, CaseIterable, Hashable {
    case synonyms
    case antonyms
    case hypernyms
    case hyponyms
    case holonyms
    case meronyms
    case derived
    case related
    case coordinateTerms = "coordinate_terms"
    case paronyms
    case abbreviations
    case proverbs

    var title: String {
        switch self {
        case .synonyms: "Synonymes"
        case .antonyms: "Antonymes"
        case .hypernyms: "Termes génériques"
        case .hyponyms: "Termes spécifiques"
        case .holonyms: "Ensembles"
        case .meronyms: "Composants"
        case .derived: "Dérivés"
        case .related: "Termes liés"
        case .coordinateTerms: "Termes coordonnés"
        case .paronyms: "Paronymes"
        case .abbreviations: "Abréviations"
        case .proverbs: "Proverbes"
        }
    }
}

struct DictionaryInfo: Sendable {
    let entries: Int
    let distinctWords: Int
    let senses: Int
    let examples: Int
    let sourceName: String
    let databaseBytes: Int64
}
