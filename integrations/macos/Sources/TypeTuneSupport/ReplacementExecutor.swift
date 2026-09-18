import Foundation

public enum EditAction: Equatable { case backspace, text(String) }
public enum EditOutcome: String { case rejected, indeterminate, submitted, verified }
/// The native adapter supplies guards/output/readback; this is also run against a controlled editor.
public enum ReplacementExecutor {
    public static func run(remove: Int, replacement: String, guardCheck: () -> Bool,
                           emit: (EditAction) -> Bool, verify: () -> Bool?) -> EditOutcome {
        guard (1...128).contains(remove), replacement.count <= 128, !replacement.isEmpty,
              !replacement.contains("\0"), guardCheck() else {return .rejected}
        var edited=false
        let actions=Array(repeating:EditAction.backspace,count:remove)+replacement.map{EditAction.text(String($0))}
        for action in actions {
            guard guardCheck() else {return edited ? .indeterminate:.rejected}
            // A failed native output may already have made a partial change.
            guard emit(action) else {return .indeterminate}
            edited=true
        }
        guard guardCheck() else {return .indeterminate}
        guard let confirmed=verify() else {return .submitted}
        return confirmed ? .verified:.indeterminate
    }
}
