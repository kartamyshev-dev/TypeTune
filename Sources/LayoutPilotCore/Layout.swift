import Foundation

public enum Language: String, Codable, Sendable { case english, russian }

public enum Layout {
    /// Physical-key correspondence: each pair is what one key (with or without Shift)
    /// produces in the English and in the Russian layout. Keys that produce the same
    /// character in both layouts (digits, `-`, `!` …) are omitted and stay unchanged.
    public struct Mapping: Equatable, Sendable {
        public let toRussian: [Character: Character]
        public let toEnglish: [Character: Character]

        /// nil when a character occurs in two pairs on either side: conversion
        /// must stay reversible key by key.
        public init?(pairs: [(latin: Character, cyrillic: Character)]) {
            var toRussian: [Character: Character] = [:], toEnglish: [Character: Character] = [:]
            for pair in pairs {
                guard pair.latin != pair.cyrillic, toRussian[pair.latin] == nil, toEnglish[pair.cyrillic] == nil else { return nil }
                toRussian[pair.latin] = pair.cyrillic; toEnglish[pair.cyrillic] = pair.latin
            }
            self.toRussian = toRussian; self.toEnglish = toEnglish
        }

        /// A table decoded from installed layouts: every Latin and Cyrillic letter must
        /// have a key, otherwise the caller keeps the authored standard table.
        public static func keyboard(pairs: [(latin: Character, cyrillic: Character)]) -> Mapping? {
            guard let mapping = Mapping(pairs: pairs), mapping.coversAllLetters else { return nil }
            return mapping
        }
        /// Builds a table from what each physical key (and Shift+key) types in the
        /// English and the Russian layout, in key order. Keys equal in both layouts,
        /// multi-character output and characters already claimed by an earlier key
        /// (for example the ISO § key duplicating `) are skipped.
        public static func decoded(keys: [(english: String?, russian: String?)]) -> Mapping? {
            var pairs: [(latin: Character, cyrillic: Character)] = []
            var latinUsed = Set<Character>(), cyrillicUsed = Set<Character>()
            for key in keys {
                guard let english = key.english, let russian = key.russian, english.count == 1, russian.count == 1,
                      let latin = english.first, let cyrillic = russian.first, latin != cyrillic,
                      !latinUsed.contains(latin), !cyrillicUsed.contains(cyrillic) else { continue }
                latinUsed.insert(latin); cyrillicUsed.insert(cyrillic)
                pairs.append((latin, cyrillic))
            }
            return keyboard(pairs: pairs)
        }
        public var coversAllLetters: Bool {
            let latin = "abcdefghijklmnopqrstuvwxyz", cyrillic = "абвгдеёжзийклмнопрстуфхцчшщъыьэюя"
            return (latin + latin.uppercased()).allSatisfy { toRussian[$0] != nil } &&
                (cyrillic + cyrillic.uppercased()).allSatisfy { toEnglish[$0] != nil }
        }

        // Independently authored standard US / Russian PC (Windows) layouts.
        public static let standardPC: Mapping = {
            let latin = Array("`qwertyuiop[]asdfghjkl;'zxcvbnm,./~QWERTYUIOP{}ASDFGHJKL:\"ZXCVBNM<>?@#$^&|")
            let cyrillic = Array("ёйцукенгшщзхъфывапролджэячсмитьбю.ЁЙЦУКЕНГШЩЗХЪФЫВАПРОЛДЖЭЯЧСМИТЬБЮ,\"№;:?/")
            precondition(latin.count == cyrillic.count)
            return Mapping(pairs: zip(latin, cyrillic).map { (latin: $0, cyrillic: $1) })!
        }()
    }

    public static func language(of text: String) -> Language? {
        let ru = text.unicodeScalars.filter { (0x410...0x44f).contains($0.value) || $0 == "ё" || $0 == "Ё" }.count
        let en = text.unicodeScalars.filter { (65...90).contains($0.value) || (97...122).contains($0.value) }.count
        if ru == 0 && en == 0 { return nil }
        return ru > en ? .russian : .english
    }

    public static func convert(_ text: String, to target: Language? = nil, mapping: Mapping = .standardPC) -> String {
        let direction = target ?? (language(of: text) == .russian ? .english : .russian)
        let table = direction == .russian ? mapping.toRussian : mapping.toEnglish
        return String(text.map { table[$0] ?? $0 })
    }

    public static func matchingCase(_ replacement: String, source: String) -> String {
        if source == source.uppercased() && source != source.lowercased() { return replacement.uppercased() }
        if source.first?.isUppercase == true && source.dropFirst() == source.dropFirst().lowercased() {
            return replacement.prefix(1).uppercased() + replacement.dropFirst()
        }
        return replacement
    }

    public static func isMixed(_ word: String) -> Bool {
        word.contains(where: { $0.isASCII && $0.isLetter }) && word.unicodeScalars.contains(where: { (0x410...0x44f).contains($0.value) || $0 == "ё" || $0 == "Ё" })
    }
}
