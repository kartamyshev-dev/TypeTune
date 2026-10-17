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
