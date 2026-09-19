import Foundation

@main struct ExtensionContractChecks {
    static func main() throws {
        let source = URL(fileURLWithPath: "Tests/Fixtures/HostTestModule/config.json")
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: source)) as! [String: Any]
        func decode(_ value: [String: Any]) throws -> ModuleManifest {
            try JSONDecoder().decode(ModuleManifest.self, from: JSONSerialization.data(withJSONObject: value))
        }
        let manifest = try decode(json)
        try manifest.validate()
        precondition(Version("2.0.0")! > Version("1.9.9")!)
        precondition(Version("invalid") == nil)
        precondition(ModuleManifest.safeComponent("extension.mjs"))
        precondition(!ModuleManifest.safeComponent("../extension.mjs"))
        json["entrypoint"] = "../extension.mjs"
        do { try decode(json).validate(); fatalError("Accepted traversal") }
        catch is ManifestError {}
        json["entrypoint"] = "extension.mjs"
        json["runtime"] = "native"
        do { try decode(json).validate(); fatalError("Accepted native runtime") }
        catch is ManifestError {}
        json["runtime"] = "javascript"
        json["sdkVersion"] = 999
        do { try decode(json).validate(); fatalError("Accepted unsupported protocol") }
        catch is ManifestError {}
        print("Passed: JavaScript-only contracts, versions, path validation and protocol rejection")
    }
}
