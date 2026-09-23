import Foundation

public struct Settings: Codable, Equatable {
    public var version = 2
    public var generation: UInt64 = 0
    public var compatibility = true
    public var autoSwitching = true
    public var manualSwitching = true
    public var switchOnlyLastWord = true
    public var dontSwitchWords = false
    public var dontCorrectAfterLayoutChange = true
    public var displayLayoutFlag = true
    public var playSwitchingSound = false
    public var autostart = false
    public var autoDisabledIn: [String] = []
    public var activeKeyboards: [String] = ["com.apple.keylayout.ABC", "com.apple.keylayout.RussianWin"]
    public var learned: [String] = []
    public var exclusions: [String] = []
    public init() {}

    /// UI auto-unchecks the mutually exclusive partner.
    public func togglingSwitchOnlyLastWord(_ on: Bool) -> Settings {
        var next = self
        next.switchOnlyLastWord = on
        if on { next.dontSwitchWords = false }
        return next
    }
    public func togglingDontSwitchWords(_ on: Bool) -> Settings {
        var next = self
        next.dontSwitchWords = on
        if on { next.switchOnlyLastWord = false }
        return next
    }
    public func addingLearned(_ raw: String) -> Settings {
        let word = raw.lowercased()
        var next = self
        guard (2...32).contains(word.count), !next.learned.contains(word) else { return self }
        next.learned = (next.learned + [word]).sorted()
        return next
    }
    public func clearingLearned() -> Settings {
        var next = self
        next.learned = []
        return next
    }

    public func validate() throws {
        guard version == 2, learned.count <= 500, exclusions.count <= 500, autoDisabledIn.count <= 500, activeKeyboards.count <= 16 else { throw SettingsError.invalid }
        guard !(switchOnlyLastWord && dontSwitchWords) else { throw SettingsError.mutualExclusion }
        for word in learned + exclusions {
            guard (2...32).contains(word.count), word == word.lowercased(),
                  word.unicodeScalars.allSatisfy({ (97...122).contains($0.value) }) || word.unicodeScalars.allSatisfy({ (1072...1103).contains($0.value) || $0.value == 1105 }) else { throw SettingsError.invalid }
        }
        guard Set(learned).count == learned.count, Set(exclusions).count == exclusions.count else { throw SettingsError.invalid }
        guard autoDisabledIn.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 255 && !$0.contains(where: { $0.isWhitespace }) }),
              Set(autoDisabledIn).count == autoDisabledIn.count else { throw SettingsError.invalid }
        guard activeKeyboards.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 255 && !$0.contains(where: { $0.isWhitespace }) }),
              Set(activeKeyboards).count == activeKeyboards.count else { throw SettingsError.invalid }
    }

    /// v1→v2: automatic→autoSwitching, applications→autoDisabledIn, words→learned.
    public static func migrateJSON(_ raw: [String: Any]) throws -> [String: Any] {
        let version = (raw["version"] as? Int) ?? 1
        var out: [String: Any]
        switch version {
        case 1:
            out = [:]
            out["version"] = 2
            out["generation"] = raw["generation"] ?? 0
            out["compatibility"] = raw["compatibility"] ?? false
            out["autoSwitching"] = raw["automatic"] ?? true
            out["manualSwitching"] = true
            out["switchOnlyLastWord"] = true
            out["dontSwitchWords"] = false
            out["dontCorrectAfterLayoutChange"] = true
            out["displayLayoutFlag"] = true
            out["playSwitchingSound"] = false
            out["autostart"] = raw["autostart"] ?? false
            out["autoDisabledIn"] = raw["applications"] ?? []
            out["activeKeyboards"] = ["com.apple.keylayout.ABC", "com.apple.keylayout.RussianWin"]
            out["learned"] = raw["words"] ?? []
            out["exclusions"] = raw["exclusions"] ?? []
        case 2:
            out = raw
            out["version"] = 2
        default:
            throw SettingsError.invalid
        }
        let defaults: [String: Any] = [
            "generation": 0,
            "compatibility": true,
            "autoSwitching": true,
            "manualSwitching": true,
            "switchOnlyLastWord": true,
            "dontSwitchWords": false,
            "dontCorrectAfterLayoutChange": true,
            "displayLayoutFlag": true,
            "playSwitchingSound": false,
            "autostart": false,
            "autoDisabledIn": [String](),
            "activeKeyboards": ["com.apple.keylayout.ABC", "com.apple.keylayout.RussianWin"],
            "learned": [String](),
            "exclusions": [String](),
        ]
        for (key, value) in defaults where out[key] == nil {
            out[key] = value
        }
        return out
    }
}

public enum SettingsError: Error, LocalizedError {
    case invalid, conflict, tooLarge, mutualExclusion
    public var errorDescription: String? {
        switch self {
        case .invalid: return "Неверные настройки. Слова: 2–32 буквы одного языка; приложения: bundle ID; раскладки: TIS ID."
        case .conflict: return "Настройки изменились. Откройте окно заново."
        case .tooLarge: return "Файл настроек слишком большой."
        case .mutualExclusion: return "Нельзя одновременно: «Переключать только последнее слово» и «Не переключать слова»."
        }
    }
}

public final class SettingsStore {
    public let url: URL
    public init(url: URL) { self.url = url }
    public func load() throws -> Settings {
        guard FileManager.default.fileExists(atPath: url.path) else { return Settings() }
        let data = try Data(contentsOf: url)
        guard data.count <= 131072 else { throw SettingsError.tooLarge }
        guard let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw SettingsError.invalid }
        let migrated = try Settings.migrateJSON(raw)
        guard let normalized = try? JSONSerialization.data(withJSONObject: migrated) else { throw SettingsError.invalid }
        let settings = try JSONDecoder().decode(Settings.self, from: normalized)
        try settings.validate(); return settings
    }
    public func save(_ proposed: Settings, expected: UInt64) throws -> Settings {
        try proposed.validate()
        guard try load().generation == expected, expected < UInt64.max else { throw SettingsError.conflict }
        var next = proposed; next.generation = expected + 1; next.version = 2
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(next).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return next
    }
}
