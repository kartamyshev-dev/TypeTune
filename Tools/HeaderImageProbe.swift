import AppKit
import Foundation
import ImageIO
import LayoutPilotCore

private struct ProbeFailure: Error { let reason: String }
@main private struct HeaderImageProbe {
    static func main() {
        let suiteName = "dev.layoutpilot.headerimage-probe.\(UUID().uuidString)"
        let fixture = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/settings-fixtures/header.png")
        var report: [String: Any] = ["kind": "standalone-real-Store-runtime", "uiUsed": false,
            "accessibilityUsed": false, "keyboardEventsPosted": false, "standardDefaultsUsed": false,
            "originalCarambaAccessed": false, "nativeAppAcceptance": false]
        var checks: [[String: Any]] = []
        var created = Set<URL>()
        var existing = Set<URL>()
        var defaults: UserDefaults?
        var ownDirectory: URL?
        var temporaryDirectory: URL?
        func check(_ value: Bool, _ id: String) { checks.append(["id": id, "passed": value]) }
        func require(_ value: @autoclosure () -> Bool, _ reason: String) throws {
            if !value() { throw ProbeFailure(reason: reason) }
        }
        func registerNewCopy(_ store: Store) throws -> URL {
            guard let ownDirectory else { throw ProbeFailure(reason: "own_directory_not_initialized") }
            let url = URL(fileURLWithPath: store.headerImagePath).standardizedFileURL
            try require(url.deletingLastPathComponent() == ownDirectory, "copy_not_in_owned_directory")
            try require(UUID(uuidString: url.deletingPathExtension().lastPathComponent) != nil, "copy_not_uuid_named")
            try require(!existing.contains(url) && FileManager.default.fileExists(atPath: url.path), "copy_not_newly_created")
            created.insert(url)
            return url
        }
        do {
            try require(CommandLine.arguments.count == 1, "no_arguments_supported")
            guard let isolated = UserDefaults(suiteName: suiteName) else { throw ProbeFailure(reason: "isolated_defaults_unavailable") }
            defaults = isolated
            try require(isolated.persistentDomain(forName: suiteName) == nil, "isolated_defaults_already_exist")
            let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: false).appendingPathComponent("LayoutPilot/HeaderImages", isDirectory: true).standardizedFileURL
            ownDirectory = directory
            existing = Set((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            let fixtureBytes = try Data(contentsOf: fixture)
            try require(!fixtureBytes.isEmpty && fixtureBytes.count < 1024 * 1024, "synthetic_fixture_invalid")
            var settings = Settings()
            settings.automatic = false; settings.sound = true
            settings.appAutomatic = ["com.example.SyntheticHeaderProbe": false]
            settings.excludedWords = ["synthetic-header-word"]
            let encodedSettings = try JSONEncoder().encode(settings)
            isolated.set(encodedSettings, forKey: "settings.v1")
            isolated.set(17, forKey: "corrected")
            let store = Store(defaults: isolated)
            check(store.headerImage == nil && store.headerImagePath.isEmpty, "initial_empty_selection")
            store.importHeaderImage(from: fixture)
            let urlCopy = try registerNewCopy(store)
            check(store.headerImage != nil && store.headerImage?.size == NSSize(width: 128, height: 64), "url_import_decodes_synthetic_128x64")
            check(try Data(contentsOf: urlCopy) == fixtureBytes, "url_import_copies_exact_source_bytes")
            check(try Data(contentsOf: fixture) == fixtureBytes, "url_import_preserves_source")
            check(isolated.string(forKey: "headerImagePath") == urlCopy.path, "url_import_persists_owned_path")
            let restart = Store(defaults: isolated)
            check(restart.headerImagePath == urlCopy.path && restart.headerImage != nil, "restart_restores_valid_owned_image")
            store.importHeaderImage(data: fixtureBytes)
            let dataCopy = try registerNewCopy(store)
            check(dataCopy != urlCopy && store.headerImage != nil, "data_import_creates_independent_owned_copy")
            check(try Data(contentsOf: dataCopy) == fixtureBytes, "data_import_preserves_exact_bytes")
            let previous = store.headerImagePath
            store.importHeaderImage(data: Data("synthetic malformed image".utf8))
            check(store.headerImagePath == previous && store.headerImage != nil, "malformed_data_keeps_previous_selection")
            store.importHeaderImage(data: Data())
            check(store.headerImagePath == previous && store.headerImage != nil, "empty_data_keeps_previous_selection")
            store.importHeaderImage(data: Data(repeating: 0, count: 32 * 1024 * 1024 + 1))
            check(store.headerImagePath == previous && store.headerImage != nil, "over_32MiB_data_keeps_previous_selection")
            store.importHeaderImage(from: URL(string: "https://example.invalid/synthetic-header.png")!)
            check(store.headerImagePath == previous && store.headerImage != nil, "nonfile_url_keeps_previous_selection")
            store.importHeaderImage(from: fixture.deletingLastPathComponent())
            check(store.headerImagePath == previous && store.headerImage != nil, "directory_url_keeps_previous_selection")
            let temporary = fixture.deletingLastPathComponent().appendingPathComponent("header-probe-\(UUID().uuidString)", isDirectory: true)
            try require(!FileManager.default.fileExists(atPath: temporary.path), "temporary_directory_already_exists")
            try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
            temporaryDirectory = temporary
            let oversizedFile = temporary.appendingPathComponent("synthetic-oversize.png")
            try Data().write(to: oversizedFile)
            let handle = try FileHandle(forWritingTo: oversizedFile)
            try handle.truncate(atOffset: UInt64(32 * 1024 * 1024 + 1))
            try handle.close()
            store.importHeaderImage(from: oversizedFile)
            check(store.headerImagePath == previous && store.headerImage != nil && store.lastStatus.contains("32"), "over_32MiB_url_rejected_before_reading_image")
            let imageBytes = NSMutableData()
            guard let context = CGContext(data: nil, width: 8193, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
                  let image = context.makeImage(),
                  let destination = CGImageDestinationCreateWithData(imageBytes, "public.png" as CFString, 1, nil) else {
                throw ProbeFailure(reason: "synthetic_dimension_fixture_unavailable")
            }
            CGImageDestinationAddImage(destination, image, nil)
            try require(CGImageDestinationFinalize(destination), "synthetic_dimension_fixture_encoding_failed")
            store.importHeaderImage(data: imageBytes as Data)
            check(store.headerImagePath == previous && store.headerImage != nil && store.lastStatus.contains("8192"), "valid_png_width8193_rejected_without_losing_previous_selection")
            try FileManager.default.removeItem(at: dataCopy)
            let missing = Store(defaults: isolated)
            check(missing.headerImagePath == dataCopy.path && missing.headerImage == nil, "missing_owned_copy_preserves_path_and_has_no_image")
            isolated.set(fixture.path, forKey: "headerImagePath")
            let outside = Store(defaults: isolated)
            check(outside.headerImagePath == fixture.path && outside.headerImage == nil, "restore_rejects_valid_image_outside_owned_directory")
            isolated.set(urlCopy.path, forKey: "headerImagePath")
            let toReset = Store(defaults: isolated)
            toReset.resetHeaderImage()
            check(toReset.headerImagePath.isEmpty && toReset.headerImage == nil && isolated.string(forKey: "headerImagePath") == "", "reset_clears_image_and_owned_preference")
            check(FileManager.default.fileExists(atPath: urlCopy.path), "reset_does_not_delete_owned_copy")
            check(try Data(contentsOf: fixture) == fixtureBytes, "all_operations_preserve_synthetic_original")
            check(isolated.data(forKey: "settings.v1") == encodedSettings && toReset.settings == settings &&
                isolated.integer(forKey: "corrected") == 17 && toReset.corrected == 17, "header_operations_do_not_change_ordinary_settings_or_statistics")
        } catch {
            report["error"] = (error as? ProbeFailure)?.reason ?? "synthetic_fixture_or_filesystem_error"
            check(false, "probe_completed_without_error")
        }
        var cleanupOK = true
        for url in created where FileManager.default.fileExists(atPath: url.path) {
            do { try FileManager.default.removeItem(at: url) }
            catch { cleanupOK = false }
        }
        check(cleanupOK && created.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) }, "cleanup_removes_only_registered_test_copies")
        if let temporaryDirectory {
            do { try FileManager.default.removeItem(at: temporaryDirectory) }
            catch { cleanupOK = false }
            check(!FileManager.default.fileExists(atPath: temporaryDirectory.path), "cleanup_removes_only_new_synthetic_fixture_directory")
        }
        if let ownDirectory {
            let remaining = Set((try? FileManager.default.contentsOfDirectory(at: ownDirectory, includingPropertiesForKeys: nil)) ?? [])
            check(existing.isSubset(of: remaining), "cleanup_preserves_all_preexisting_owned_paths")
        }
        if let defaults {
            defaults.removePersistentDomain(forName: suiteName)
            let remaining = defaults.persistentDomain(forName: suiteName) ?? [:]
            report["remainingProbePreferenceKeysCount"] = remaining.count
            check(remaining.isEmpty, "cleanup_removes_all_unique_probe_defaults_keys")
        }
        report["checks"] = checks
        report["passedCount"] = checks.filter { ($0["passed"] as? Bool) == true }.count
        report["totalCount"] = checks.count
        let passed = checks.allSatisfy { ($0["passed"] as? Bool) == true }
        report["passed"] = passed
        if let json = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            print(String(decoding: json, as: UTF8.self))
        }
        exit(passed ? 0 : 1)
    }
}
