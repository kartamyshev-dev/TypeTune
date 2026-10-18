import Foundation
import LayoutPilotCore

func resourceChecks() -> [(Bool, String)] {
    var checks: [(Bool, String)] = []
    func check(_ result: Bool, _ name: String) { checks.append((result, "resources: " + name)) }
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("typetune-resources-\(UUID().uuidString)", isDirectory: true)
    defer { try? fm.removeItem(at: root) }
    func place(_ path: String) -> URL {
        let file = root.appendingPathComponent(path)
        try? fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        _ = fm.createFile(atPath: file.path, contents: Data("{}".utf8))
        return file
    }
    func find(_ directories: [String]) -> URL? {
        CoreResources.url(forResource: "lexicon", withExtension: "json",
                          searching: directories.map { root.appendingPathComponent($0, isDirectory: true) })
    }
    // What build.sh produces on macOS CI: a flat bundle inside the app's Resources.
    let flat = place("A.app/Contents/Resources/LayoutPilot_LayoutPilotCore.bundle/lexicon.json")
    check(find(["A.app/Contents/Resources"])?.standardizedFileURL == flat.standardizedFileURL, "flat bundle in the app's Resources")
    let nested = place("B.app/Contents/Resources/LayoutPilot_LayoutPilotCore.bundle/Contents/Resources/lexicon.json")
    check(find(["B.app/Contents/Resources"])?.standardizedFileURL == nested.standardizedFileURL, "bundle with Contents/Resources")
    let cli = place("dist/LayoutPilot_LayoutPilotCore.bundle/lexicon.json")
    check(find(["missing", "dist"])?.standardizedFileURL == cli.standardizedFileURL, "next to the CLI after an empty candidate")
    let linux = place("linux/LayoutPilot_LayoutPilotCore.resources/lexicon.json")
    check(find(["linux"])?.standardizedFileURL == linux.standardizedFileURL, "Linux .resources directory")
    check(find(["A.app/Contents/Resources", "dist"])?.standardizedFileURL == flat.standardizedFileURL, "the first directory wins")
    check(find(["missing", "A.app"]) == nil, "nothing outside the searched directories")
    check(CoreResources.url(forResource: "lexicon", withExtension: "json", searching: [root]) == nil, "the bundle name must match")
    check(CoreResources.url(forResource: "lexicon", withExtension: "json") != nil, "this build finds its lexicon")
    return checks
}
