import AppKit

/// Native action windows live in the helper, keeping the wheel process focused on dragging.
@MainActor enum NativeActionBridge {
    static func openPending(_ invocation: ModuleInvocation, handled: inout Set<String>) async throws {
        let file = invocation.workspace.appendingPathComponent("native-request.json")
        guard let data = try? Data(contentsOf: file),
              let request = try? JSONDecoder().decode(NativeActionRequest.self, from: data),
              !handled.contains(request.id) else { return }
        guard UUID(uuidString: request.id) != nil, ["image", "crop"].contains(request.kind) else {
            throw ManifestError.invalid("Invalid native action request")
        }
        handled.insert(request.id)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = ["--action-request", file.path]
        configuration.createsNewApplicationInstance = true
        configuration.activates = request.kind == "crop"
        _ = try await NSWorkspace.shared.openApplication(
            at: Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/Talos.app"),
            configuration: configuration)
    }
}

nonisolated struct NativeActionRequest: Codable {
    let id: String
    let kind: String
    let input: String
    let output: String?
    let stripMetadata: Bool?
}
