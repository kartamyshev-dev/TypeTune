import Foundation

/// Complete whitespace-delimited token at the caret; coordinates are AX UTF-16.
public enum EditorWord {
    public static func beforeCaret(in value: String, selection: NSRange) -> String? {
        guard selection.length == 0, let range=Range(selection,in:value) else {return nil}
        let prefix=value[..<range.lowerBound]
        if !prefix.hasSuffix(" "), let next=value[range.upperBound...].first, !next.isWhitespace {return nil}
        let tokenEnd=prefix.lastIndex(where:{$0 != " "}).map{prefix.index(after:$0)} ?? prefix.startIndex
        let wordPrefix=prefix[..<tokenEnd]
        let start=wordPrefix.lastIndex(where:{$0.isWhitespace}).map{wordPrefix.index(after:$0)} ?? wordPrefix.startIndex
        let word=String(prefix[start...])
        guard start != tokenEnd, word.count<=128 else {return nil}
        return word
    }
    public static func matches(_ before: String, in value: String, selection: NSRange) -> Bool {
        beforeCaret(in:value,selection:selection)==before
    }
}
