import XCTest

/// Runs the shipping screens with real mouse/keyboard input. No app model imports or mocked views.
@MainActor
final class TalosFlows: XCTestCase {
    private var app: XCUIApplication!
    private var projectFixture: URL?

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["TALOS_UI_TEST_RUN"] = UUID().uuidString
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
    }

    override func tearDownWithError() throws {
        if let run = testRun, run.failureCount > 0 {
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.lifetime = .keepAlways
            add(screenshot)
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        app.terminate()
        if let projectFixture { try FileManager.default.removeItem(at: projectFixture) }
        if let id = app.launchEnvironment["TALOS_UI_TEST_RUN"] {
            UserDefaults().removePersistentDomain(forName: "com.thom1606.Talos.UITests.\(id)")
            let storage = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Talos/UITests/\(id)")
            if FileManager.default.fileExists(atPath: storage.path) {
                try FileManager.default.removeItem(at: storage)
            }
        }
    }

    func testOnboardingCompletesAndDoesNotReturnAfterRelaunch() {
        finishOnboarding(openSettings: false)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.windows["settings"].waitForExistence(timeout: 10))
        app.activate()
        XCTAssertFalse(app.buttons["onboarding.next"].exists)
        let wheel = app.descendants(matching: .any)["wheel.preview"].firstMatch
        XCTAssertEqual(wheel.buttons.count, 1)
        XCTAssertTrue(wheel.buttons["Settings"].exists)
    }

    func testSettingsNavigationAndSoundPreferencePersist() {
        finishOnboarding()
        navigate("Advanced")
        let sound = app.switches["settings.hoverSound"]
        XCTAssertTrue(sound.waitForExistence(timeout: 5))
        let original = String(describing: sound.value!)
        sound.click()
        XCTAssertNotEqual(String(describing: sound.value!), original)
        let changed = String(describing: sound.value!)
        navigate("Repositories")
        XCTAssertTrue(app.staticTexts["No repositories"].waitForExistence(timeout: 5))
        navigate("Wheel")
        XCTAssertTrue(app.staticTexts["Drag tiles onto the wheel to add them."].waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.windows["settings"].waitForExistence(timeout: 10))
        app.activate()
        navigate("Advanced")
        XCTAssertEqual(String(describing: app.switches["settings.hoverSound"].value!), changed)
    }

    func testGitHubFormValidationAndCancellation() {
        finishOnboarding()
        navigate("Repositories")
        app.menuButtons["Add repository"].click()
        app.menuItems["Add GitHub repository…"].click()
        let url = app.textFields["repository.url"]
        XCTAssertTrue(url.waitForExistence(timeout: 5))
        let add = app.buttons["Add"].firstMatch
        XCTAssertFalse(add.isEnabled)
        url.click()
        url.typeText("not-a-repository")
        XCTAssertFalse(add.isEnabled)
        replaceText(url, with: "https://github.com/example/tools")
        XCTAssertTrue(add.isEnabled)
        XCTAssertTrue(app.secureTextFields["repository.token"].exists)
        app.buttons["Cancel"].click()
        XCTAssertTrue(url.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No repositories"].exists)
        app.menuButtons["Add repository"].click()
        app.menuItems["Add GitHub repository…"].click()
        XCTAssertTrue(url.waitForExistence(timeout: 5))
        XCTAssertEqual(url.value as? String, "")
        app.buttons["Cancel"].click()
    }

    func testLocalProjectLinkPersistsAndRemovalRemovesTiles() throws {
        // A real, unbuilt extension project selected through the system folder picker.
        // This fixture is input data; it does not write to Talos storage.
        let project = FileManager.default.temporaryDirectory
            .appendingPathComponent("Talos-UI-Project-\(UUID().uuidString)", isDirectory: true)
        projectFixture = project
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try Data("""
        {
          "name": "UI Test Tools", "version": "1.0.0",
          "talos": { "bundleId": "com.talos.uitests.tools", "entry": "src/index.ts", "locales": {} },
          "commands": [{ "name": "inspect", "displayName": "Inspect Test File",
                         "icon": "doc.text", "supportedFileTypes": ["*"] }]
        }
        """.utf8).write(to: project.appendingPathComponent("package.json"))
        finishOnboarding()
        navigate("Repositories")
        app.menuButtons["Add repository"].click()
        app.menuItems["Link local project…"].click()
        let picker = app.sheets["open-panel"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        app.typeKey("g", modifierFlags: [.command, .shift])
        let path = app.sheets["GoToWindow"].textFields["PathTextField"]
        XCTAssertTrue(path.waitForExistence(timeout: 5))
        replaceText(path, with: project.path)
        app.typeKey(.return, modifierFlags: [])
        picker.buttons["Open"].click()
        XCTAssertTrue(app.staticTexts["UI Test Tools"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Build project to proceed"].exists)
        navigate("Wheel")
        let tile = app.descendants(matching: .any)["wheel.palette.com.talos.uitests.tools.inspect"].firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        XCTAssertTrue(tile.waitForExistence(timeout: 10))
        navigate("Repositories")
        XCTAssertTrue(app.staticTexts["UI Test Tools"].exists)
        app.menuButtons["Repository actions"].click()
        app.menuItems["Remove"].click()
        XCTAssertTrue(app.staticTexts["No repositories"].waitForExistence(timeout: 5))
        navigate("Wheel")
        XCTAssertFalse(tile.exists)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.windows["settings"].waitForExistence(timeout: 10))
        navigate("Repositories")
        XCTAssertTrue(app.staticTexts["No repositories"].waitForExistence(timeout: 5))
    }

    func testDragFolderOntoWheelRenameAndPersist() {
        finishOnboarding()
        let source = app.descendants(matching: .any)["wheel.palette.folder"].firstMatch
        let wheel = app.descendants(matching: .any)["wheel.preview"].firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        XCTAssertTrue(wheel.exists)
        XCTAssertFalse(app.buttons["Folder"].exists)
        // Coordinates are relative to the actual accessibility frames, not screen pixels.
        // Drop on the visible ring above the center of the wheel.
        let destination = wheel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .withOffset(CGVector(dx: 0, dy: -90))
        source.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .click(forDuration: 0.1, thenDragTo: destination, withVelocity: .slow, thenHoldForDuration: 0.1)
        let folder = app.buttons["Folder"].firstMatch
        XCTAssertTrue(folder.waitForExistence(timeout: 5), "Dragging from the palette must add a real wheel entry")
        XCTAssertEqual(app.buttons.matching(identifier: "Folder").count, 1)
        folder.click()
        let name = app.textFields["wheel.entry.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        replaceText(name, with: "Work tools")
        app.buttons["Save"].click()
        XCTAssertTrue(app.buttons["Work tools"].waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["Work tools"].waitForExistence(timeout: 10))
        focusSettings()
        app.buttons["Work tools"].click()
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "Work tools")
        replaceText(name, with: "Discard this")
        app.buttons["Cancel"].click()
        XCTAssertTrue(app.buttons["Work tools"].exists)
        XCTAssertFalse(app.buttons["Discard this"].exists)
    }

    private func finishOnboarding(openSettings: Bool = true) {
        let next = app.buttons["onboarding.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        next.click()
        XCTAssertTrue(app.staticTexts["Set up your experience"].waitForExistence(timeout: 5))
        app.buttons["Next"].click()
        let finish = app.buttons["onboarding.finish"]
        XCTAssertTrue(finish.waitForExistence(timeout: 5))
        finish.click()
        XCTAssertTrue(finish.waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.windows["settings"].exists)
        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        XCTAssertTrue(finder.wait(for: .runningForeground, timeout: 5))
        XCTAssertTrue(finder.windows.firstMatch.waitForExistence(timeout: 5))
        guard openSettings else { return }
        app.activate()
        app.typeKey(",", modifierFlags: .command)
        focusSettings()
    }

    private func focusSettings() {
        XCTAssertTrue(app.windows["settings"].waitForExistence(timeout: 10))
        app.activate()
        // A menu-bar app can still be behind Finder after onboarding or relaunch.
        // Focus its titlebar before starting gestures that require the first mouse event.
        app.windows["settings"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.04)).click()
    }

    private func navigate(_ name: String) {
        app.activate()
        app.outlines.staticTexts[name].click()
    }

    private func replaceText(_ field: XCUIElement, with value: String) {
        field.click()
        field.typeKey("a", modifierFlags: .command)
        field.typeText(value)
    }
}
