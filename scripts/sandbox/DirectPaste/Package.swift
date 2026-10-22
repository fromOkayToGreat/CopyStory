// swift-tools-version: 6.0
import PackageDescription

// Independent, dependency-free harness. Never resolves the production package.
let package = Package(
    name: "DirectPasteExperiment", platforms: [.macOS("26.0")],
    products: [.executable(name: "PastePrototype", targets: ["PastePrototype"]),
               .executable(name: "PasteFixture", targets: ["PasteFixture"])],
    targets: [.target(name: "RoutingCore"),
              .executableTarget(name: "PastePrototype", dependencies: ["RoutingCore"],
                                linkerSettings: [.linkedFramework("Carbon")]),
              .executableTarget(name: "PasteFixture"),
              .testTarget(name: "RoutingCoreTests", dependencies: ["RoutingCore"])],
    swiftLanguageModes: [.v5]
)
