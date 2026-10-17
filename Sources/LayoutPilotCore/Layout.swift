import Foundation

public enum Language: String, Codable, Sendable { case english, russian }

public enum Layout {
    // Independently authored standard US / Russian physical-key correspondence.
    private static let latin = Array("`qwertyuiop[]asdfghjkl;'zxcvbnm,./~QWERTYUIOP{}ASDFGHJKL:\"ZXCVBNM<>?")
    private static let cyrillic = Array("ёйцукенгшщзхъфывапролджэячсмитьбю.ЁЙЦУКЕНГШЩЗХЪФЫВАПРОЛДЖЭЯЧСМИТЬБЮ,")
    private static let toRussian = Dictionary(uniqueKeysWithValues: zip(latin, cyrillic))
    private static let toEnglish = Dictionary(uniqueKeysWithValues: zip(cyrillic, latin))

    public static func language(of text: String) -> Language? {
        let ru = text.unicodeScalars.filter { (0x410...0x44f).contains($0.value) || $0 == "ё" || $0 == "Ё" }.count
        let en = text.unicodeScalars.filter { (65...90).contains($0.value) || (97...122).contains($0.value) }.count
        if ru == 0 && en == 0 { return nil }
        return ru > en ? .russian : .english
    }

    public static func convert(_ text: String, to target: Language? = nil) -> String {
        let direction = target ?? (language(of: text) == .russian ? .english : .russian)
        let table = direction == .russian ? toRussian : toEnglish
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
