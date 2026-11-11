// swift-tools-version: 6.0
import PackageDescription
import Foundation

// Transitional feasibility configuration; use a separate scratch path.
let appStore = ProcessInfo.processInfo.environment["COPYSTORY_LEGACY_UPDATER"] != "1"
let reconstruction = ProcessInfo.processInfo.environment["COPYSTORY_SHIPPING_RECONSTRUCTION"] == "1"
let productionTests = ProcessInfo.processInfo.environment["COPYSTORY_PRODUCTION_TESTS"] == "1"
precondition(!productionTests || (appStore && !reconstruction), "Production tests require APP_STORE without reconstruction")
let appSettings: [SwiftSetting] = (appStore ? [.define("APP_STORE")] : []) +
    (reconstruction ? [.define("SHIPPING_RECONSTRUCTION")] : []) +
    (productionTests ? [.define("COPYSTORY_PRODUCTION")] : [])

let package = Package(
    name: "CopyStory",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "CopyStory", targets: ["CopyStory"]), .library(name: "CopyStoryCore", targets: ["CopyStoryCore"])],
    dependencies: appStore ? [] : [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
    ],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .target(name: "CopyStoryCore", dependencies: ["CSQLite"]),
        .executableTarget(name: "CopyStory", dependencies: appStore ? ["CopyStoryCore"] : ["CopyStoryCore", .product(name: "Sparkle", package: "Sparkle")], exclude: reconstruction ? ["SandboxProbe.swift"] : [], swiftSettings: appSettings, linkerSettings: [.linkedFramework("Carbon")]),
        .testTarget(name: "CopyStoryCoreTests", dependencies: ["CopyStoryCore"]),
        .testTarget(name: "CopyStoryPlatformTests", dependencies: ["CopyStory"], swiftSettings: productionTests ? [.define("COPYSTORY_PRODUCTION")] : [])
    ],
    swiftLanguageModes: [.v5]
)
