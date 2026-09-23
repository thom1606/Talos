import XCTest
import AppKit
import AVFoundation

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
        app.activate()
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
        XCTAssertEqual(wheel.buttons.count, 5)
        for title in ["Crop", "Archive", "Compress", "Convert", "Settings"] { XCTAssertTrue(wheel.buttons[title].exists) }
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
                         "icon": "doc.text", "supportedFileTypes": ["*"],
                         "settings": [
                           { "name": "server", "displayName": "Server", "type": "text", "required": true },
                           { "name": "password", "displayName": "Password", "type": "password", "required": true },
                           { "name": "expiry", "displayName": "Expire after", "section": "Link expiration",
                             "type": "select", "options": ["Never", "7 days", "30 days"] }
                         ] }]
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
        let wheel = app.descendants(matching: .any)["wheel.preview"].firstMatch
        let destination = wheel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .withOffset(CGVector(dx: 0, dy: -90))
        tile.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .click(forDuration: 0.1, thenDragTo: destination, withVelocity: .slow, thenHoldForDuration: 0.1)
        let action = app.buttons["Inspect Test File"].firstMatch
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        action.click()
        let server = app.textFields["wheel.entry.setting.server"]
        let password = app.secureTextFields["wheel.entry.setting.password"]
        XCTAssertTrue(server.waitForExistence(timeout: 5))
        XCTAssertTrue(password.exists)
        XCTAssertTrue(app.staticTexts["Link expiration"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["wheel.entry.setting.expiry"].firstMatch.exists)
        let title = app.staticTexts["Edit Action"].firstMatch
        XCTAssertTrue(title.exists)
        XCTAssertLessThan(abs(title.frame.minX - app.staticTexts["Name"].firstMatch.frame.minX), 50)
        app.buttons["Cancel"].click()
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

    func testBuiltInCropExportsSelectedDimensions() throws {
        let directory = try mediaFixture("crop")
        finishOnboarding(openSettings: false)
        dropOnWheel(file: directory.appendingPathComponent("sample.png"), offset: CGVector(dx: 0, dy: -105))
        let window = app.windows["Crop"]
        XCTAssertTrue(window.waitForExistence(timeout: 15), "A single Finder drop must open Crop")
        let width = window.textFields["Width"]
        XCTAssertTrue(width.waitForExistence(timeout: 15))
        replaceText(width, with: "160")
        width.typeKey(.tab, modifierFlags: [])
        let height = window.textFields["Height"]
        replaceText(height, with: "120")
        height.typeKey(.tab, modifierFlags: [])
        let input = directory.appendingPathComponent("sample.png")
        let original = try Data(contentsOf: input)
        window.buttons["Apply"].click()
        let output = directory.appendingPathComponent("sample-cropped.png")
        waitForFile(output)
        XCTAssertFalse(window.sheets.firstMatch.exists)
        let result = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: output)))
        XCTAssertEqual(result.pixelsWide, 160)
        XCTAssertEqual(result.pixelsHigh, 120)
        window.buttons["Apply"].click()
        let second = directory.appendingPathComponent("sample-cropped-2.png")
        waitForFile(second)
        XCTAssertEqual(try Data(contentsOf: output), try Data(contentsOf: second))
        XCTAssertEqual(try Data(contentsOf: input), original)
    }

    func testBuiltInConvertUsesWheelSubmenu() throws {
        let directory = try mediaFixture("convert")
        finishOnboarding(openSettings: false)
        // Hover Convert to enter its submenu, then release over TIFF in the child wheel.
        dropOnWheel(file: directory.appendingPathComponent("sample.png"), offset: CGVector(dx: -60, dy: 85))
        let output = directory.appendingPathComponent("sample-converted.tiff")
        waitForFile(output)
        XCTAssertFalse(app.windows["Convert"].exists)
        let result = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: output)))
        XCTAssertEqual(result.pixelsWide, 320)
        XCTAssertEqual(result.pixelsHigh, 240)
    }

    func testBuiltInCompressionPreservesPixels() throws {
        let directory = try mediaFixture("compress")
        finishOnboarding(openSettings: false)
        let input = directory.appendingPathComponent("sample.png")
        dropOnWheel(file: input, offset: CGVector(dx: 62, dy: 85))
        let output = directory.appendingPathComponent("sample-compressed.png")
        waitForFile(output)
        let originalData = try Data(contentsOf: input), outputData = try Data(contentsOf: output)
        XCTAssertLessThan(outputData.count, originalData.count)
        let original = try XCTUnwrap(NSBitmapImageRep(data: originalData))
        let compressed = try XCTUnwrap(NSBitmapImageRep(data: outputData))
        XCTAssertEqual(compressed.pixelsWide, original.pixelsWide)
        XCTAssertEqual(compressed.pixelsHigh, original.pixelsHigh)
        for y in 0..<original.pixelsHigh {
            for x in 0..<original.pixelsWide { XCTAssertEqual(original.colorAt(x: x, y: y), compressed.colorAt(x: x, y: y)) }
        }
    }

    func testBuiltInVideoCropPreviewsAndExports() async throws {
        let directory = try mediaFixture("video")
        let input = directory.appendingPathComponent("sample.mp4")
        finishOnboarding(openSettings: false)
        dropOnWheel(file: input, offset: CGVector(dx: 0, dy: -105))
        let window = app.windows["Crop"]
        XCTAssertTrue(window.waitForExistence(timeout: 15))
        let preview = window.buttons["Play / pause preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 15), "Local video metadata must load without copying all bytes through JSON")
        preview.click()
        let width = window.textFields["Width"], height = window.textFields["Height"]
        replaceText(width, with: "160"); width.typeKey(.tab, modifierFlags: [])
        replaceText(height, with: "120"); height.typeKey(.tab, modifierFlags: [])
        window.buttons["Apply"].click()
        let output = directory.appendingPathComponent("sample-cropped.mp4")
        let exists = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in FileManager.default.fileExists(atPath: output.path) }, object: nil)
        await fulfillment(of: [exists], timeout: 30)
        let tracks = try await AVURLAsset(url: output).loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let size = try await track.load(.naturalSize)
        XCTAssertEqual(size.width, 160); XCTAssertEqual(size.height, 120)
        XCTAssertTrue(FileManager.default.fileExists(atPath: input.path))
    }

    func testBuiltInArchiveIncludesEntireSelection() throws {
        let directory = try mediaFixture("archive")
        finishOnboarding(openSettings: false)
        // Mixed image/text selection leaves Archive and Settings: Archive is the top segment.
        dropOnWheel(file: directory.appendingPathComponent("sample.png"), offset: CGVector(dx: 0, dy: -105), includingFile: "notes.txt")
        let output = directory.appendingPathComponent("Archive.zip")
        waitForFile(output)
        for name in ["sample.png", "notes.txt"] {
            let process = Process(), pipe = Pipe()
            process.executableURL = URL(filePath: "/usr/bin/unzip")
            process.arguments = ["-p", output.path, name]
            process.standardOutput = pipe
            try process.run()
            let archived = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0)
            XCTAssertEqual(archived, try Data(contentsOf: directory.appendingPathComponent(name)))
        }
    }

    private func mediaFixture(_ name: String) throws -> URL {
        let directory = Bundle.main.bundleURL.deletingLastPathComponent()
            .appendingPathComponent("TalosUITestFixtures/\(name)", isDirectory: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("sample.png").path))
        return directory
    }

    private func waitForFile(_ url: URL) {
        let exists = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in FileManager.default.fileExists(atPath: url.path) }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [exists], timeout: 20), .completed, "Missing output: \(url.lastPathComponent)")
    }

    private func dropOnWheel(file: URL, offset: CGVector, includingFile: String? = nil) {
        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        finder.activate()
        finder.typeKey("g", modifierFlags: [.command, .shift])
        let path = finder.sheets["GoToWindow"].textFields["PathTextField"]
        XCTAssertTrue(path.waitForExistence(timeout: 5))
        replaceText(path, with: file.deletingLastPathComponent().path)
        finder.typeKey(.return, modifierFlags: [])
        finder.typeKey("1", modifierFlags: .command)
        let source = finder.windows.firstMatch.images[file.lastPathComponent].firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        // Start unselected: Shift-clicking an already selected Finder icon deselects it.
        finder.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.8)).click()
        if let includingFile { finder.windows.firstMatch.images[includingFile].firstMatch.click() }
        let point = source.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        XCUIElement.perform(withKeyModifiers: .shift) {
            point.click(forDuration: 0.2, thenDragTo: point.withOffset(offset), withVelocity: XCUIGestureVelocity(rawValue: 40), thenHoldForDuration: 1.2)
        }
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
