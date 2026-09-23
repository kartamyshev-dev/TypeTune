import Foundation
import Testing
@testable import TypeTuneSupport

struct SettingsTests {
    @Test func persistenceAndConflict() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SettingsStore(url: directory.appendingPathComponent("settings.json"))
        var value = try store.load()
        #expect(value.version == 2)
        #expect(!value.autostart)
        #expect(value.compatibility)
        #expect(value.autoSwitching)
        #expect(value.switchOnlyLastWord)
        #expect(!value.dontSwitchWords)
        #expect(value.dontCorrectAfterLayoutChange)
        #expect(value.displayLayoutFlag)
        #expect(!value.playSwitchingSound)
        #expect(value.activeKeyboards == ["com.apple.keylayout.ABC", "com.apple.keylayout.RussianWin"])
        value.learned = ["github"]; value.autoSwitching = false
        let saved = try store.save(value, expected: 0)
        #expect(saved.generation == 1)
        #expect(try store.load() == saved)
        #expect(throws: SettingsError.self) { try store.save(value, expected: 0) }
        #expect(try store.load() == saved)
    }

    @Test func migratesVersionOneToVersionTwo() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("settings.json")
        let v1: [String: Any] = [
            "version": 1,
            "generation": 3,
            "compatibility": true,
            "automatic": false,
            "autostart": true,
            "words": ["привет"],
            "exclusions": ["github"],
            "applications": ["com.apple.Terminal"],
        ]
        try JSONSerialization.data(withJSONObject: v1).write(to: file)
        let loaded = try SettingsStore(url: file).load()
        #expect(loaded.version == 2)
        #expect(loaded.generation == 3)
        #expect(loaded.compatibility)
        #expect(!loaded.autoSwitching)
        #expect(loaded.autostart)
        #expect(loaded.learned == ["привет"])
        #expect(loaded.exclusions == ["github"])
        #expect(loaded.autoDisabledIn == ["com.apple.Terminal"])
        #expect(loaded.activeKeyboards == ["com.apple.keylayout.ABC", "com.apple.keylayout.RussianWin"])
        #expect(loaded.manualSwitching)
        #expect(loaded.switchOnlyLastWord)
        #expect(!loaded.dontSwitchWords)
        #expect(loaded.dontCorrectAfterLayoutChange)
        #expect(loaded.displayLayoutFlag)
        #expect(!loaded.playSwitchingSound)
    }

    @Test func rejectsMutualExclusionAndAcceptsUIHelpers() throws {
        var value = Settings()
        value.switchOnlyLastWord = true
        value.dontSwitchWords = true
        #expect(throws: SettingsError.mutualExclusion) { try value.validate() }

        let onlyLast = Settings().togglingSwitchOnlyLastWord(true)
        #expect(onlyLast.switchOnlyLastWord && !onlyLast.dontSwitchWords)
        try onlyLast.validate()

        let noWords = Settings().togglingDontSwitchWords(true)
        #expect(noWords.dontSwitchWords && !noWords.switchOnlyLastWord)
        try noWords.validate()

        // Turning the partner on auto-unchecks the previous exclusive choice.
        let flipped = noWords.togglingSwitchOnlyLastWord(true)
        #expect(flipped.switchOnlyLastWord && !flipped.dontSwitchWords)
    }

    @Test func learnedHelpersCapAndNormalize() throws {
        var value = Settings()
        value = value.addingLearned("GitHub")
        value = value.addingLearned("github")
        #expect(value.learned == ["github"])
        value = value.addingLearned("привет")
        #expect(value.learned == ["github", "привет"])
        #expect(value.clearingLearned().learned.isEmpty)
        #expect(Settings().addingLearned("a").learned.isEmpty)
    }

    @Test func invalidWordsAndCorruption() throws {
        var value = Settings(); value.learned = ["aб"]
        #expect(throws: SettingsError.self) { try value.validate() }
        value = Settings(); value.dontSwitchWords = true; value.switchOnlyLastWord = true
        #expect(throws: SettingsError.self) { try value.validate() }
        value = Settings(); value.activeKeyboards = ["bad id"]
        #expect(throws: SettingsError.self) { try value.validate() }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("broken".utf8).write(to: file)
        #expect(throws: (any Error).self) { try SettingsStore(url: file).load() }
    }
}
