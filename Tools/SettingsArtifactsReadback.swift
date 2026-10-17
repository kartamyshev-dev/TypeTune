import AppKit
import Foundation
import ImageIO
import LayoutPilotCore

/// Read-only observer. Does not activate windows, set defaults, post events or play audio.
@main private struct SettingsArtifactsReadback {
    static func main() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        guard args.count == 1, ["header-png","header-tiff","header-reset","sound","sound-reset","statistics","validate-fixtures"].contains(args[0]) else { exit(2) }
        let mode = args[0]
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        if mode == "validate-fixtures" {
            let fixtures = root.appendingPathComponent(".build/settings-fixtures")
            var checks: [String:Bool] = [:]
            for ext in ["png","tiff"] {
                let data = try Data(contentsOf: fixtures.appendingPathComponent("LP-F19-drop.\(ext)"))
                if let source = CGImageSourceCreateWithData(data as CFData,nil),
                   let image = CGImageSourceCreateImageAtIndex(source,0,nil) {
                    checks["\(ext)Decodes128x64"] = image.width == 128 && image.height == 64
                } else { checks["\(ext)Decodes128x64"] = false }
            }
            let sound = NSSound(contentsOf: fixtures.appendingPathComponent("LP-F08-soft.wav"),byReference:true)
            checks["wavDecodesWithoutPlayback"] = sound != nil && abs((sound?.duration ?? 0) - 0.22) < 0.01
            let result: [String:Any] = ["kind":"synthetic-fixtures-decoder-check","checks":checks,
                "passed":checks.values.allSatisfy { $0 },"soundPlayed":false,"uiUsed":false,"originalAccessed":false,
                "nativeDropVerified":false,"audibilityVerified":false]
            let output = try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys])
            print(String(decoding:output,as:UTF8.self))
            if !checks.values.allSatisfy({ $0 }) { exit(1) }
            return
        }
        let expectedExecutable = root.appendingPathComponent("dist/LayoutPilot.app/Contents/MacOS/LayoutPilot").standardizedFileURL
        let matches = NSRunningApplication.runningApplications(withBundleIdentifier: "dev.layoutpilot.mac")
        guard matches.count == 1, let app = matches.first, !app.isTerminated,
              app.executableURL?.standardizedFileURL == expectedExecutable,
              let defaults = UserDefaults(suiteName: "dev.layoutpilot.mac") else { exit(3) }
        let pid = app.processIdentifier
        var checks: [String: Bool] = [:]
        let fixtures = root.appendingPathComponent(".build/settings-fixtures")
        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: false).appendingPathComponent("LayoutPilot", isDirectory: true)
        func exactOwnCopy(_ path: String, folder: String, fixture: String) throws -> Bool {
            guard !path.isEmpty else { return false }
            let expected = try Data(contentsOf: fixtures.appendingPathComponent(fixture))
            let url = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL
            let ownFolder = directory.appendingPathComponent(folder).resolvingSymlinksInPath().standardizedFileURL
            guard url.deletingLastPathComponent() == ownFolder,
                  UUID(uuidString: url.deletingPathExtension().lastPathComponent) != nil,
                  let fileSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                  fileSize == expected.count else { return false }
            let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
            return try file.read(upToCount: expected.count + 1) == expected
        }
        if mode == "header-png" || mode == "header-tiff" {
            let format = mode == "header-png" ? "png":"tiff"
            let path = defaults.string(forKey: "headerImagePath") ?? ""
            checks["ownedCopyMatchesSyntheticFixture"] = try exactOwnCopy(path, folder:"HeaderImages", fixture:"LP-F19-drop.\(format)")
        } else if mode == "header-reset" {
            checks["headerSelectionEmpty"] = (defaults.string(forKey:"headerImagePath") ?? "").isEmpty
        } else if mode == "sound" {
            checks["ownedCopyMatchesSyntheticFixture"] = try exactOwnCopy(defaults.string(forKey:"customSoundPath") ?? "", folder:"Sounds", fixture:"LP-F08-soft.wav")
            let settings = defaults.data(forKey:"settings.v1").flatMap { try? JSONSerialization.jsonObject(with:$0) as? [String:Any] }
            checks["soundEnabled"] = settings?["sound"] as? Bool == true
        } else if mode == "sound-reset" {
            checks["customSoundSelectionEmpty"] = (defaults.string(forKey:"customSoundPath") ?? "").isEmpty
        }
        var counts: [String:Int64] = [:]
        if let data = defaults.data(forKey:"statistics.v1"), let statistics = try? JSONDecoder().decode(UsageStatistics.self,from:data) {
            counts = Dictionary(uniqueKeysWithValues: UsageCategory.allCases.map { ($0.rawValue,statistics[$0]) })
            checks["statisticsDecoded"] = true
        } else if mode == "statistics" { checks["statisticsDecoded"] = false }
        checks["sameOwnProcessStillRunning"] = !app.isTerminated && app.processIdentifier == pid &&
            NSRunningApplication.runningApplications(withBundleIdentifier:"dev.layoutpilot.mac").count == 1
        let result: [String:Any] = ["kind":"own-app-read-only-artifact-readback","mode":mode,"checks":checks,
            "passed":checks.values.allSatisfy { $0 },"counts":counts,"uiObserved":false,"nativeDropVerified":false,
            "audibilityVerified":false,"eventsPosted":0,"guiActivated":false,"clipboardRead":false,
            "preferencesWritten":false,"privatePathsOrContentsLogged":false]
        let data = try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys])
        print(String(decoding:data,as:UTF8.self))
        if !checks.values.allSatisfy({ $0 }) { exit(1) }
    }
}
