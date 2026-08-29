import Foundation

enum SearchNormalizer {
    static func normalize(_ source: String) -> String {
        let replacements: [Character: String] = [
            "’": "'", "‘": "'", "ʼ": "'", "＇": "'", "`": "'", "´": "'",
            "œ": "oe", "Œ": "oe", "æ": "ae", "Æ": "ae"
        ]
        let replaced = source.reduce(into: "") { result, character in
            result += replacements[character] ?? String(character)
        }
        return replaced
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                     locale: Locale(identifier: "fr_FR"))
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}
