import XCTest

final class PetHealthUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {}

    @MainActor
    func testCanAddPetAndSeeItInProfilesAndHome() throws {
        let app = XCUIApplication()
        app.launchArguments += ["UI_TESTING", "RESET_SELECTED_PET"]
        app.launch()

        app.tabBars.buttons["Pets"].tap()

        app.buttons["add-pet-button"].tap()

        let nameField = app.textFields["add-pet-name-field"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("Mochi")

        let saveButton = app.buttons["save-pet-button"]
        XCTAssertTrue(saveButton.isEnabled)
        saveButton.tap()

        XCTAssertTrue(app.staticTexts["Mochi"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Home"].tap()
        XCTAssertTrue(app.staticTexts["Mochi"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            let app = XCUIApplication()
            app.launchArguments += ["UI_TESTING", "RESET_SELECTED_PET"]
            app.launch()
        }
    }
}
