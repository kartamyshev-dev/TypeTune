import Foundation

/// Pure inverse-edit proof. Runtime must separately pin the same AX target,
/// permissions, source/revision and the still-active FIFO barrier.
public struct PartialMutationRollbackPlan: Sendable {
    public let edit: TextEdit
    public init?(isPartial: Bool, hasQueuedEditingInput: Bool,
                 beforeText: String, beforeSelection: NSRange, replacementRange: NSRange,
                 decision: Decision, afterText: String, afterSelection: NSRange) {
        guard isPartial, hasQueuedEditingInput, beforeSelection.length == 0,
              let originalRange = TextEdit.validatedRange(replacementRange, in: beforeText),
              replacementRange.location + replacementRange.length == beforeSelection.location,
              String(beforeText[originalRange]).utf16.elementsEqual(decision.original.utf16),
              let forward = TextEdit(text: beforeText, selection: replacementRange, replacement: decision.replacement),
              forward.expectedText.utf16.elementsEqual(afterText.utf16),
              afterSelection == NSRange(location: forward.cursor, length: 0),
              let inverse = TextEdit(text: afterText,
                  selection: NSRange(location: replacementRange.location, length: decision.replacement.utf16.count),
                  replacement: decision.original),
              inverse.expectedText.utf16.elementsEqual(beforeText.utf16),
              inverse.cursor == beforeSelection.location else { return nil }
        edit = inverse
    }
}
