import Foundation

public struct Settings: Codable, Equatable {
    public var version = 1
    public var generation: UInt64 = 0
    public var compatibility = false
    public var automatic = true
    public var autostart = false
    public var words: [String] = []
    public var exclusions: [String] = []
    public var applications: [String] = []
    public init() {}
    public func validate() throws {
        guard version == 1, words.count <= 500, exclusions.count <= 500, applications.count <= 500 else { throw SettingsError.invalid }
        for word in words + exclusions {
            guard (2...32).contains(word.count), word == word.lowercased(),
                  word.unicodeScalars.allSatisfy({ (97...122).contains($0.value) }) || word.unicodeScalars.allSatisfy({ (1072...1103).contains($0.value) || $0.value == 1105 }) else { throw SettingsError.invalid }
        }
        guard applications.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 255 && !$0.contains(where: { $0.isWhitespace }) }), Set(words).count == words.count, Set(exclusions).count == exclusions.count else { throw SettingsError.invalid }
    }
}
public enum SettingsError: Error, LocalizedError {
    case invalid, conflict, tooLarge
    public var errorDescription: String? {
        switch self {
        case .invalid: return "Неверные настройки. Слова: 2–32 буквы одного языка; приложения: bundle ID."
        case .conflict: return "Настройки изменились. Откройте окно заново."
        case .tooLarge: return "Файл настроек слишком большой."
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
        let settings = try JSONDecoder().decode(Settings.self, from: data)
        try settings.validate(); return settings
    }
    public func save(_ proposed: Settings, expected: UInt64) throws -> Settings {
        try proposed.validate()
        guard try load().generation == expected, expected < UInt64.max else { throw SettingsError.conflict }
        var next = proposed; next.generation = expected + 1
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(next).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return next
    }
}

