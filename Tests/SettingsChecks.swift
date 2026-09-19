import AppKit

@main struct SettingsChecks {
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("local")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: CommandLine.arguments[1]), to: sourceURL)
        let store = LibraryStore(root: root.appendingPathComponent("state"))
        let installer = ModuleInstaller(modulesDirectory: root.appendingPathComponent("installed"))
        let model = ModuleLibraryModel(store: store, installer: installer)
        var settingsOpened = false
        model.configureOpenSettings { settingsOpened = true }
        await model.load()
        await model.importLocal(sourceURL)
        precondition(model.error == nil, model.error ?? "")
        precondition(model.actionItems.count == 2)
        let original = model.actionItems.map(\.id)
        await model.moveActions(from: IndexSet(integer: 0), to: 2)
        precondition(model.actionItems.map(\.id) == original.reversed())
        await model.setActionEnabled(false, item: model.actionItems[0])
        let txt = ModuleFile(url: root.appendingPathComponent("sample.txt"), typeIdentifier: "public.plain-text", isDirectory: false, isPackage: false)
        precondition(model.paletteActions.last?.id == ModuleLibraryModel.settingsActionID)
        precondition(model.wheelEntries.last?.actionID == ModuleLibraryModel.settingsActionID)
        let defaultActions = model.actions(for: [txt])
        precondition(defaultActions.count == 2)
        guard case .handler(let openSettings) = defaultActions.last?.destination else {
            preconditionFailure("Built-in Settings action missing")
        }
        openSettings([])
        precondition(settingsOpened)
        let saved = try await store.load()
        precondition(saved.actionOrder == Array(original.reversed()))
        precondition(saved.disabledActions == [original[1]])
        // Version changes replace the app but preserve action identities and preferences.
        let manifestURL = sourceURL.appendingPathComponent("config.json")
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as! [String: Any]
        json["version"] = "1.0.1"
        try JSONSerialization.data(withJSONObject: json).write(to: manifestURL)
        await model.refresh()
        let source = model.snapshot.repositories[0]
        precondition(model.hasUpdate(source))
        await model.update(source)
        precondition(model.error == nil, model.error ?? "")
        precondition(!model.hasUpdate(source))
        precondition(model.snapshot.installed[0].manifest.version == "1.0.1")
        precondition(model.actionItems.map(\.id) == saved.actionOrder)
        precondition(model.actions(for: [txt]).count == 2)
        // The editor enables palette drops and uses the exact visible wheel order.
        await model.placeAction(original[1], at: 0)
        precondition(model.actionItems.filter(model.actionEnabled).map(\.id) == Array(original.reversed()))
        await model.placeAction(original[1], at: 1)
        precondition(model.actionItems.filter(model.actionEnabled).map(\.id) == original)
        precondition(model.actions(for: [txt]).map(\.title) ==
            model.actionItems.filter(model.actionEnabled).map { $0.action.title } + ["Settings"])
        let editorSnapshot = try await store.load()
        precondition(editorSnapshot.actionOrder == original && editorSnapshot.disabledActions.isEmpty)
        await model.placeAction("unknown-action", at: 0)
        precondition(model.actionItems.map(\.id) == original)
        // A folder tree preserves duplicate placements, order, and independent removal.
        let legacy = model.wheelEntries.filter { $0.actionID != ModuleLibraryModel.settingsActionID }
        precondition(legacy.map(\.actionID) == original.map(Optional.some))
        precondition(model.wheelEntries.last?.actionID == ModuleLibraryModel.settingsActionID)
        let reports = (0..<5).map { _ in WheelEntry.action(original[1]) }
        let inner = WheelEntry(title: "Reports", children: reports)
        let outer = WheelEntry(title: "Tools", children: [inner])
        await model.setWheelEntries([legacy[0], outer, .folder("Empty")], at: [])
        precondition(model.error == nil, model.error ?? "")
        let treeSaved = try await store.load()
        precondition(treeSaved.wheel == model.wheelEntries)
        let reopened = ModuleLibraryModel(store: store, installer: installer)
        await reopened.load()
        precondition(reopened.wheelEntries == model.wheelEntries)
        let rootActions = reopened.actions(for: [txt])
        precondition(rootActions.count == 2, "Empty folders must not become dead ends during file drags")
        guard case .submenu(let tools) = rootActions[1].destination,
              case .submenu(let reportActions) = tools[0].destination else { preconditionFailure("Nested folders missing") }
        precondition(reportActions.count == 5 && Set(reportActions.map(\.id)).count == 5)
        let wheel = WheelModel()
        wheel.reset(actions: rootActions, files: [])
        wheel.enter(tools); wheel.enter(reportActions)
        wheel.back(); precondition(wheel.actions.map(\.id) == tools.map(\.id))
        wheel.back(); precondition(wheel.actions.map(\.id) == rootActions.map(\.id))
        let reordered = [reports[4], reports[0], reports[2], reports[3]]
        await model.setWheelEntries(reordered, at: [outer.id, inner.id])
        precondition(WheelEntry.entries(in: model.wheelEntries, path: [outer.id, inner.id]) == reordered)
        precondition(model.wheelEntries[0] == legacy[0])
        // Pagination operates inside each folder without dropping repeated actions.
        let many = (0..<12).map { _ in WheelEntry.action(original[1]) }
        await model.setWheelEntries(many, at: [outer.id, inner.id])
        guard case .submenu(let outerPage) = model.actions(for: [txt])[1].destination,
              case .submenu(let firstPage) = outerPage[0].destination,
              case .submenu(let secondPage) = firstPage[7].destination else { preconditionFailure("Folder pagination missing") }
        precondition(firstPage.count == 8 && secondPage.count == 5)
        await model.setWheelEntries([], at: [])
        precondition(model.actions(for: [txt]).isEmpty)
        let emptySaved = try await store.load()
        precondition(emptySaved.wheel == [])
        await model.removeRepository(source)
        precondition(model.snapshot.installed.isEmpty && model.snapshot.repositories.isEmpty)
        let oldJSON = Data("{\"installed\":[],\"repositories\":[]}".utf8)
        let migrated = try JSONDecoder().decode(LibrarySnapshot.self, from: oldJSON)
        precondition(migrated.actionOrder.isEmpty && migrated.disabledActions.isEmpty)
        print("Passed: local repository install/update/remove, persistent action order and toggles, nested folders, duplicate placements, pagination, legacy catalogue decoding")
    }
}
