import Foundation

/// Login item registration is reverted to the previous effective value if save fails.
public enum LoginItemIntent {
    public static func rollbackTarget(desired: Bool, previous: Bool) -> Bool? {
        desired == previous ? nil : previous
    }
}
