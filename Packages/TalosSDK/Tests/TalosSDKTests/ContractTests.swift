import Foundation
import Testing
@testable import TalosSDK

private func manifest() throws -> ModuleManifest {
    try JSONDecoder().decode(ModuleManifest.self, from: Data(#"""
    {"id":"test.images","name":"Images","description":"Test","version":"1.2.0","sdkVersion":1,
     "minimumMacOS":"15.0","architectures":["arm64"],"appBundle":"Images.app",
     "actions":[{"id":"convert","title":"Convert","acceptedTypes":["public.image"],"minimumFiles":1,
       "children":[{"id":"png","title":"PNG","acceptedTypes":["public.image"],"minimumFiles":1,"maximumFiles":3}]}]}
    """#.utf8))
}

@Test func typesAndMixedSelections() throws {
    let action = try manifest().actions[0]
    let image = ModuleFile(url: URL(fileURLWithPath: "/tmp/a.png"), typeIdentifier: "public.png")
    let movie = ModuleFile(url: URL(fileURLWithPath: "/tmp/a.mov"), typeIdentifier: "com.apple.quicktime-movie")
    #expect(action.filtered(for: [image])?.children?.count == 1)
    #expect(action.filtered(for: [movie]) == nil)
    #expect(action.filtered(for: [image, movie]) == nil)
    #expect(action.filtered(for: []) == nil)
    #expect(action.filtered(for: Array(repeating: image, count: 4)) == nil)
}

@Test func manifestsAndVersions() throws {
    try manifest().validate()
    let children = (0..<22).map { index in
        let type = index < 8 ? "public.image" : "public.movie"
        return #"{"id":"format-\#(index)","title":"Format \#(index)","acceptedTypes":["\#(type)"],"minimumFiles":1}"#
    }.joined(separator: ",")
    let catalogue = try JSONDecoder().decode(ModuleManifest.self, from: Data(#"""
    {"id":"test.converter","name":"Converter","description":"Test","version":"1.0.0","sdkVersion":1,
     "minimumMacOS":"15.0","architectures":["arm64"],"appBundle":"Converter.app",
     "actions":[{"id":"convert","title":"Convert","acceptedTypes":["public.image","public.movie"],"minimumFiles":1,
       "children":[\#(children)]}]}
    """#.utf8))
    try catalogue.validate()
    let image = ModuleFile(url: URL(fileURLWithPath: "/tmp/a.png"), typeIdentifier: "public.png")
    #expect(catalogue.actions[0].filtered(for: [image])?.children?.count == 8)
    #expect(Version("1.10.0")! > Version("1.9.9")!)
    #expect(Version("1.0") == Version("1.0.0"))
    #expect(Version("1..0") == nil)
    #expect(!ModuleManifest.safeComponent("../evil.app"))
    #expect(!ModuleManifest.validIdentifier("../../module"))
    let json = String(decoding: try JSONEncoder().encode(manifest()), as: UTF8.self)
    let incompatible = try JSONDecoder().decode(ModuleManifest.self, from: Data(json.replacingOccurrences(of: "\"sdkVersion\":1", with: "\"sdkVersion\":99").utf8))
    #expect(throws: ManifestError.self) { try incompatible.validate() }
}

@Test func moduleIPCAndCancellation() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let invocation = ModuleInvocation(taskID: UUID(), moduleID: "test", actionID: "run", files: [], workspace: directory)
    let input = directory.appendingPathComponent("invocation.json")
    try JSONEncoder().encode(invocation).write(to: input)
    let session = try ModuleSession(invocationURL: input)
    try await session.progress(0.5, message: "Halfway")
    try await session.notify("Ready", actions: [.init(id: "reveal", title: "Show in Finder")])
    try JSONEncoder().encode("reveal").write(to: directory.appendingPathComponent("notification-action.json"))
    #expect(try await session.takeNotificationAction() == "reveal")
    #expect(try await session.takeNotificationAction() == nil)
    try Data().write(to: directory.appendingPathComponent("cancel"))
    await #expect(throws: CancellationError.self) { try await session.checkCancellation() }
    try await session.complete(message: "Done")
    try await session.progress(0.8, message: "Ignored after completion")
    let lines = try String(contentsOf: directory.appendingPathComponent("events.jsonl"), encoding: .utf8).split(separator: "\n")
    let events = try lines.map { try JSONDecoder().decode(ModuleEvent.self, from: Data($0.utf8)) }
    #expect(events.count == 3)
    #expect(events[0].fraction == 0.5)
    #expect(events.allSatisfy { $0.taskID == invocation.taskID })
    #expect(events.last?.kind == .completed)
}
