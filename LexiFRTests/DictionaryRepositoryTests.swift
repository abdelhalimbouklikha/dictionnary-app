import XCTest
@testable import LexiFR

final class DictionaryRepositoryTests: XCTestCase {
    func testExactAccentlessPrefixAndFormSearch() async throws {
        let repository = try DictionaryRepository()
        let exact = try await repository.search("ÉCOLE")
        XCTAssertEqual(exact.first?.word, "école")
        let accentless = try await repository.search("ecole")
        XCTAssertTrue(accentless.contains { $0.word == "école" })
        let prefix = try await repository.search("épan")
        XCTAssertEqual(Array(prefix.prefix(2).map(\.word)), ["épanouir", "épanouissement"])
        let inflection = try await repository.search("suis")
        XCTAssertTrue(inflection.contains { $0.word == "être" })
    }

    func testEntryLoadsAllSections() async throws {
        let repository = try DictionaryRepository()
        let matches = try await repository.search("école")
        let summary = try XCTUnwrap(matches.first)
        let loadedEntry = try await repository.entry(id: summary.id)
        let entry = try XCTUnwrap(loadedEntry)
        XCTAssertFalse(entry.senses.isEmpty)
        XCTAssertFalse(entry.pronunciations.isEmpty)
        XCTAssertFalse(entry.forms.isEmpty)
    }

    func testVeryLargeEntryLoadsWithFixedQueryCountAndStableGroups() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let databaseURL = directory.appendingPathComponent("large.sqlite")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try makeLargeEntryDatabase(at: databaseURL)

        let repository = try DictionaryRepository(databaseURL: databaseURL)
#if DEBUG
        let statementsBeforeLoad = await repository.preparedStatementCountForTesting()
#endif
        let loaded = try await repository.entry(id: "large-entry")
        let entry = try XCTUnwrap(loaded)

        XCTAssertEqual(entry.senses.count, 200)
        XCTAssertEqual(entry.senses.reduce(0) { $0 + $1.examples.count }, 1_000)
        XCTAssertEqual(entry.forms.count, 500)
        XCTAssertEqual(entry.relations.count, 2_000)
        XCTAssertEqual(entry.relationSections.reduce(0) { $0 + $1.relations.count }, 2_000)
        XCTAssertEqual(Set(entry.relations.map(\.id)).count, 2_000)
        XCTAssertEqual(entry.relationSections.map(\.kind), [.synonyms, .antonyms, .hypernyms, .hyponyms])
#if DEBUG
        let statementsAfterLoad = await repository.preparedStatementCountForTesting()
        XCTAssertEqual(statementsAfterLoad - statementsBeforeLoad, 6)
#endif
    }

    func testProgressiveRenderingPolicyEventuallyExposesEverything() {
        XCTAssertLessThan(WordDetailRenderingPolicy.initialSenseCount, 200)
        XCTAssertLessThan(WordDetailRenderingPolicy.initialExampleCount, 1_000)
        XCTAssertLessThan(WordDetailRenderingPolicy.initialRelationCount, 2_000)
        XCTAssertLessThan(WordDetailRenderingPolicy.initialFormCount, 500)

        let cases = [
            (WordDetailRenderingPolicy.initialSenseCount, WordDetailRenderingPolicy.senseBatchSize, 200),
            (WordDetailRenderingPolicy.initialExampleCount, WordDetailRenderingPolicy.exampleBatchSize, 1_000),
            (WordDetailRenderingPolicy.initialRelationCount, WordDetailRenderingPolicy.relationBatchSize, 2_000),
            (WordDetailRenderingPolicy.initialFormCount, WordDetailRenderingPolicy.formBatchSize, 500)
        ]
        for (initial, batch, total) in cases {
            var visible = initial
            while visible < total {
                visible = WordDetailRenderingPolicy.expandedCount(
                    current: visible,
                    total: total,
                    batchSize: batch
                )
            }
            XCTAssertEqual(visible, total)
        }
    }

    private func makeLargeEntryDatabase(at url: URL) throws {
        do {
            let database = try SQLiteConnection(url: url, readOnly: false)
            try database.execute(
                """
                CREATE TABLE entries (
                    id TEXT NOT NULL UNIQUE,
                    word TEXT NOT NULL,
                    normalized_word TEXT NOT NULL,
                    pos_title TEXT NOT NULL,
                    gender TEXT,
                    etymology TEXT
                )
                """
            )
            try database.execute(
                "CREATE TABLE pronunciations (id INTEGER PRIMARY KEY, entry_rowid INTEGER NOT NULL, ordinal INTEGER NOT NULL, ipa TEXT NOT NULL, region TEXT)"
            )
            try database.execute(
                "CREATE TABLE senses (id INTEGER PRIMARY KEY, entry_rowid INTEGER NOT NULL, ordinal INTEGER NOT NULL, definition TEXT NOT NULL, tags_json TEXT)"
            )
            try database.execute(
                "CREATE TABLE examples (id INTEGER PRIMARY KEY, sense_id INTEGER NOT NULL, ordinal INTEGER NOT NULL, text TEXT NOT NULL, source TEXT)"
            )
            try database.execute(
                "CREATE TABLE forms (id INTEGER PRIMARY KEY, entry_rowid INTEGER NOT NULL, ordinal INTEGER NOT NULL, form TEXT NOT NULL, normalized_form TEXT NOT NULL, tags_json TEXT)"
            )
            try database.execute(
                "CREATE TABLE relations (id INTEGER PRIMARY KEY, entry_rowid INTEGER NOT NULL, kind TEXT NOT NULL, word TEXT NOT NULL)"
            )
            try database.execute("CREATE TABLE digits (value INTEGER PRIMARY KEY)")
            for digit in 0 ..< 10 {
                try database.execute("INSERT INTO digits(value) VALUES (?)", bindings: [.integer(Int64(digit))])
            }
            try database.execute(
                "INSERT INTO entries(id, word, normalized_word, pos_title) VALUES ('large-entry', 'géant', 'geant', 'Nom commun')"
            )
            try database.execute(
                "INSERT INTO pronunciations(entry_rowid, ordinal, ipa) VALUES (1, 0, '/ʒe.ɑ̃/')"
            )
            try database.execute(
                """
                INSERT INTO senses(entry_rowid, ordinal, definition, tags_json)
                SELECT 1, n, 'Définition ' || n, '[]'
                  FROM (
                    SELECT a.value + 10 * b.value + 100 * c.value AS n
                      FROM digits a CROSS JOIN digits b CROSS JOIN digits c
                  )
                 WHERE n < 200
                 ORDER BY n
                """
            )
            try database.execute(
                """
                INSERT INTO examples(sense_id, ordinal, text, source)
                SELECT s.id, d.value, 'Exemple ' || s.ordinal || '-' || d.value, NULL
                  FROM senses s CROSS JOIN digits d
                 WHERE d.value < 5
                 ORDER BY s.ordinal, d.value
                """
            )
            try database.execute(
                """
                INSERT INTO forms(entry_rowid, ordinal, form, normalized_form, tags_json)
                SELECT 1, n, 'forme-' || n, 'forme-' || n, '[]'
                  FROM (
                    SELECT a.value + 10 * b.value + 100 * c.value AS n
                      FROM digits a CROSS JOIN digits b CROSS JOIN digits c
                  )
                 WHERE n < 500
                 ORDER BY n
                """
            )
            try database.execute(
                """
                INSERT INTO relations(entry_rowid, kind, word)
                SELECT 1,
                       CASE n % 4
                         WHEN 0 THEN 'synonyms'
                         WHEN 1 THEN 'antonyms'
                         WHEN 2 THEN 'hypernyms'
                         ELSE 'hyponyms'
                       END,
                       'relation-' || n
                  FROM (
                    SELECT a.value + 10 * b.value + 100 * c.value + 1000 * d.value AS n
                      FROM digits a CROSS JOIN digits b CROSS JOIN digits c CROSS JOIN digits d
                  )
                 WHERE n < 2000
                 ORDER BY n
                """
            )
            try database.execute("CREATE INDEX senses_entry_idx ON senses(entry_rowid, ordinal)")
            try database.execute("CREATE INDEX examples_sense_idx ON examples(sense_id, ordinal)")
            try database.execute("CREATE INDEX pronunciations_entry_idx ON pronunciations(entry_rowid, ordinal)")
            try database.execute("CREATE INDEX forms_entry_idx ON forms(entry_rowid, ordinal)")
            try database.execute("CREATE INDEX relations_entry_kind_idx ON relations(entry_rowid, kind)")
            try database.execute("PRAGMA wal_checkpoint(TRUNCATE)")
        }
    }
}
