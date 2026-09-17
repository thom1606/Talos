// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "HostTestModule", platforms: [.macOS(.v15)],
    dependencies: [.package(path: "../../..")],
    targets: [.executableTarget(name: "HostTestModule", dependencies: [.product(name: "TalosSDK", package: "Talos")])],
    swiftLanguageModes: [.v6])
