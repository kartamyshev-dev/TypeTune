// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "TypeTune", platforms: [.macOS("27.0")],
    products: [.executable(name: "TypeTune", targets: ["TypeTune"])],
    targets: [
        .systemLibrary(name: "CTypeTune"),
        .target(name: "TypeTuneSupport"),
        .executableTarget(name: "TypeTune", dependencies: ["CTypeTune", "TypeTuneSupport"],
            linkerSettings: [.linkedFramework("Carbon"), .linkedFramework("ApplicationServices")]),
        .testTarget(name: "TypeTuneSupportTests", dependencies: ["TypeTuneSupport", "TypeTune"])
    ])
