import XCTest

final class LexiFRUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunchSearchAndOpenWord() {
        let app = XCUIApplication()
        app.launch()
        let search = app.textFields["Rechercher un mot…"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("ecole")
        XCTAssertTrue(app.staticTexts["école"].waitForExistence(timeout: 3))
        app.staticTexts["école"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["école"].waitForExistence(timeout: 3))
        let favorite = app.buttons["Ajouter aux favoris"]
        XCTAssertTrue(favorite.waitForExistence(timeout: 3))
        favorite.tap()
        XCTAssertTrue(app.buttons["Retirer des favoris"].waitForExistence(timeout: 3))
    }

    func testCreateCollection() {
        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["Collections"].tap()
        app.buttons["Créer une collection"].tap()
        let field = app.textFields["Nom"]
        field.typeText("Lecture")
        app.buttons["Enregistrer"].tap()
        XCTAssertTrue(app.staticTexts["Lecture"].waitForExistence(timeout: 3))
    }
}
