import Foundation

/// Before-edit refusal keeps the original input source after a successful select.
public enum LayoutRestore {
    public static func after(_ result: String, original: String, select: (String) -> Bool) -> String {
        if result == "rejected" { _ = select(original) }
        return result
    }
}
