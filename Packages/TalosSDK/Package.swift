// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TalosSDK",
    platforms: [.macOS(.v15)],
    products: [.library(name: "TalosSDK", targets: ["TalosSDK"])],
    targets: [.target(name: "TalosSDK"), .testTarget(name: "TalosSDKTests", dependencies: ["TalosSDK"])],
    swiftLanguageModes: [.v6]
)
