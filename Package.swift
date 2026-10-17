// swift-tools-version: 6.0
import PackageDescription

var products: [Product] = [
    .executable(name: "layoutpilot-cli", targets: ["LayoutPilotCLI"])
]
var targets: [Target] = [
    .target(name: "LayoutPilotCore", resources: [.process("Resources")]),
    .executableTarget(name: "LayoutPilotCLI", dependencies: ["LayoutPilotCore"]),
    .testTarget(name: "LayoutPilotCoreTests", dependencies: ["LayoutPilotCore"])
]
// The AppKit application exists only on macOS; Core, CLI and tests also build on Linux.
#if os(macOS)
products.insert(.executable(name: "LayoutPilot", targets: ["LayoutPilot"]), at: 0)
targets.insert(.executableTarget(name: "LayoutPilot", dependencies: ["LayoutPilotCore"],
                                 swiftSettings: [.swiftLanguageMode(.v5)]), at: 1)
#endif

let package = Package(
    name: "LayoutPilot",
    platforms: [.macOS(.v14)],
    products: products,
    targets: targets
)
