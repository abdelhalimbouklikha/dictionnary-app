import Foundation

actor UserStore {
    private let database: SQLiteConnection

    init(fileManager: FileManager = .default, databaseURL: URL? = nil) throws {
        let resolvedURL: URL
        if let databaseURL {
            try fileManager.createDirectory(at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            resolvedURL = databaseURL
        } else {
            let support = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let directory = support.appendingPathComponent("LexiFR", isDirectory: true)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            resolvedURL = directory.appendingPathComponent("user.sqlite")
        }
        database = try SQLiteConnection(url: resolvedURL, readOnly: false)
        try database.execute(
            """
            CREATE TABLE IF NOT EXISTS favorites (
                word_id TEXT PRIMARY KEY,
                word TEXT NOT NULL,
                normalized_word TEXT NOT NULL,
                pos_title TEXT NOT NULL,
                thumbnail_path TEXT,
                favorited_at REAL NOT NULL
            )
            """
        )
        try database.execute(
            """
            CREATE TABLE IF NOT EXISTS collections (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                normalized_name TEXT NOT NULL,
                created_at REAL NOT NULL,
                sort_mode TEXT NOT NULL
            )
            """
        )
        try database.execute(
            """
            CREATE TABLE IF NOT EXISTS collection_words (
                collection_id TEXT NOT NULL REFERENCES collections(id) ON DELETE CASCADE,
                word_id TEXT NOT NULL,
                word TEXT NOT NULL,
                normalized_word TEXT NOT NULL,
                pos_title TEXT NOT NULL,
                thumbnail_path TEXT,
                added_at REAL NOT NULL,
                PRIMARY KEY (collection_id, word_id)
            )
            """
        )
        try database.execute(
            """
            CREATE TABLE IF NOT EXISTS word_images (
                word_id TEXT PRIMARY KEY,
                original_path TEXT NOT NULL,
                thumbnail_path TEXT NOT NULL,
                updated_at REAL NOT NULL
            )
            """
        )
        try database.execute(
            """
            CREATE TABLE IF NOT EXISTS recent_words (
                word_id TEXT PRIMARY KEY,
                word TEXT NOT NULL,
                pos_title TEXT NOT NULL,
                viewed_at REAL NOT NULL
            )
            """
        )
        try database.execute(
            "CREATE TABLE IF NOT EXISTS preferences (key TEXT PRIMARY KEY, value TEXT NOT NULL) WITHOUT ROWID"
        )
        try database.execute("CREATE INDEX IF NOT EXISTS favorites_normalized_idx ON favorites(normalized_word)")
        try database.execute("CREATE INDEX IF NOT EXISTS collection_words_sort_idx ON collection_words(collection_id, normalized_word, added_at)")
        try database.execute("CREATE INDEX IF NOT EXISTS recent_words_date_idx ON recent_words(viewed_at DESC)")
    }

    func isFavorite(_ wordID: String) throws -> Bool {
        try !database.rows("SELECT 1 FROM favorites WHERE word_id = ? LIMIT 1", bindings: [.text(wordID)]).isEmpty
    }

    @discardableResult
    func toggleFavorite(_ word: WordSummary) throws -> Bool {
        if try isFavorite(word.id) {
            try database.execute("DELETE FROM favorites WHERE word_id = ?", bindings: [.text(word.id)])
            return false
        }
        let thumbnail = try image(for: word.id)?.thumbnailPath
        try database.execute(
            """
            INSERT INTO favorites
               (word_id, word, normalized_word, pos_title, thumbnail_path, favorited_at)
               VALUES (?, ?, ?, ?, ?, ?)
            """,
            bindings: [
                .text(word.id), .text(word.word), .text(SearchNormalizer.normalize(word.word)),
                .text(word.partOfSpeech), thumbnail.map(SQLiteValue.text) ?? .null,
                .real(Date().timeIntervalSince1970)
            ]
        )
        return true
    }

    func favorites(sort: WordSort) throws -> [SavedWord] {
        try savedWords(
            sql: "SELECT word_id, word, pos_title, thumbnail_path, favorited_at AS saved_at FROM favorites ORDER BY \(sortClause(sort))"
        )
    }

    func collections() throws -> [WordCollection] {
        let rows = try database.rows(
            """
            SELECT c.id, c.name, c.created_at, c.sort_mode, count(cw.word_id) AS word_count
              FROM collections c LEFT JOIN collection_words cw ON cw.collection_id = c.id
             GROUP BY c.id
             ORDER BY c.normalized_name, c.name
            """
        )
        return rows.compactMap { row in
            guard let id = row["id"]?.string,
                  let name = row["name"]?.string,
                  let created = row["created_at"]?.double else { return nil }
            return WordCollection(
                id: id,
                name: name,
                createdAt: Date(timeIntervalSince1970: created),
                wordCount: row["word_count"]?.int ?? 0,
                sort: WordSort(rawValue: row["sort_mode"]?.string ?? "") ?? .alphabeticalAscending
            )
        }
    }

    func createCollection(name: String) throws -> WordCollection {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { throw UserStoreError.emptyCollectionName }
        let id = UUID().uuidString.lowercased()
        let now = Date()
        try database.execute(
            "INSERT INTO collections(id, name, normalized_name, created_at, sort_mode) VALUES (?, ?, ?, ?, ?)",
            bindings: [
                .text(id), .text(cleanName), .text(SearchNormalizer.normalize(cleanName)),
                .real(now.timeIntervalSince1970), .text(WordSort.alphabeticalAscending.rawValue)
            ]
        )
        return WordCollection(id: id, name: cleanName, createdAt: now, wordCount: 0, sort: .alphabeticalAscending)
    }

    func renameCollection(id: String, name: String) throws {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { throw UserStoreError.emptyCollectionName }
        try database.execute(
            "UPDATE collections SET name = ?, normalized_name = ? WHERE id = ?",
            bindings: [.text(cleanName), .text(SearchNormalizer.normalize(cleanName)), .text(id)]
        )
    }

    func deleteCollection(id: String) throws {
        try database.execute("DELETE FROM collections WHERE id = ?", bindings: [.text(id)])
    }

    func setCollectionSort(id: String, sort: WordSort) throws {
        try database.execute(
            "UPDATE collections SET sort_mode = ? WHERE id = ?",
            bindings: [.text(sort.rawValue), .text(id)]
        )
    }

    func collectionContains(collectionID: String, wordID: String) throws -> Bool {
        try !database.rows(
            "SELECT 1 FROM collection_words WHERE collection_id = ? AND word_id = ? LIMIT 1",
            bindings: [.text(collectionID), .text(wordID)]
        ).isEmpty
    }

    func setWord(_ word: WordSummary, in collectionID: String, included: Bool) throws {
        if included {
            let thumbnail = try image(for: word.id)?.thumbnailPath
            try database.execute(
                """
                INSERT OR REPLACE INTO collection_words
                   (collection_id, word_id, word, normalized_word, pos_title, thumbnail_path, added_at)
                   VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                bindings: [
                    .text(collectionID), .text(word.id), .text(word.word),
                    .text(SearchNormalizer.normalize(word.word)), .text(word.partOfSpeech),
                    thumbnail.map(SQLiteValue.text) ?? .null, .real(Date().timeIntervalSince1970)
                ]
            )
        } else {
            try database.execute(
                "DELETE FROM collection_words WHERE collection_id = ? AND word_id = ?",
                bindings: [.text(collectionID), .text(word.id)]
            )
        }
    }

    func words(in collectionID: String, sort: WordSort) throws -> [SavedWord] {
        try savedWords(
            sql: """
                SELECT word_id, word, pos_title, thumbnail_path, added_at AS saved_at
                  FROM collection_words WHERE collection_id = ?
                 ORDER BY \(sortClause(sort))
                """,
            bindings: [.text(collectionID)]
        )
    }

    func saveRecent(_ word: WordSummary) throws {
        try database.execute(
            """
            INSERT INTO recent_words(word_id, word, pos_title, viewed_at) VALUES (?, ?, ?, ?)
               ON CONFLICT(word_id) DO UPDATE SET word=excluded.word, pos_title=excluded.pos_title, viewed_at=excluded.viewed_at
            """,
            bindings: [.text(word.id), .text(word.word), .text(word.partOfSpeech), .real(Date().timeIntervalSince1970)]
        )
        try database.execute(
            "DELETE FROM recent_words WHERE word_id NOT IN (SELECT word_id FROM recent_words ORDER BY viewed_at DESC LIMIT 30)"
        )
    }

    func recentWords(limit: Int = 12) throws -> [WordSummary] {
        try database.rows(
            "SELECT word_id, word, pos_title FROM recent_words ORDER BY viewed_at DESC LIMIT ?",
            bindings: [.integer(Int64(limit))]
        ).compactMap { row in
            guard let id = row["word_id"]?.string,
                  let word = row["word"]?.string,
                  let partOfSpeech = row["pos_title"]?.string else { return nil }
            return WordSummary(id: id, word: word, partOfSpeech: partOfSpeech)
        }
    }

    func clearRecents() throws {
        try database.execute("DELETE FROM recent_words")
    }

    func image(for wordID: String) throws -> WordImageRecord? {
        guard let row = try database.rows(
            "SELECT original_path, thumbnail_path FROM word_images WHERE word_id = ? LIMIT 1",
            bindings: [.text(wordID)]
        ).first,
        let original = row["original_path"]?.string,
        let thumbnail = row["thumbnail_path"]?.string else { return nil }
        return WordImageRecord(originalPath: original, thumbnailPath: thumbnail)
    }

    func setImage(_ record: WordImageRecord?, for wordID: String) throws {
        if let record {
            try database.execute(
                """
                INSERT INTO word_images(word_id, original_path, thumbnail_path, updated_at) VALUES (?, ?, ?, ?)
                   ON CONFLICT(word_id) DO UPDATE SET original_path=excluded.original_path,
                   thumbnail_path=excluded.thumbnail_path, updated_at=excluded.updated_at
                """,
                bindings: [
                    .text(wordID), .text(record.originalPath), .text(record.thumbnailPath),
                    .real(Date().timeIntervalSince1970)
                ]
            )
        } else {
            try database.execute("DELETE FROM word_images WHERE word_id = ?", bindings: [.text(wordID)])
        }
        let thumbnail: SQLiteValue = record.map { .text($0.thumbnailPath) } ?? .null
        try database.execute("UPDATE favorites SET thumbnail_path = ? WHERE word_id = ?", bindings: [thumbnail, .text(wordID)])
        try database.execute("UPDATE collection_words SET thumbnail_path = ? WHERE word_id = ?", bindings: [thumbnail, .text(wordID)])
    }

    func preference(_ key: String) throws -> String? {
        try database.rows("SELECT value FROM preferences WHERE key = ? LIMIT 1", bindings: [.text(key)]).first?["value"]?.string
    }

    func setPreference(_ value: String, key: String) throws {
        try database.execute(
            "INSERT INTO preferences(key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
            bindings: [.text(key), .text(value)]
        )
    }

    private func savedWords(sql: String, bindings: [SQLiteValue] = []) throws -> [SavedWord] {
        try database.rows(sql, bindings: bindings).compactMap { row in
            guard let id = row["word_id"]?.string,
                  let word = row["word"]?.string,
                  let partOfSpeech = row["pos_title"]?.string,
                  let savedAt = row["saved_at"]?.double else { return nil }
            return SavedWord(
                id: id,
                word: word,
                partOfSpeech: partOfSpeech,
                savedAt: Date(timeIntervalSince1970: savedAt),
                thumbnailPath: row["thumbnail_path"]?.string
            )
        }
    }

    private func sortClause(_ sort: WordSort) -> String {
        switch sort {
        case .alphabeticalAscending: "normalized_word ASC, word ASC"
        case .alphabeticalDescending: "normalized_word DESC, word DESC"
        case .newest: "saved_at DESC"
        case .oldest: "saved_at ASC"
        }
    }
}

enum UserStoreError: LocalizedError {
    case emptyCollectionName

    var errorDescription: String? { "Le nom de la collection ne peut pas être vide." }
}
