// swift-tools-version: 6.0
import PackageDescription

// Remote SwiftPM entry point. The host and external modules share these sources.
let package = Package(
    name: "TalosSDK",
    platforms: [.macOS(.v15)],
    products: [.library(name: "TalosSDK", targets: ["TalosSDK"]),
               .plugin(name: "TalosBuild", targets: ["TalosBuild"])],
    targets: [
        .plugin(name: "TalosBuild", capability: .command(
            intent: .custom(verb: "talos-build", description: "Build and package a native Talos action module"),
            permissions: [.writeToPackageDirectory(reason: "Create the installable module in dist/")]),
            path: "Plugins/TalosBuild"),
        .target(name: "TalosSDK", path: "Packages/TalosSDK/Sources/TalosSDK"),
        .testTarget(name: "TalosSDKTests", dependencies: ["TalosSDK"],
                    path: "Packages/TalosSDK/Tests/TalosSDKTests")
    ],
    swiftLanguageModes: [.v6]
)
