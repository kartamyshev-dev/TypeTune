/// Where typed text goes, as far as it can be identified without reading the field.
/// Universal mode always knows the process and application; the window number is known
/// when the window server reports it; the focused field only when Accessibility exposes it.
/// Field is the platform's field identity (an AX element on macOS).
public struct InputTarget<Field> {
    public var pid: Int32
    public var applicationID: String
    public var window: UInt32?
    public var field: Field?

    public init(pid: Int32, applicationID: String, window: UInt32? = nil, field: Field? = nil) {
        self.pid = pid; self.applicationID = applicationID; self.window = window; self.field = field
    }

    /// Whether `current` is still this target. The expected target decides what must be
    /// proven: a window or field known when the target was taken must be observed again
    /// and be equal; losing it fails closed. What was never known cannot be required.
    public func matches(_ current: InputTarget<Field>, sameField: (Field, Field) -> Bool) -> Bool {
        guard pid == current.pid, applicationID == current.applicationID else { return false }
        if let window {
            guard current.window == window else { return false }
        }
        if let field {
            guard let observed = current.field, sameField(field, observed) else { return false }
        }
        return true
    }

    /// How strong an identity proof this target can give.
    public var proof: Proof {
        if field != nil { return .field }
        if window != nil { return .window }
        return .application
    }

    public enum Proof: Int, Comparable, Sendable {
        case application, window, field
        public static func < (a: Proof, b: Proof) -> Bool { a.rawValue < b.rawValue }
    }
}

extension InputTarget: Sendable where Field: Sendable {}
extension InputTarget: Equatable where Field: Equatable {}

public extension InputTarget where Field: Equatable {
    func matches(_ current: InputTarget<Field>) -> Bool { matches(current, sameField: ==) }
}
