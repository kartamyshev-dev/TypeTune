import AppKit
import Foundation
import LayoutPilotCore

/// Optional independent vocabulary provider, not reconstructed Caramba data.
/// Calls only explicit-language spelling APIs; no global language, learning or settings writes.
@MainActor
final class SystemVocabulary {
    private struct Key: Hashable { var language: String; var word: String }
    private struct Entry { var accepted: Bool; var guesses: [String]? }
    private let checker = NSSpellChecker.shared
    private let documentTag = NSSpellChecker.uniqueSpellDocumentTag()
    private var languages: [Language: String] = [:]
    private var cache: [Key: Entry] = [:]
    private var slots: [Key] = []
    private var eviction = 0
    private(set) var spellQueries = 0
    private(set) var guessQueries = 0
    let capacity = 4096
    var isAvailable: Bool { languages[.english] != nil && languages[.russian] != nil }
    var statusInfo: String {
        if !isAvailable { return "Системный словарь недоступен для RU/EN; используется встроенный словарь" }
        return "Системный словарь RU/EN: \(languages[.russian]!), \(languages[.english]!); кэш \(cache.count)/\(capacity), только в памяти"
    }
    init() {
        let available = checker.availableLanguages
        languages[.english] = available.first(where: { $0 == "en_US" || $0 == "en-US" }) ?? available.first(where: Self.isEnglish)
        languages[.russian] = available.first(where: Self.isRussian)
    }
    deinit { checker.closeSpellDocument(withTag: documentTag) }
    private static func isEnglish(_ value: String) -> Bool { value == "en" || value.hasPrefix("en_") || value.hasPrefix("en-") }
    private static func isRussian(_ value: String) -> Bool { value == "ru" || value.hasPrefix("ru_") || value.hasPrefix("ru-") }
    private static func pureLanguage(_ value: String) -> Language? {
        guard !value.isEmpty else { return nil }
        if value.unicodeScalars.allSatisfy({ (97...122).contains($0.value) || (65...90).contains($0.value) }) { return .english }
        if value.unicodeScalars.allSatisfy({ (0x410...0x44f).contains($0.value) || $0 == "ё" || $0 == "Ё" }) { return .russian }
        return nil
    }
    private func store(_ entry: Entry, for key: Key) {
        if cache[key] != nil { cache[key] = entry; return }
        if slots.count < capacity { slots.append(key) }
        else { cache.removeValue(forKey: slots[eviction]); slots[eviction] = key; eviction = (eviction + 1) % capacity }
        cache[key] = entry
    }
    private func spelling(_ word: String, language: Language) -> Bool {
        guard let name = languages[language] else { return false }
        let key = Key(language: name, word: word.lowercased())
        if let entry = cache[key] { return entry.accepted }
        spellQueries += 1
        var count = 0
        let miss = checker.checkSpelling(of: key.word, startingAt: 0, language: name, wrap: false,
                                        inSpellDocumentWithTag: documentTag, wordCount: &count)
        let accepted = miss.location == NSNotFound && count == 1
        store(Entry(accepted: accepted, guesses: nil), for: key)
        return accepted
    }
    private func guesses(_ word: String, language: Language) -> [String] {
        guard let name = languages[language] else { return [] }
        let key = Key(language: name, word: word)
        if let values = cache[key]?.guesses { return values }
        guessQueries += 1
        let values = checker.guesses(forWordRange: NSRange(location: 0, length: word.utf16.count), in: word,
                                    language: name, inSpellDocumentWithTag: documentTag) ?? []
        // Bound work after the synchronous OS request; never select from a truncated list.
        let bounded = values.count <= 128 ? values : []
        store(Entry(accepted: cache[key]?.accepted ?? false, guesses: bounded), for: key)
        return bounded
    }
    /// Restricted Damerau/Levenshtein distance exactly one: insertion/deletion/substitution/adjacent transposition.
    private static func oneEdit(_ a: String, _ b: String) -> Bool {
        let x = Array(a), y = Array(b)
        guard abs(x.count - y.count) <= 1, x != y else { return false }
        if x.count == y.count {
            let changed = x.indices.filter { x[$0] != y[$0] }
            if changed.count == 1 { return true }
            return changed.count == 2 && changed[1] == changed[0] + 1 && x[changed[0]] == y[changed[1]] && x[changed[1]] == y[changed[0]]
        }
        let short = x.count < y.count ? x : y, long = x.count < y.count ? y : x
        var i = 0, j = 0, edits = 0
        while i < short.count && j < long.count {
            if short[i] == long[j] { i += 1; j += 1 }
            else { edits += 1; j += 1; if edits > 1 { return false } }
        }
        return edits + long.count - j == 1
    }
    /// Whether macOS accepts the whole token as a word of its own single script.
    func accepts(_ word: String) -> Bool {
        guard isAvailable, (1...40).contains(word.count), let language = Self.pureLanguage(word) else { return false }
        return spelling(word, language: language)
    }
    func decision(_ word: String, settings: Settings, context: InputContext = InputContext()) -> Decision? {
        let base = Engine(settings: settings)
        if let decision = base.decide(word, context: context) { return decision }
        guard isAvailable, settings.automatic || settings.typos || settings.yo,
              !context.secure, context.reliable, !settings.excludedApps.contains(context.application),
              (3...40).contains(word.count), word.utf16.count <= 80, !Layout.isMixed(word) else { return nil }
        let lower = word.lowercased()
        guard !settings.excludes(word) else { return nil }
        let converted = Layout.convert(word)
        let sourceLanguage = Self.pureLanguage(word)
        let targetLanguage = Self.pureLanguage(converted)
        // Permit physical punctuation only when the entire alternate token is RU/EN letters.
        guard sourceLanguage != nil || targetLanguage != nil else { return nil }
        var lexicon = Lexicon.bundled
        func add(_ token: String, _ language: Language) {
            if language == .english { lexicon.english.insert(token.lowercased()) }
            else { lexicon.russian.insert(token.lowercased()) }
        }
        var sourceAccepted = false
        if let language = sourceLanguage {
            sourceAccepted = spelling(word, language: language)
            if sourceAccepted { add(word, language) }
        }
        if settings.automatic, let language = targetLanguage, spelling(converted, language: language) { add(converted, language) }
        if let decision = Engine(settings: settings, lexicon: lexicon).decide(word, context: context) { return decision }
        if settings.typos, !sourceAccepted, let language = sourceLanguage,
           word.count >= 5, word == lower {
            let candidates = Set(guesses(lower, language: language).filter { value in
                (3...40).contains(value.count) && Self.pureLanguage(value) == language && Self.oneEdit(lower, value.lowercased())
            })
            // Count close alternatives before rejecting capitalization/ё guesses: removing an unsafe
            // alternative must not turn an ambiguous set into an apparently unique correction.
            if candidates.count == 1, let candidate = candidates.first,
               candidate == candidate.lowercased(), !candidate.contains("ё"), spelling(candidate, language: language) {
                lexicon.typos[lower] = candidate
            }
        }
        return Engine(settings: settings, lexicon: lexicon).decide(word, context: context)
    }
}
