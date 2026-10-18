import Foundation

/// Locates Core's resources. SwiftPM's `Bundle.module` looks for the resource bundle at
/// the application's root and then at the absolute `.build` path of the machine that
/// compiled it. An `.app` keeps it in `Contents/Resources` and the CLI next to its
/// executable, so a build moved to another Mac would only work through that build path
/// and otherwise stop with `fatalError`. Those places are searched first;
/// `Bundle.module` remains the fallback for `swift build` and `swift test`.
public enum CoreResources {
    static let bundleName = "LayoutPilot_LayoutPilotCore"

    public static func url(forResource name: String, withExtension ext: String) -> URL? {
        let directories = [Bundle.main.resourceURL, Bundle.main.executableURL?.deletingLastPathComponent()].compactMap { $0 }
        return url(forResource: name, withExtension: ext, searching: directories) ??
            Bundle.module.url(forResource: name, withExtension: ext)
    }

    /// The resource inside a `<bundleName>.bundle` (macOS) or `.resources` (Linux) directory
    /// in one of `directories`, flat or with `Contents/Resources`.
    public static func url(forResource name: String, withExtension ext: String, searching directories: [URL]) -> URL? {
        for directory in directories {
            for suffix in ["bundle", "resources"] {
                let bundle = directory.appendingPathComponent("\(bundleName).\(suffix)", isDirectory: true)
                for inner in [bundle, bundle.appendingPathComponent("Contents/Resources", isDirectory: true)] {
                    let file = inner.appendingPathComponent("\(name).\(ext)")
                    if FileManager.default.isReadableFile(atPath: file.path) { return file }
                }
            }
        }
        return nil
    }
}
