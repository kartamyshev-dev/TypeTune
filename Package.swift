// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LayoutPilot",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "LayoutPilot", targets: ["LayoutPilot"]),
        .executable(name: "layoutpilot-cli", targets: ["LayoutPilotCLI"])
    ],
    targets: [
        .target(name: "LayoutPilotCore", resources: [.process("Resources")]),
        .executableTarget(name: "LayoutPilot", dependencies: ["LayoutPilotCore"],
                          swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "LayoutPilotCLI", dependencies: ["LayoutPilotCore"]),
        .testTarget(name: "LayoutPilotCoreTests", dependencies: ["LayoutPilotCore"])
    ]
)
