/// Which process must receive synthesized keystrokes.
///
/// The frontmost application is not always the one with keyboard focus: system panels such as
/// Spotlight keep the previous application frontmost while their own search field receives keys
/// (docs/SPOTLIGHT_FOCUS.md). Keystrokes posted to the frontmost process then land in the wrong
/// application, so the edit is lost and the previous application may even be modified.
public enum KeystrokeDestination {
    /// The system-wide focused element, as far as Accessibility exposes it. Never carries text.
    public struct Focus: Equatable, Sendable {
        public var pid: Int32
        public var applicationID: String
        /// The element belongs to a running application, not to a helper or renderer process.
        /// Posting keystrokes to a helper is not the same as posting them to its application.
        public var isApplication: Bool
        /// A text input (search field, text field, text area), not a menu, list or web area.
        public var isTextInput: Bool
        /// Password fields are never edited, even when the system reports this focus.
        public var isSecure: Bool
        public init(pid: Int32, applicationID: String, isApplication: Bool, isTextInput: Bool, isSecure: Bool) {
            self.pid = pid
            self.applicationID = applicationID
            self.isApplication = isApplication
            self.isTextInput = isTextInput
            self.isSecure = isSecure
        }
    }

    /// Whether the keystrokes must go to the focused element's process instead of the
    /// frontmost application. `frontmostPid` is the process the edit was planned for.
    public static func retargets(frontmostPid: Int32, focus: Focus?, excludedApplications: [String]) -> Bool {
        guard let focus, focus.isApplication, focus.isTextInput, !focus.isSecure,
              !focus.applicationID.isEmpty, focus.pid != frontmostPid else { return false }
        return !excludedApplications.contains(focus.applicationID)
    }
}
