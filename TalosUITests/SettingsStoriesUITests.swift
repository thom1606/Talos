//
//  SettingsStoriesUITests.swift
//  TalosUITests
//
//  The Settings journey as a user sees it. Every run has a disposable
//  preferences and storage location, so it never reads or writes the
//  developer's installed modules, App Group data, or preferences.
//

import XCTest

final class SettingsStoriesUITests: XCTestCase {
    private var testRoot: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        testRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("TalosUITests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: testRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: testRoot)
    }

    private func launch(skipOnboarding: Bool = false) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.thom1606.Talos.Settings")
        app.launchEnvironment = [
            "TALOS_TEST_ROOT": testRoot.path,
            "TALOS_TEST_SUITE": UUID().uuidString,
            "TALOS_SKIP_ONBOARDING": skipOnboarding ? "1" : "0",
        ]
        app.launchArguments = ["-AppleLanguages", "(en)"]
        app.launch()
        return app
    }

    /// Restrict identifier lookup to app windows, avoiding duplicate system
    /// controls (for example, Touch Bar mirrors) on the test Mac.
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.windows.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    func testSettingsJourneyShowsRepositoriesWheelAndPreferences() {
        let app = launch(skipOnboarding: true)

        let repositories = element(app, "settings.page.repositories")
        XCTAssertTrue(repositories.waitForExistence(timeout: 10), "The Settings sidebar did not appear")
        repositories.click()
        XCTAssertTrue(element(app, "repositories.add").waitForExistence(timeout: 5),
                      "The repository page did not offer a way to add an action source")

        let wheel = element(app, "settings.page.wheel")
        wheel.click()
        XCTAssertTrue(element(app, "wheel.preview").waitForExistence(timeout: 5),
                      "The wheel editor did not load")
        XCTAssertTrue(element(app, "wheel.palette.builtin.settings").waitForExistence(timeout: 5),
                      "The wheel palette did not include the built-in Settings action")

        let advanced = element(app, "settings.page.advanced")
        advanced.click()
        let automaticUpdates = element(app, "advanced.automaticUpdates")
        XCTAssertTrue(automaticUpdates.waitForExistence(timeout: 5),
                      "The Advanced page did not show update preferences")
        XCTAssertTrue(element(app, "advanced.hoverSound").exists)
        XCTAssertTrue(element(app, "advanced.checkForUpdates").exists)
    }

    func testFirstRunReachesFinderInstructions() {
        let app = launch()

        let next = element(app, "onboarding.next")
        XCTAssertTrue(next.waitForExistence(timeout: 10), "The first onboarding page did not appear")
        XCTAssertTrue(app.staticTexts["Welcome to Talos"].exists)
        next.click()

        XCTAssertTrue(app.staticTexts["Set up your experience"].waitForExistence(timeout: 5),
                      "The experience page did not appear")
        XCTAssertTrue(element(app, "onboarding.notifications").exists)
        next.click()

        let finish = element(app, "onboarding.finish")
        XCTAssertTrue(finish.waitForExistence(timeout: 5), "The final onboarding page did not appear")
        XCTAssertTrue(app.staticTexts["It’s ready in Finder"].exists)
    }
}
