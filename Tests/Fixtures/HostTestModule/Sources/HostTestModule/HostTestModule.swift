import Foundation
import TalosSDK

// Internal integration-test fixture, not a user-facing action or template.
@main struct HostTestModule: ModuleApplication {
    static func run(session: ModuleSession) async throws {
        let reports = try session.invocation.files.map { file in
            let attributes = try FileManager.default.attributesOfItem(atPath: file.url.path)
            return Report(path: file.url.path, bytes: (attributes[.size] as? NSNumber)?.int64Value ?? 0)
        }
        let output = session.invocation.workspace.appendingPathComponent("report.json")
        try JSONEncoder().encode(reports).write(to: output)
        try await session.complete(message: "Fixture completed", outputs: [output])
    }
    struct Report: Encodable { let path: String; let bytes: Int64 }
}
