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
}
