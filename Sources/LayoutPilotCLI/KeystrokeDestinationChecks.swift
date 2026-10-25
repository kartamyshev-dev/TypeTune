import LayoutPilotCore

/// The bug: Spotlight keeps the previous application frontmost while its own search field
/// receives keys. Keystrokes posted to the frontmost process never reach it.
func keystrokeDestinationChecks() -> [(Bool, String)] {
    var checks: [(Bool, String)] = []
    func check(_ result: Bool, _ name: String) { checks.append((result, "keystroke destination: " + name)) }

    let panel = KeystrokeDestination.Focus(pid: 690, applicationID: "com.apple.Spotlight",
        isApplication: true, isTextInput: true, isSecure: false)
    check(KeystrokeDestination.retargets(frontmostPid: 23317, focus: panel, excludedApplications: []),
          "a focused panel field receives the keystrokes instead of the frontmost application")
    check(!KeystrokeDestination.retargets(frontmostPid: 690, focus: panel, excludedApplications: []),
          "the frontmost process that already has focus is never redirected")
    check(!KeystrokeDestination.retargets(frontmostPid: 23317, focus: panel,
                                          excludedApplications: ["com.apple.Spotlight"]),
          "an excluded application stays untouched")

    let never = [
        ("a helper process that is not a running application",
         KeystrokeDestination.Focus(pid: 701, applicationID: "com.google.Chrome.helper",
                                    isApplication: false, isTextInput: true, isSecure: false)),
        ("a focused element that is not a text input",
         KeystrokeDestination.Focus(pid: 702, applicationID: "com.apple.finder",
                                    isApplication: true, isTextInput: false, isSecure: false)),
        ("a password field",
         KeystrokeDestination.Focus(pid: 703, applicationID: "com.example.password",
                                    isApplication: true, isTextInput: true, isSecure: true)),
        ("an unknown application identity",
         KeystrokeDestination.Focus(pid: 704, applicationID: "",
                                    isApplication: true, isTextInput: true, isSecure: false))
    ]
    for (name, focus) in never {
        check(!KeystrokeDestination.retargets(frontmostPid: 23317, focus: focus, excludedApplications: []),
              "\(name) never takes the keystrokes")
    }
    check(!KeystrokeDestination.retargets(frontmostPid: 23317, focus: nil, excludedApplications: []),
          "an unreadable system focus keeps the frontmost application")
    return checks
}
