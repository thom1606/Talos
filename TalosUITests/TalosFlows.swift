import XCTest
import AppKit
import AVFoundation

/// Runs the shipping screens with real mouse/keyboard input. No app model imports or mocked views.
@MainActor
final class TalosFlows: XCTestCase {
    private var app: XCUIApplication!
    private var projectFixture: URL?
    private var dragLog: URL?

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // A production instance can otherwise intercept the same Shift-drag.
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.thom1606.Talos")
        for bundleURL in Set(runningApps.compactMap(\.bundleURL)) {
            XCUIApplication(url: bundleURL).terminate()
        }
        let stopped = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.thom1606.Talos")
                .allSatisfy(\.isTerminated)
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [stopped], timeout: 5), .completed,
                       "Close every running Talos instance before launching the test app")
        app.launchEnvironment["TALOS_UI_TEST_RUN"] = UUID().uuidString
        // Onboarding opens real Finder, using the test files instead of the user's Downloads.
        app.launchEnvironment["TALOS_UI_TEST_FINDER_DIRECTORY"] = try mediaFixture("crop").path
        // Gesture coordinates belong to this fixture, independent of the shipping defaults.
        let firstAction = name.contains("Redact") ? "talos-actions.redact" : "talos-actions.crop"
        let actions = name.contains("AudioWaveformExports") || name.contains("WebPExports") || name.contains("ArchiveExports") ? ["talos-actions.convert"] :
            [firstAction, "talos-actions.archive", "talos-actions.organize",
             "talos-actions.compress", "talos-actions.convert", "talos.system.settings"]
        let wheel = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1,
            "items": actions.map { ["id": UUID().uuidString, "actionID": $0] }
        ])
        app.launchEnvironment["TALOS_UI_TEST_WHEEL"] = wheel.base64EncodedString()
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("TalosDrag-\(UUID().uuidString).log")
        try Data().write(to: log)
        dragLog = log
        app.launchEnvironment["TALOS_UI_TEST_DRAG_LOG"] = log.path
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
            if let dragLog, let contents = try? String(contentsOf: dragLog, encoding: .utf8) {
                let trace = XCTAttachment(string: contents)
                trace.name = "Native drag callbacks"
                trace.lifetime = .keepAlways
                add(trace)
            }
        }
        app.terminate()
        if let dragLog { try FileManager.default.removeItem(at: dragLog) }
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

    func testOnboardingAndSettingsPersistAfterRelaunch() {
        finishOnboarding()
        let wheel = app.descendants(matching: .any)["wheel.preview"].firstMatch
        let defaultActions = ["Crop", "Archive", "Organize", "Compress", "Convert", "Settings"]
        XCTAssertEqual(wheel.buttons.count, defaultActions.count)
        for title in defaultActions { XCTAssertTrue(wheel.buttons[title].exists) }
        navigate("Advanced")
        let sound = app.switches["settings.hoverSound"]
        XCTAssertTrue(sound.waitForExistence(timeout: 5))
        let original = String(describing: sound.value!)
        sound.click()
        let changed = String(describing: sound.value!)
        XCTAssertNotEqual(changed, original)
        app.terminate()
        app.launch()
        showSettingsWindow()
        XCTAssertFalse(app.buttons["onboarding.next"].exists)
        navigate("Advanced")
        XCTAssertEqual(String(describing: app.switches["settings.hoverSound"].value!), changed)
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
        app.buttons["Cancel"].click()
        app.terminate()
        app.launch()
        showSettingsWindow()
        navigate("Wheel")
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
        showSettingsWindow()
        navigate("Repositories")
        XCTAssertTrue(app.staticTexts["No repositories"].waitForExistence(timeout: 5))
    }

    func testPackageImportReplacesBuiltInPersistsAndRestoresOnRemoval() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Talos-Import-\(UUID())")
        projectFixture = root
        let source = root.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let archive = root.appendingPathComponent("test.talos")
        func package(version: String, title: String) throws {
            try Data("""
            {"name":"Imported Test Tools","version":"\(version)",
             "talos":{"bundleId":"talos-actions","entry":"index.mjs","locales":{"en":"en.json"}},
             "commands":[{"name":"crop","displayName":"\(title)","icon":"crop","supportedFileTypes":["*"]}]}
            """.utf8).write(to: source.appendingPathComponent("package.json"))
            try Data("export async function activate() {}".utf8).write(to: source.appendingPathComponent("index.mjs"))
            try Data("{}".utf8).write(to: source.appendingPathComponent("en.json"))
            if FileManager.default.fileExists(atPath: archive.path) { try FileManager.default.removeItem(at: archive) }
            let process = Process()
            process.executableURL = URL(filePath: "/usr/bin/ditto")
            process.arguments = ["-c", "-k", "--norsrc", "--noextattr", source.path, archive.path]
            try process.run()
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0)
        }
        try package(version: "1.0.0", title: "Imported Crop")
        finishOnboarding()
        navigate("Repositories")
        importPackage(archive)
        XCTAssertTrue(app.staticTexts["Imported Test Tools"].waitForExistence(timeout: 15))
        navigate("Wheel")
        let wheel = app.descendants(matching: .any)["wheel.preview"].firstMatch
        XCTAssertTrue(wheel.buttons["Imported Crop"].waitForExistence(timeout: 10))
        app.terminate()
        app.launch()
        showSettingsWindow()
        navigate("Wheel")
        XCTAssertTrue(wheel.buttons["Imported Crop"].waitForExistence(timeout: 10))
        navigate("Repositories")
        try package(version: "2.0.0", title: "Updated Crop")
        importPackage(archive)
        XCTAssertTrue(app.staticTexts["2.0.0"].waitForExistence(timeout: 10))
        navigate("Wheel")
        XCTAssertTrue(wheel.buttons["Updated Crop"].waitForExistence(timeout: 10))
        navigate("Repositories")
        // A failed replacement must leave the working package installed.
        try Data("not a zip".utf8).write(to: archive)
        importPackage(archive)
        XCTAssertTrue(app.staticTexts["The Talos package is invalid or unsafe."].waitForExistence(timeout: 10))
        app.windows["settings"].sheets.buttons["OK"].click()
        XCTAssertTrue(app.windows["settings"].sheets.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["2.0.0"].exists)
        // macOS restores this menu as "More" after dismissing a sheet. Its image identifier is stable.
        let actions = app.windows["settings"].menuButtons["ellipsis"]
        XCTAssertTrue(actions.waitForExistence(timeout: 5))
        actions.click()
        app.menuItems["Remove"].click()
        XCTAssertTrue(app.staticTexts["No repositories"].waitForExistence(timeout: 10))
        navigate("Wheel")
        XCTAssertTrue(wheel.buttons["Crop"].waitForExistence(timeout: 10))
        XCTAssertFalse(wheel.buttons["Updated Crop"].exists)
    }

    private func importPackage(_ url: URL) {
        app.menuButtons["Add repository"].click()
        app.menuItems["Import .talos…"].click()
        let picker = app.sheets["open-panel"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        app.typeKey("g", modifierFlags: [.command, .shift])
        let path = app.sheets["GoToWindow"].textFields["PathTextField"]
        XCTAssertTrue(path.waitForExistence(timeout: 5))
        replaceText(path, with: url.path)
        app.typeKey(.return, modifierFlags: [])
        picker.buttons["Open"].click()
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
        showSettingsWindow()
        XCTAssertTrue(app.buttons["Work tools"].waitForExistence(timeout: 10))
        app.buttons["Work tools"].click()
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "Work tools")
        replaceText(name, with: "Discard this")
        app.buttons["Cancel"].click()
        XCTAssertTrue(app.buttons["Work tools"].exists)
        XCTAssertFalse(app.buttons["Discard this"].exists)
    }

    func testEmptySecondaryWheelDoesNotShowOrAcceptDrop() throws {
        finishOnboarding(openSettings: false)
        let directory = try mediaFixture("crop")
        dropOnWheel(file: directory.appendingPathComponent("sample.png"), offset: CGVector(dx: 0, dy: -105),
                    modifiers: [.shift, .option]) {
            XCTAssertFalse(app.windows["Crop"].waitForExistence(timeout: 1),
                           "An empty secondary must not run the primary action")
        }
        let trace = try String(contentsOf: XCTUnwrap(dragLog), encoding: .utf8)
        XCTAssertFalse(trace.contains("show wheel=secondary"), "An empty secondary must not present a live wheel")
        dropOnWheel(file: directory.appendingPathComponent("sample.png"), offset: CGVector(dx: 0, dy: -105)) {
            XCTAssertTrue(app.windows["Crop"].waitForExistence(timeout: 10),
                          "The primary wheel must remain available after Option is released")
        }
    }

    func testSecondaryWheelPersistsSeparatelyAndAcceptsOptionDrop() throws {
        finishOnboarding()
        let wheel = app.descendants(matching: .any)["wheel.preview"].firstMatch
        let selector = app.descendants(matching: .any)["wheel.selector"].firstMatch
        let primary = selector.descendants(matching: .any)["Primary"].firstMatch
        let secondary = selector.descendants(matching: .any)["Secondary"].firstMatch
        XCTAssertTrue(secondary.waitForExistence(timeout: 5))
        secondary.click()
        XCTAssertEqual(wheel.buttons.count, 0)
        XCTAssertTrue(app.staticTexts["Drag actions onto this wheel"].exists)

        let archive = app.descendants(matching: .any)["wheel.palette.talos-actions.archive"].firstMatch
        let destination = wheel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .withOffset(CGVector(dx: 0, dy: -90))
        archive.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .click(forDuration: 0.1, thenDragTo: destination, withVelocity: .slow, thenHoldForDuration: 0.1)
        XCTAssertTrue(wheel.buttons["Archive"].waitForExistence(timeout: 5))
        destination.click()
        let name = app.textFields["wheel.entry.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        replaceText(name, with: "Extra archive")
        app.buttons["Save"].click()
        XCTAssertTrue(wheel.buttons["Extra archive"].waitForExistence(timeout: 5))
        primary.click()
        XCTAssertEqual(wheel.buttons.count, 6)
        XCTAssertTrue(wheel.buttons["Archive"].exists)
        XCTAssertFalse(wheel.buttons["Extra archive"].exists)

        app.terminate()
        app.launch()
        showSettingsWindow()
        navigate("Wheel")
        XCTAssertTrue(primary.waitForExistence(timeout: 5))
        XCTAssertEqual(wheel.buttons.count, 6)
        secondary.click()
        XCTAssertTrue(wheel.buttons["Extra archive"].waitForExistence(timeout: 5))
        XCTAssertEqual(wheel.buttons.count, 1)
        let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        screenshot.name = "Secondary wheel configuration"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        app.typeKey("w", modifierFlags: .command)
        let directory = try mediaFixture("crop")
        let output = directory.appendingPathComponent("Archive.zip")
        try? FileManager.default.removeItem(at: output)
        dropOnWheel(file: directory.appendingPathComponent("sample.png"), offset: CGVector(dx: 0, dy: -105),
                    modifiers: [.shift, .option]) {
            waitForFile(output)
        }
        XCTAssertFalse(app.windows["Crop"].exists, "Shift + Option must select the secondary action instead of primary Crop")
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("sample.png").path))
    }

    func testBackRemainsAtBottomWhileFolderContentsChange() {
        finishOnboarding()
        let wheel = app.descendants(matching: .any)["wheel.preview"].firstMatch
        let center = wheel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let destination = center.withOffset(CGVector(dx: 0, dy: -90))
        let folderSource = app.descendants(matching: .any)["wheel.palette.folder"].firstMatch
        folderSource.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .click(forDuration: 0.1, thenDragTo: destination, withVelocity: .slow, thenHoldForDuration: 0.1)
        let folder = wheel.buttons["Folder"]
        XCTAssertTrue(folder.waitForExistence(timeout: 5))
        let folderPoint = folder.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        folderPoint.click(forDuration: 0.7, thenDragTo: folderPoint, withVelocity: .slow, thenHoldForDuration: 0.1)

        let back = wheel.buttons["Back to parent folder"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        center.click()
        XCTAssertTrue(back.exists, "The center must remain a neutral place to read the wheel")

        for (index, action) in ["crop", "archive", "organize", "compress", "convert"].enumerated() {
            let source = app.descendants(matching: .any)["wheel.palette.talos-actions.\(action)"].firstMatch
            XCTAssertTrue(source.exists)
            source.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .click(forDuration: 0.1, thenDragTo: destination, withVelocity: .slow, thenHoldForDuration: 0.1)
            XCTAssertEqual(wheel.buttons.count, index + 2, "Adding an action must preserve the dedicated Back option")
            center.click()
            XCTAssertTrue(back.exists)
            if index == 0 || index == 4 {
                let screenshot = XCTAttachment(screenshot: app.screenshot())
                screenshot.name = "Folder with \(index + 1) actions and fixed Back"
                screenshot.lifetime = .keepAlways
                add(screenshot)
            }
        }

        center.withOffset(CGVector(dx: 0, dy: 102)).click()
        XCTAssertTrue(folder.waitForExistence(timeout: 5), "Back must work at the same bottom position with five actions")
        XCTAssertFalse(back.exists)
    }

    func testQuittingExtensionWindowKeepsTalosRunning() throws {
        let directory = try mediaFixture("crop")
        finishOnboarding(openSettings: false)
        let window = app.windows["Crop"]
        dropOnWheel(file: directory.appendingPathComponent("sample.png"), offset: CGVector(dx: 0, dy: -75)) {
            XCTAssertTrue(window.waitForExistence(timeout: 15))
        }
        app.activate()
        window.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(window.waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5), "Closing extension windows must keep the Talos agent running")
        showSettingsWindow()
        XCTAssertTrue(app.windows["settings"].exists)
    }

    func testBuiltInCropExportsSelectedDimensions() throws {
        let directory = try mediaFixture("crop")
        finishOnboarding(openSettings: false)
        let window = app.windows["Crop"]
        dropOnWheel(file: directory.appendingPathComponent("sample.png"), offset: CGVector(dx: 0, dy: -105)) {
            XCTAssertTrue(window.waitForExistence(timeout: 15), "A single Finder drop must open Crop")
        }
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
        // The output can appear before the window finishes closing.
        XCTAssertTrue(window.waitForNonExistence(timeout: 10))
        let firstExport = try Data(contentsOf: output)
        // Drop the original again to verify collision-safe naming.
        dropOnWheel(file: input, offset: CGVector(dx: 0, dy: -105)) {
            XCTAssertTrue(window.waitForExistence(timeout: 15))
        }
        XCTAssertTrue(width.waitForExistence(timeout: 15))
        replaceText(width, with: "160")
        width.typeKey(.tab, modifierFlags: [])
        replaceText(height, with: "120")
        height.typeKey(.tab, modifierFlags: [])
        window.buttons["Apply"].click()
        let second = directory.appendingPathComponent("sample-cropped-2.png")
        waitForFile(second)
        XCTAssertEqual(try Data(contentsOf: output), firstExport, "The first export must not be replaced")
        let secondImage = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: second)))
        XCTAssertEqual(secondImage.pixelsWide, 160)
        XCTAssertEqual(secondImage.pixelsHigh, 120)
        XCTAssertEqual(try Data(contentsOf: input), original)
    }

    func testBuiltInConvertUsesWheelSubmenu() throws {
        let directory = try mediaFixture("convert")
        finishOnboarding(openSettings: false)
        // The left edge of Convert overlaps PNG in its submenu, outside the fixed Back segment.
        let output = directory.appendingPathComponent("sample-converted.png")
        dropOnWheel(file: directory.appendingPathComponent("sample.png"), offset: CGVector(dx: -100, dy: 25)) {
            waitForFile(output)
        }
        XCTAssertFalse(app.windows["Convert"].exists)
        let result = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: output)))
        XCTAssertEqual(result.pixelsWide, 320)
        XCTAssertEqual(result.pixelsHigh, 240)
    }

    func testBuiltInConvertAudioWaveformExports() throws {
        let directory = try mediaFixture("convertAudio")
        let input = directory.appendingPathComponent("sample.wav")
        let original = try Data(contentsOf: input)
        finishOnboarding(openSettings: false)
        // One root Convert action lets a continuous Finder drag dwell on either submenu item.
        for (format, offset) in [("png", CGVector(dx: -100, dy: 25)),
                                 ("svg", CGVector(dx: -85, dy: -53))] {
            let output = directory.appendingPathComponent("sample-converted.\(format)")
            dropOnWheel(file: input, offset: offset) { waitForFile(output) }
            XCTAssertFalse(app.windows["Convert"].exists)
            if format == "png" {
                let image = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: output)))
                XCTAssertEqual(image.pixelsWide, 1600)
                XCTAssertEqual(image.pixelsHigh, 400)
                XCTAssertTrue(image.hasAlpha)
                let background = try XCTUnwrap(image.colorAt(x: 0, y: 0)?.usingColorSpace(.sRGB))
                XCTAssertEqual(background.alphaComponent, 0)
                // A bar near the midpoint contains the fixture's constant tone, in the Talos accent.
                XCTAssertEqual(image.colorSpace.cgColorSpace?.name as String?, CGColorSpace.sRGB as String)
                // colorAt returns a calibrated NSColor despite the bitmap's sRGB profile.
                // Read decoded components with their declared profile instead of converting twice.
                var color = [Int](repeating: 0, count: 4)
                image.getPixel(&color, atX: 800, y: 200)
                XCTAssertEqual(color, [202, 73, 28, 255])
            } else {
                let svg = try String(contentsOf: output, encoding: .utf8)
                XCTAssertTrue(svg.contains("viewBox=\"0 0 1600 400\""))
                XCTAssertTrue(svg.contains("fill=\"#CA491C\""))
                XCTAssertEqual(svg.components(separatedBy: "<rect ").count - 1, 512)
            }
        }
        XCTAssertEqual(try Data(contentsOf: input), original)
    }

    func testBuiltInConvertWebPExports() throws {
        let directory = try mediaFixture("convertWebP")
        let input = directory.appendingPathComponent("sample.png")
        let original = try Data(contentsOf: input)
        let output = directory.appendingPathComponent("sample-converted.webp")
        finishOnboarding(openSettings: false)
        // WebP is the second image format in the actual Convert submenu.
        dropOnWheel(file: input, offset: CGVector(dx: -85, dy: -53)) { waitForFile(output) }
        XCTAssertFalse(app.windows["Convert"].exists)
        let bytes = try Data(contentsOf: output)
        XCTAssertEqual(String(data: bytes.prefix(4), encoding: .ascii), "RIFF")
        XCTAssertEqual(String(data: bytes.subdata(in: 8..<12), encoding: .ascii), "WEBP")
        let image = try XCTUnwrap(NSBitmapImageRep(data: bytes))
        XCTAssertEqual(image.pixelsWide, 320)
        XCTAssertEqual(image.pixelsHigh, 240)
        XCTAssertEqual(try Data(contentsOf: input), original)
    }

    func testBuiltInConvertArchiveExports() throws {
        let directory = try mediaFixture("convertArchives")
        let input = directory.appendingPathComponent("sample.zip")
        let original = try Data(contentsOf: input)
        finishOnboarding(openSettings: false)
        // Three formats share the remaining 290 degrees above the fixed Back segment.
        for (format, offset) in [("zip", CGVector(dx: -102, dy: 12)),
                                 ("tar", CGVector(dx: 0, dy: -105)),
                                 ("tgz", CGVector(dx: 102, dy: 12))] {
            let output = directory.appendingPathComponent("sample-converted.\(format)")
            dropOnWheel(file: input, offset: offset) { waitForFile(output) }
            XCTAssertFalse(app.windows["Convert"].exists)
            for (entry, expected) in [("picture.png", try Data(contentsOf: directory.appendingPathComponent("sample.png"))),
                                      ("nested/notes.txt", Data("A file inside the archive".utf8))] {
                let process = Process(), pipe = Pipe()
                process.executableURL = URL(filePath: "/usr/bin/tar")
                process.arguments = ["-xOf", output.path, entry]
                process.standardOutput = pipe
                try process.run()
                let contents = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                XCTAssertEqual(process.terminationStatus, 0)
                XCTAssertEqual(contents, expected, "\(format) must preserve \(entry)")
            }
            let bytes = try Data(contentsOf: output)
            if format == "tgz" { XCTAssertEqual(Array(bytes.prefix(2)), [0x1f, 0x8b]) }
            XCTAssertEqual(try Data(contentsOf: input), original)
        }
    }

    func testBuiltInRedactAudioPreviewsAndExportsBleepedSelections() async throws {
        let directory = try mediaFixture("redactAudio")
        let input = directory.appendingPathComponent("sample.wav")
        let original = try Data(contentsOf: input)
        finishOnboarding(openSettings: false)
        let window = app.windows["Redact"]
        dropOnWheel(file: input, offset: CGVector(dx: 0, dy: -105)) {
            XCTAssertTrue(window.waitForExistence(timeout: 15), "Audio files must enable the real Redact wheel action")
        }
        let surface = window.descendants(matching: .any)["Audio waveform. Drag to select; use arrow keys to move a selection, or Backspace to delete."].firstMatch
        XCTAssertTrue(surface.waitForExistence(timeout: 15))
        let save = window.buttons["Save"]
        let play = window.buttons["Play bleeped audio"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in play.isEnabled }, object: nil)
        await fulfillment(of: [ready], timeout: 15)
        XCTAssertFalse(save.isEnabled)
        XCTAssertGreaterThan(play.frame.minY, window.frame.maxY - 65, "Playback controls must stay at the bottom of the window")
        XCTAssertEqual(window.textFields.count, 0, "Audio redaction must have only a waveform and playback bar")
        XCTAssertFalse(window.buttons["Add bleep"].exists)
        surface.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.3))
            .click(forDuration: 0.1, thenDragTo: surface.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.7)), withVelocity: .slow, thenHoldForDuration: 0.1)
        XCTAssertTrue(save.isEnabled)
        window.typeKey(.delete, modifierFlags: [])
        XCTAssertFalse(save.isEnabled, "Backspace must remove the selected rectangle")
        surface.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.3))
            .click(forDuration: 0.1, thenDragTo: surface.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.7)), withVelocity: .slow, thenHoldForDuration: 0.1)
        XCTAssertTrue(save.isEnabled)
        let selection = window.checkBoxes.firstMatch
        let widthBeforeResize = selection.frame.width
        selection.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5))
            .click(forDuration: 0.1, thenDragTo: surface.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.5)), withVelocity: .slow, thenHoldForDuration: 0.1)
        XCTAssertGreaterThan(selection.frame.width, widthBeforeResize * 1.15, "The right handle must resize the actual bleep interval")
        let screenshot = XCTAttachment(screenshot: window.screenshot())
        screenshot.name = "Audio waveform and bleep selection"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        play.click()
        let pause = window.buttons["Pause preview"]
        XCTAssertTrue(pause.waitForExistence(timeout: 10), "The actual chunked audio preview must start")
        // Run past several chunk boundaries, then test cancelling a second playback.
        let finished = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            window.staticTexts["0:05 / 0:05"].exists && play.exists
        }, object: nil)
        await fulfillment(of: [finished], timeout: 12)
        play.click()
        XCTAssertTrue(pause.waitForExistence(timeout: 5))
        pause.click()
        window.buttons["Save"].click()
        let output = directory.appendingPathComponent("sample-redacted.wav")
        waitForFile(output)
        XCTAssertTrue(window.waitForNonExistence(timeout: 10))
        XCTAssertEqual(try Data(contentsOf: input), original)
        let asset = AVURLAsset(url: output)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(tracks.count, 1)
        let duration = try await asset.load(.duration)
        XCTAssertEqual(duration.seconds, 5, accuracy: 0.001)
        // Decode the saved result independently of FFmpeg and verify both source tones are gone.
        let reader = try AVAssetReader(asset: asset)
        let decoded = AVAssetReaderTrackOutput(track: try XCTUnwrap(tracks.first), outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMIsFloatKey: true,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsNonInterleaved: false
        ])
        reader.add(decoded)
        XCTAssertTrue(reader.startReading())
        var frame = 0, checked = 0
        while let buffer = decoded.copyNextSampleBuffer() {
            let block = try XCTUnwrap(CMSampleBufferGetDataBuffer(buffer))
            var bytes = Data(count: CMBlockBufferGetDataLength(block))
            let byteCount = bytes.count
            let copied = bytes.withUnsafeMutableBytes { pointer in
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: byteCount, destination: pointer.baseAddress!)
            }
            XCTAssertEqual(copied, kCMBlockBufferNoErr)
            bytes.withUnsafeBytes { pointer in
                let values = pointer.bindMemory(to: Float.self)
                for offset in stride(from: 0, to: values.count, by: 2) {
                    let time = Double(frame) / 48000
                    if time >= 0.55 && time < 1.65 {
                        let expected = Float(0.18 * sin(2 * .pi * 1000 * time))
                        XCTAssertEqual(values[offset], expected, accuracy: 0.00001)
                        XCTAssertEqual(values[offset + 1], expected, accuracy: 0.00001)
                        checked += 1
                    }
                    frame += 1
                }
            }
        }
        XCTAssertEqual(reader.status, .completed)
        XCTAssertEqual(checked, 52800)
    }

    func testBuiltInRedactImageStillExportsBlackBlocks() throws {
        let directory = try mediaFixture("redactImage")
        let input = directory.appendingPathComponent("sample.png")
        let original = try Data(contentsOf: input)
        finishOnboarding(openSettings: false)
        let window = app.windows["Redact"]
        dropOnWheel(file: input, offset: CGVector(dx: 0, dy: -105)) {
            XCTAssertTrue(window.waitForExistence(timeout: 15))
        }
        let surface = window.descendants(matching: .any)["Drag to draw a black block. Select a block to move or resize it; press Backspace to delete it."].firstMatch
        XCTAssertTrue(surface.waitForExistence(timeout: 15))
        surface.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.3))
            .click(forDuration: 0.1, thenDragTo: surface.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.7)), withVelocity: .slow, thenHoldForDuration: 0.1)
        window.buttons["Save"].click()
        let output = directory.appendingPathComponent("sample-redacted.png")
        waitForFile(output)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: output)))
        let center = try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)?.usingColorSpace(.deviceRGB))
        XCTAssertEqual(center.redComponent, 0, accuracy: 0.001)
        XCTAssertEqual(center.greenComponent, 0, accuracy: 0.001)
        XCTAssertEqual(center.blueComponent, 0, accuracy: 0.001)
        XCTAssertEqual(try Data(contentsOf: input), original)
    }

    func testBuiltInCompressionPreservesPixels() throws {
        let directory = try mediaFixture("compress")
        finishOnboarding(openSettings: false)
        let input = directory.appendingPathComponent("sample.png")
        // Six default actions put Compress at the bottom of the image wheel.
        let output = directory.appendingPathComponent("sample-compressed.png")
        dropOnWheel(file: input, offset: CGVector(dx: 0, dy: 105)) {
            waitForFile(output)
        }
        let originalData = try Data(contentsOf: input), outputData = try Data(contentsOf: output)
        XCTAssertLessThan(outputData.count, originalData.count)
        let original = try XCTUnwrap(NSBitmapImageRep(data: originalData))
        let compressed = try XCTUnwrap(NSBitmapImageRep(data: outputData))
        XCTAssertEqual(compressed.pixelsWide, original.pixelsWide)
        XCTAssertEqual(compressed.pixelsHigh, original.pixelsHigh)
        XCTAssertEqual(try rgbaPixels(of: original), try rgbaPixels(of: compressed), "Lossless compression must preserve every pixel")
    }

    func testBuiltInVideoCropPreviewsAndExports() async throws {
        let directory = try mediaFixture("video")
        let input = directory.appendingPathComponent("sample.mp4")
        finishOnboarding(openSettings: false)
        let window = app.windows["Crop"]
        dropOnWheel(file: input, offset: CGVector(dx: 0, dy: -105)) {
            XCTAssertTrue(window.waitForExistence(timeout: 15))
        }
        let preview = window.buttons["Play preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 15), "Local video metadata must load without copying all bytes through JSON")
        let screenshot = window.screenshot()
        let firstFrame = XCTAttachment(screenshot: screenshot)
        firstFrame.name = "Video crop before Play"
        firstFrame.lifetime = .keepAlways
        add(firstFrame)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: screenshot.pngRepresentation))
        let color = try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 3)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(max(color.redComponent, color.greenComponent, color.blueComponent)
            - min(color.redComponent, color.greenComponent, color.blueComponent), 0.15,
            "The colorful first video frame must be visible before Play")
        preview.click()
        XCTAssertTrue(window.buttons["Pause preview"].waitForExistence(timeout: 5))
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
        // Unsupported actions stay visible, so Archive remains the second of six segments.
        let output = directory.appendingPathComponent("Archive.zip")
        dropOnWheel(file: directory.appendingPathComponent("sample.png"), offset: CGVector(dx: 91, dy: -52), includingFile: "notes.txt") {
            waitForFile(output)
        }
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

    private func rgbaPixels(of bitmap: NSBitmapImageRep) throws -> Data {
        let image = try XCTUnwrap(bitmap.cgImage)
        var pixels = Data(count: image.width * image.height * 4)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return pixels
    }

    private func mediaFixture(_ name: String) throws -> URL {
        // The build phase prepares a clean fixture outside the sandboxed runner's
        // private container, so the Talos Node process can save beside the inputs.
        let directory = Bundle.main.bundleURL.deletingLastPathComponent()
            .appendingPathComponent("TalosUITestFixtures/\(name)", isDirectory: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("sample.png").path))
        return directory
    }

    private func waitForFile(_ url: URL) {
        let exists = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in FileManager.default.fileExists(atPath: url.path) }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [exists], timeout: 20), .completed, "Missing output: \(url.lastPathComponent)")
    }

    private func dropOnWheel(file: URL, offset: CGVector, includingFile: String? = nil,
                             modifiers: XCUIElement.KeyModifierFlags = .shift, verifyDrop: () -> Void) {
        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        finder.activate()
        finder.typeKey("g", modifierFlags: [.command, .shift])
        let path = finder.sheets["GoToWindow"].textFields["PathTextField"]
        XCTAssertTrue(path.waitForExistence(timeout: 5))
        replaceText(path, with: file.deletingLastPathComponent().path)
        finder.typeKey(.return, modifierFlags: [])
        finder.typeKey("1", modifierFlags: .command)
        centerFinderWindow(finder)
        let source = finder.windows.firstMatch.images[file.lastPathComponent].firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        // Start unselected: Shift-clicking an already selected Finder icon deselects it.
        finder.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.8)).click()
        if let includingFile { finder.windows.firstMatch.images[includingFile].firstMatch.click() }
        let point = source.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        XCUIElement.perform(withKeyModifiers: modifiers) {
            point.click(forDuration: 0.2, thenDragTo: point.withOffset(offset), withVelocity: XCUIGestureVelocity(rawValue: 40), thenHoldForDuration: 1.2)
            // Keep the activation key down until AppKit has delivered the mouse-up/drop callbacks.
            verifyDrop()
        }
    }

    private func centerFinderWindow(_ finder: XCUIApplication) {
        let window = finder.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        guard let screen = NSScreen.screens.first else {
            XCTFail("Finder drag tests require a display")
            return
        }
        // AppKit screen coordinates start at the bottom; XCTest starts at the top.
        let visible = CGRect(x: screen.visibleFrame.minX, y: screen.frame.maxY - screen.visibleFrame.maxY,
                             width: screen.visibleFrame.width, height: screen.visibleFrame.height)
        let size = CGSize(width: min(760, visible.width - 80), height: min(520, visible.height - 80))
        // Move away from screen edges before resizing so macOS does not clamp the height.
        moveFinderWindowToCenter(window, in: visible)
        if abs(window.frame.width - size.width) > 2 {
            let width = window.frame.width
            let edge = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5))
                .withOffset(CGVector(dx: -1, dy: 0))
            edge.click(forDuration: 0.1,
                thenDragTo: edge.withOffset(CGVector(dx: size.width - width, dy: 0)),
                withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        if abs(window.frame.height - size.height) > 2 {
            let height = window.frame.height
            let edge = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1))
                .withOffset(CGVector(dx: 0, dy: -1))
            edge.click(forDuration: 0.1,
                thenDragTo: edge.withOffset(CGVector(dx: 0, dy: size.height - height)),
                withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        let resized = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            abs(window.frame.width - size.width) < 8 && abs(window.frame.height - size.height) < 8
        }, object: nil)
        let result = XCTWaiter.wait(for: [resized], timeout: 5)
        XCTAssertEqual(result, .completed, "Finder must have a predictable size: frame \(window.frame), size \(size)")
        moveFinderWindowToCenter(window, in: visible)
    }

    private func moveFinderWindowToCenter(_ window: XCUIElement, in visible: CGRect) {
        let current = window.frame
        let target = CGPoint(x: visible.midX - current.width / 2, y: visible.midY - current.height / 2)
        guard abs(current.minX - target.x) > 2 || abs(current.minY - target.y) > 2 else { return }
        let titlebar = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
            .withOffset(CGVector(dx: 0, dy: 18))
        titlebar.click(forDuration: 0.1,
            thenDragTo: titlebar.withOffset(CGVector(dx: target.x - current.minX, dy: target.y - current.minY)),
            withVelocity: .slow, thenHoldForDuration: 0.1)
        let centered = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            // Native titlebar dragging can consume the first few pixels before the window moves.
            abs(window.frame.minX - target.x) < 20 && abs(window.frame.minY - target.y) < 20
        }, object: nil)
        let result = XCTWaiter.wait(for: [centered], timeout: 5)
        XCTAssertEqual(result, .completed,
                       "Finder must be centered before dragging: frame \(window.frame), target \(target), visible \(visible)")
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
        showSettingsWindow()
    }

    private func showSettingsWindow() {
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
