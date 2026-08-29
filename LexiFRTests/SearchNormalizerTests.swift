import XCTest
@testable import LexiFR

final class SearchNormalizerTests: XCTestCase {
    func testAccentsCaseWhitespaceAndLigatures() {
        XCTAssertEqual(SearchNormalizer.normalize("  ÉCOLE  "), "ecole")
        XCTAssertEqual(SearchNormalizer.normalize("CŒUR"), "coeur")
        XCTAssertEqual(SearchNormalizer.normalize("L’ÉCOLE"), "l'ecole")
        XCTAssertEqual(SearchNormalizer.normalize("l`école"), "l'ecole")
    }

    func testGoogleImagesURL() throws {
        let url = try XCTUnwrap(GoogleImagesService.url(for: "cœur & âme"))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "www.google.com")
        let queryItems: [String: String] = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })
        XCTAssertEqual(queryItems["q"], "cœur & âme")
    }
}
