import Foundation

/// Complete whitespace-delimited token at the caret; coordinates are AX UTF-16.
public enum EditorWord {
    /// Editors may render a physical Space as NBSP, notably contenteditable.
    /// These delimiters are preserved verbatim; other whitespace is a boundary.
    public static func isSupportedSpace(_ character: Character) -> Bool {
        character == " " || character == "\u{00A0}"
    }

    public static func beforeCaret(in value: String, selection: NSRange) -> String? {
        guard selection.length == 0, let range=Range(selection,in:value) else {return nil}
        let prefix=value[..<range.lowerBound]
        if prefix.last.map(isSupportedSpace) != true, let next=value[range.upperBound...].first, !next.isWhitespace {return nil}
        let tokenEnd=prefix.lastIndex(where:{!isSupportedSpace($0)}).map{prefix.index(after:$0)} ?? prefix.startIndex
        let wordPrefix=prefix[..<tokenEnd]
        let start=wordPrefix.lastIndex(where:{$0.isWhitespace}).map{wordPrefix.index(after:$0)} ?? wordPrefix.startIndex
        let word=String(prefix[start...])
        guard start != tokenEnd, word.count<=128 else {return nil}
        return word
    }
    public static func matches(_ before: String, in value: String, selection: NSRange) -> Bool {
        guard let word = beforeCaret(in: value, selection: selection) else { return false }
        // Spaces are part of the edit, not ignorable padding. A missing Space
        // means AX has not observed the trigger yet; an extra Space is new input.
        return !before.isEmpty && before == word
    }

    /// Validate and calculate every UTF-16 coordinate before emitting any key.
    public static func prepare(before: String, replacement: String, in value: String,
                               selection: NSRange) -> ValidatedTextEdit? {
        guard matches(before, in: value, selection: selection),
              !replacement.isEmpty, !replacement.contains("\0"),
              before.count <= 128, replacement.count <= 128,
              selection.location >= before.utf16.count else { return nil }
        let range = NSRange(location: selection.location - before.utf16.count,
                            length: before.utf16.count)
        guard let nativeRange = Range(range, in: value), String(value[nativeRange]) == before else { return nil }
        return ValidatedTextEdit(range: range,
            expected: value.replacingCharacters(in: nativeRange, with: replacement),
            caret: range.location + replacement.utf16.count)
    }
}

public struct ValidatedTextEdit: Equatable {
    public let range: NSRange
    public let expected: String
    public let caret: Int
}
