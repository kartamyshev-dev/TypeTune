import Foundation

/// A user abbreviation replaced by text in any application (docs/SNIPPETS_PLAN.md).
/// `text` is a template: `{{…}}` variables are expanded when the snippet fires and
/// `\{{` stands for a literal `{{` (SnippetTemplate, stage S2).
public struct Snippet: Codable, Equatable, Identifiable, Sendable {
    /// When the abbreviation fires.
    public enum Trigger: String, Codable, Sendable {
        /// Right after its last character is typed.
        case immediate
        /// When whitespace (Space, Return, Tab) completes it as a whole token.
        case boundary
    }

    public var id: UUID
    public var abbreviation: String
    public var text: String
    public var trigger: Trigger
    /// The abbreviation also fires when typed on the same keys in the other layout.
    public var otherLayout: Bool
    /// `Спс` → «Спасибо», `СПС` → «СПАСИБО».
    public var matchCase: Bool
    public var applications: ApplicationFilter
    public var enabled: Bool

    public init(id: UUID = UUID(), abbreviation: String, text: String, trigger: Trigger? = nil,
                otherLayout: Bool = true, matchCase: Bool = true,
                applications: ApplicationFilter = ApplicationFilter(), enabled: Bool = true) {
        self.id = id; self.abbreviation = abbreviation; self.text = text
        self.trigger = trigger ?? Self.defaultTrigger(for: abbreviation)
        self.otherLayout = otherLayout; self.matchCase = matchCase
        self.applications = applications; self.enabled = enabled
    }

    /// DECISIONS п. 28: an abbreviation that starts with a sign (`;адр`) cannot be the
    /// start of an ordinary word and fires at once; a word-like one (`спс`) waits for
    /// the boundary so that `спсб` or `спс-то` stay as typed.
    public static func defaultTrigger(for abbreviation: String) -> Trigger {
        guard let first = abbreviation.first else { return .boundary }
        return first.isLetter || first.isNumber ? .boundary : .immediate
    }

    /// A former literal rule as a snippet with the same behaviour: whole token at the
    /// boundary, typed as is (no other-layout match), case carried over, same id.
    public init(migrating rule: UserRule) {
        self.init(id: rule.id, abbreviation: rule.source, text: SnippetTemplate.escaped(rule.replacement),
                  trigger: .boundary, otherLayout: false, matchCase: true)
    }

    private enum CodingKeys: String, CodingKey {
        case id, abbreviation, text, trigger, otherLayout, matchCase, applications, enabled
    }
    /// Fields added by later versions get defaults, so an older file still loads.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let abbreviation = try values.decode(String.self, forKey: .abbreviation)
        self.init(id: try values.decode(UUID.self, forKey: .id), abbreviation: abbreviation,
                  text: try values.decode(String.self, forKey: .text),
                  trigger: try values.decodeIfPresent(Trigger.self, forKey: .trigger),
                  otherLayout: try values.decodeIfPresent(Bool.self, forKey: .otherLayout) ?? true,
                  matchCase: try values.decodeIfPresent(Bool.self, forKey: .matchCase) ?? true,
                  applications: try values.decodeIfPresent(ApplicationFilter.self, forKey: .applications) ?? ApplicationFilter(),
                  enabled: try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? true)
    }
}

/// Which applications (bundle IDs) a snippet works in.
public struct ApplicationFilter: Codable, Equatable, Sendable {
    public enum Mode: String, Codable, Sendable { case all, only, except }
    public var mode: Mode
    public var applications: [String]

    public init(mode: Mode = .all, applications: [String] = []) {
        self.mode = mode; self.applications = applications
    }
    public func permits(_ applicationID: String) -> Bool {
        switch mode {
        case .all: return true
        case .only: return applications.contains(applicationID)
        case .except: return !applications.contains(applicationID)
        }
    }
}

/// A problem that keeps a snippet from being saved in the editor or used for matching.
public enum SnippetIssue: Equatable, Sendable {
    case abbreviationLength
    /// Whitespace or control characters: the typed buffer splits tokens at whitespace.
    case abbreviationCharacters
    case emptyText
    case textTooLong
    /// Control characters other than line feed and tab cannot be inserted.
    case textCharacters
    /// `{{…}}` that is not a known variable, unclosed, or a second cursor.
    case template(SnippetTemplate.Failure)
    /// The same abbreviation (ignoring case, and on the same keys when either snippet
    /// matches the other layout) already belongs to the snippet with this id.
    case duplicate(of: UUID)
}

/// The stored snippet collection: `snippets.json` in Application Support, separate
/// from the settings in UserDefaults (DECISIONS п. 28).
public struct SnippetLibrary: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public static let abbreviationLength = 2...64
    public static let maximumTextLength = 10_000

    public var version: Int
    public var snippets: [Snippet]

    public init(snippets: [Snippet] = []) {
        self.version = Self.currentVersion; self.snippets = snippets
    }

    public enum LoadError: Error, Equatable {
        /// Written by a newer TypeTune: must not be overwritten by this one.
        case unsupportedVersion(Int)
        case malformed
    }

    /// The outcome of reading storage at launch. `unavailable` blocks every write until
    /// the user decides, as with unreadable settings (`settingsStorageAvailable`).
    public enum LoadResult: Equatable {
        case loaded(SnippetLibrary)
        /// No file yet: the former literal rules become snippets; the caller saves them.
        case migrated(SnippetLibrary)
        case unavailable(LoadError)
    }

    public static func load(fileData: Data?, legacyRules: [UserRule]) -> LoadResult {
        guard let fileData else { return .migrated(SnippetLibrary(snippets: legacyRules.map(Snippet.init(migrating:)))) }
        do { return .loaded(try decode(fileData)) } catch let error as LoadError { return .unavailable(error) }
        catch { return .unavailable(.malformed) }
    }

    public static func decode(_ data: Data) throws -> SnippetLibrary {
        struct Header: Decodable { let version: Int }
        guard let header = try? JSONDecoder().decode(Header.self, from: data) else { throw LoadError.malformed }
        guard header.version <= currentVersion, header.version >= 1 else { throw LoadError.unsupportedVersion(header.version) }
        guard let library = try? JSONDecoder().decode(SnippetLibrary.self, from: data) else { throw LoadError.malformed }
        return library
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    /// Problems of `snippet` as a member of this library (it may already be in it).
    public func issues(for snippet: Snippet, mapping: Layout.Mapping = .standardPC) -> [SnippetIssue] {
        var result: [SnippetIssue] = []
        let abbreviation = snippet.abbreviation
        if !Self.abbreviationLength.contains(abbreviation.count) { result.append(.abbreviationLength) }
        if abbreviation.unicodeScalars.contains(where: {
            CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0)
        }) { result.append(.abbreviationCharacters) }
        if snippet.text.isEmpty { result.append(.emptyText) }
        if snippet.text.count > Self.maximumTextLength { result.append(.textTooLong) }
        if snippet.text.unicodeScalars.contains(where: {
            CharacterSet.controlCharacters.contains($0) && $0 != "\n" && $0 != "\t"
        }) { result.append(.textCharacters) }
        if case .failure(let failure) = SnippetTemplate.parse(snippet.text) { result.append(.template(failure)) }
        if let other = snippets.first(where: { $0.id != snippet.id && Self.collide($0, snippet, mapping: mapping) }) {
            result.append(.duplicate(of: other.id))
        }
        return result
    }

    /// Snippets that can fire: enabled and without issues. Of two colliding ones only
    /// the earlier stays usable, so a hand-edited file cannot make matching ambiguous.
    public func usable(mapping: Layout.Mapping = .standardPC) -> [Snippet] {
        var kept: [Snippet] = []
        for snippet in snippets where snippet.enabled {
            let alone = SnippetLibrary(snippets: kept)
            if alone.issues(for: snippet, mapping: mapping).isEmpty { kept.append(snippet) }
        }
        return kept
    }

    /// Whether two abbreviations would fire on the same typed text.
    static func collide(_ a: Snippet, _ b: Snippet, mapping: Layout.Mapping) -> Bool {
        let x = a.abbreviation.lowercased(), y = b.abbreviation.lowercased()
        if x == y { return true }
        guard a.otherLayout || b.otherLayout else { return false }
        return x == Layout.convert(y, to: .english, mapping: mapping).lowercased() ||
            x == Layout.convert(y, to: .russian, mapping: mapping).lowercased()
    }
}

public extension SnippetLibrary {
    /// Former literal rules for the per-application path (universal mode off), which does not
    /// know snippets: usable whole-word snippets without variables or line breaks that work in
    /// every application. Keeps each snippet's id. Universal mode ignores `Settings.rules` and
    /// uses the library itself, so a deleted or restricted snippet never fires through a rule.
    func legacyRules(mapping: Layout.Mapping = .standardPC) -> [UserRule] {
        usable(mapping: mapping).compactMap { snippet in
            guard snippet.trigger == .boundary, snippet.applications.mode == .all,
                  let text = SnippetTemplate.literal(snippet.text), !text.contains(where: \.isNewline) else { return nil }
            var rule = UserRule(source: snippet.abbreviation, replacement: text)
            rule.id = snippet.id
            return rule
        }
    }
}

