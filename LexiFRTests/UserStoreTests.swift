import XCTest
@testable import LexiFR

final class UserStoreTests: XCTestCase {
    private var directory: URL!
    private var databaseURL: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        databaseURL = directory.appendingPathComponent("user.sqlite")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testFavoritesSortAndPersistence() async throws {
        let store = try UserStore(databaseURL: databaseURL)
        let school = WordSummary(id: "stable-school", word: "école", partOfSpeech: "Nom commun")
        let summer = WordSummary(id: "stable-summer", word: "été", partOfSpeech: "Nom commun")
        let addedSummer = try await store.toggleFavorite(summer)
        XCTAssertTrue(addedSummer)
        try await Task.sleep(for: .milliseconds(10))
        let addedSchool = try await store.toggleFavorite(school)
        XCTAssertTrue(addedSchool)
        let ascending = try await store.favorites(sort: .alphabeticalAscending)
        let descending = try await store.favorites(sort: .alphabeticalDescending)
        let newest = try await store.favorites(sort: .newest)
        let oldest = try await store.favorites(sort: .oldest)
        XCTAssertEqual(ascending.map(\.word), ["école", "été"])
        XCTAssertEqual(descending.map(\.word), ["été", "école"])
        XCTAssertEqual(newest.first?.id, school.id)
        XCTAssertEqual(oldest.first?.id, summer.id)

        let reopened = try UserStore(databaseURL: databaseURL)
        let persisted = try await reopened.isFavorite("stable-school")
        XCTAssertTrue(persisted)
    }

    func testCollectionsMultipleAssociationAndDates() async throws {
        let store = try UserStore(databaseURL: databaseURL)
        let word = WordSummary(id: "stable-word", word: "cœur", partOfSpeech: "Nom commun")
        let first = try await store.createCollection(name: "Lecture")
        let second = try await store.createCollection(name: "À apprendre")
        try await store.setWord(word, in: first.id, included: true)
        try await store.setWord(word, in: second.id, included: true)
        let inFirst = try await store.collectionContains(collectionID: first.id, wordID: word.id)
        let inSecond = try await store.collectionContains(collectionID: second.id, wordID: word.id)
        let firstWords = try await store.words(in: first.id, sort: .newest)
        XCTAssertTrue(inFirst)
        XCTAssertTrue(inSecond)
        XCTAssertEqual(firstWords.first?.id, word.id)
        try await store.setWord(word, in: first.id, included: false)
        let removedFromFirst = try await store.collectionContains(collectionID: first.id, wordID: word.id)
        let keptInSecond = try await store.collectionContains(collectionID: second.id, wordID: word.id)
        XCTAssertFalse(removedFromFirst)
        XCTAssertTrue(keptInSecond)
        let memberships = try await store.collectionMemberships(for: word.id)
        XCTAssertEqual(memberships, [second.id])
    }
}
