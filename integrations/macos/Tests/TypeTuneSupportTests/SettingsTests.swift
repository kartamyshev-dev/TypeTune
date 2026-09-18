import Foundation
import Testing
@testable import TypeTuneSupport
struct SettingsTests {
    @Test func persistenceAndConflict() throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:directory)}
        let store=SettingsStore(url:directory.appendingPathComponent("settings.json"))
        var value=try store.load()
        #expect(!value.compatibility && !value.autostart)
        value.words=["github"];value.compatibility=true
        let saved=try store.save(value,expected:0)
        #expect(saved.generation==1)
        #expect(try store.load()==saved)
        #expect(throws:SettingsError.self){try store.save(value,expected:0)}
        #expect(try store.load()==saved)
    }
    @Test func invalidWordsAndCorruption() throws {
        var value=Settings();value.words=["aб"]
        #expect(throws:SettingsError.self){try value.validate()}
        let file=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:file)}
        try Data("broken".utf8).write(to:file)
        #expect(throws:(any Error).self){try SettingsStore(url:file).load()}
    }
}
