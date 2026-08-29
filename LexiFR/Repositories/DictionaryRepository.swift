import Foundation

actor DictionaryRepository {
    private let database: SQLiteConnection
    private let databaseURL: URL

    init(bundle: Bundle = .main) throws {
        guard let url = bundle.url(forResource: "french", withExtension: "sqlite")
                ?? bundle.url(forResource: "french.sample", withExtension: "sqlite") else {
            throw DatabaseError.open("ressource french.sqlite absente")
        }
        databaseURL = url
        database = try SQLiteConnection(url: url, readOnly: true)
    }

    func search(_ rawQuery: String, limit: Int = 40) throws -> [WordSummary] {
        try Task.checkCancellation()
        let query = SearchNormalizer.normalize(rawQuery)
        guard !query.isEmpty else { return [] }
        let upperBound = query + "\u{10FFFF}"
        let rows = try database.rows(
            """
            WITH matches AS (
                SELECT id, word, pos_title, normalized_word, 0 AS rank
                  FROM entries WHERE normalized_word = ?
                UNION ALL
                SELECT id, word, pos_title, normalized_word, 1 AS rank
                  FROM entries
                 WHERE normalized_word >= ? AND normalized_word < ?
                   AND normalized_word <> ?
                UNION ALL
                SELECT e.id, e.word, e.pos_title, e.normalized_word, 2 AS rank
                  FROM forms f JOIN entries e ON e.rowid = f.entry_rowid
                 WHERE f.normalized_form >= ? AND f.normalized_form < ?
            )
            SELECT id, word, pos_title
              FROM matches
             GROUP BY id
             ORDER BY MIN(rank), normalized_word, word
             LIMIT ?
            """,
            bindings: [
                .text(query), .text(query), .text(upperBound), .text(query),
                .text(query), .text(upperBound), .integer(Int64(limit))
            ]
        )
        try Task.checkCancellation()
        return rows.compactMap { row in
            guard let id = row["id"]?.string,
                  let word = row["word"]?.string,
                  let partOfSpeech = row["pos_title"]?.string else { return nil }
            return WordSummary(id: id, word: word, partOfSpeech: partOfSpeech)
        }
    }

    func entry(id: String) throws -> WordEntry? {
        let entryRows = try database.rows(
            "SELECT rowid AS entry_rowid, id, word, pos_title, gender, etymology FROM entries WHERE id = ? LIMIT 1",
            bindings: [.text(id)]
        )
        guard let row = entryRows.first,
              let entryRowID = row["entry_rowid"]?.int64,
              let word = row["word"]?.string,
              let partOfSpeech = row["pos_title"]?.string else { return nil }

        let pronunciationRows = try database.rows(
            "SELECT id, ipa, region FROM pronunciations WHERE entry_rowid = ? ORDER BY ordinal",
            bindings: [.integer(entryRowID)]
        )
        let pronunciations = pronunciationRows.compactMap { value -> Pronunciation? in
            guard let identifier = value["id"]?.int64, let ipa = value["ipa"]?.string else { return nil }
            return Pronunciation(id: identifier, ipa: ipa, region: value["region"]?.string)
        }

        let senseRows = try database.rows(
            "SELECT id, ordinal, definition, tags_json FROM senses WHERE entry_rowid = ? ORDER BY ordinal",
            bindings: [.integer(entryRowID)]
        )
        var senses: [WordSense] = []
        for value in senseRows {
            guard let senseID = value["id"]?.int64,
                  let definition = value["definition"]?.string else { continue }
            let exampleRows = try database.rows(
                "SELECT id, text, source FROM examples WHERE sense_id = ? ORDER BY ordinal",
                bindings: [.integer(senseID)]
            )
            let examples = exampleRows.compactMap { item -> WordExample? in
                guard let exampleID = item["id"]?.int64, let text = item["text"]?.string else { return nil }
                return WordExample(id: exampleID, text: text, source: item["source"]?.string)
            }
            senses.append(WordSense(
                id: senseID,
                ordinal: value["ordinal"]?.int ?? senses.count,
                definition: definition,
                tags: Self.decodeTags(value["tags_json"]?.string),
                examples: examples
            ))
        }

        let formRows = try database.rows(
            "SELECT id, form, tags_json FROM forms WHERE entry_rowid = ? ORDER BY ordinal",
            bindings: [.integer(entryRowID)]
        )
        let forms = formRows.compactMap { value -> WordForm? in
            guard let formID = value["id"]?.int64, let form = value["form"]?.string else { return nil }
            return WordForm(id: formID, form: form, tags: Self.decodeTags(value["tags_json"]?.string))
        }

        let relationRows = try database.rows(
            "SELECT id, kind, word FROM relations WHERE entry_rowid = ? ORDER BY kind, id",
            bindings: [.integer(entryRowID)]
        )
        let relations = relationRows.compactMap { value -> WordRelation? in
            guard let relationID = value["id"]?.int64,
                  let rawKind = value["kind"]?.string,
                  let kind = RelationKind(rawValue: rawKind),
                  let relatedWord = value["word"]?.string else { return nil }
            return WordRelation(id: relationID, kind: kind, word: relatedWord)
        }

        return WordEntry(
            id: id,
            word: word,
            partOfSpeech: partOfSpeech,
            gender: row["gender"]?.string,
            etymology: row["etymology"]?.string,
            pronunciations: pronunciations,
            senses: senses,
            forms: forms,
            relations: relations
        )
    }

    func metadata() throws -> DictionaryInfo {
        let values: [String: String] = Dictionary(uniqueKeysWithValues: try database.rows("SELECT key, value FROM metadata").compactMap { row in
            guard let key = row["key"]?.string, let value = row["value"]?.string else { return nil }
            return (key, value)
        })
        let fileSize = try? databaseURL.resourceValues(forKeys: [.fileSizeKey]).fileSize
        let size = Int64(fileSize ?? 0)
        return DictionaryInfo(
            entries: Int(values["entry_count"] ?? "0") ?? 0,
            distinctWords: Int(values["distinct_word_count"] ?? "0") ?? 0,
            senses: Int(values["sense_count"] ?? "0") ?? 0,
            examples: Int(values["example_count"] ?? "0") ?? 0,
            sourceName: values["source_name"] ?? "Kaikki/Wiktionnaire",
            databaseBytes: size
        )
    }

    private static func decodeTags(_ json: String?) -> [String] {
        guard let json, let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }
}
