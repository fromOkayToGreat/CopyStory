// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CopyStory",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "CopyStory", targets: ["CopyStory"]), .library(name: "CopyStoryCore", targets: ["CopyStoryCore"])],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
    ],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .target(name: "CopyStoryCore", dependencies: ["CSQLite"]),
        .executableTarget(name: "CopyStory", dependencies: ["CopyStoryCore", .product(name: "Sparkle", package: "Sparkle")], linkerSettings: [.linkedFramework("Carbon")]),
        .testTarget(name: "CopyStoryCoreTests", dependencies: ["CopyStoryCore"]),
        .testTarget(name: "CopyStoryPlatformTests", dependencies: ["CopyStory"])
    ],
    swiftLanguageModes: [.v5]
)
