// Prints what the focused UI element of the frontmost application exposes to Accessibility,
// without any of its text: role, attribute names, value types, string lengths, ranges,
// settable flags, and the same summary for up to six ancestors. Used to find out why a field
// is unreadable for TypeTune (docs/MAC_AGENT_GUIDE.md, section 4).
//
// Usage: scripts/ax_focus_probe.sh [--delay SECONDS] [--manual] [--enhanced]
//   --delay     seconds to wait before reading, to click into the field (default 3)
//   --manual    set AXManualAccessibility = true on the application first
//   --enhanced  set AXEnhancedUserInterface = true on the application first (side effects:
//               window animations and some window managers; reset with --reset-enhanced)
//   --reset-enhanced  set AXEnhancedUserInterface = false and exit
import AppKit
import ApplicationServices

var delay = 3.0
var setManual = false, setEnhanced = false, resetEnhanced = false
var arguments = Array(CommandLine.arguments.dropFirst())
while !arguments.isEmpty {
    let argument = arguments.removeFirst()
    switch argument {
    case "--delay": delay = Double(arguments.isEmpty ? "" : arguments.removeFirst()) ?? 3
    case "--manual": setManual = true
    case "--enhanced": setEnhanced = true
    case "--reset-enhanced": resetEnhanced = true
    default:
        FileHandle.standardError.write(Data("unknown argument \(argument)\n".utf8)); exit(2)
    }
}

func emit(_ value: Any) {
    let data = try! JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
    print(String(decoding: data, as: UTF8.self))
}
guard AXIsProcessTrusted() else {
    emit(["error": "Accessibility is not granted to the terminal running this probe"]); exit(1)
}
Thread.sleep(forTimeInterval: max(0, delay))
guard let application = NSWorkspace.shared.frontmostApplication else { emit(["error": "no frontmost application"]); exit(1) }
let appElement = AXUIElementCreateApplication(application.processIdentifier)
AXUIElementSetMessagingTimeout(appElement, 0.5)

var output: [String: Any] = ["bundleID": application.bundleIdentifier ?? "", "pid": Int(application.processIdentifier)]
func setFlag(_ name: String, _ value: Bool) -> Int {
    Int(AXUIElementSetAttributeValue(appElement, name as CFString, value ? kCFBooleanTrue : kCFBooleanFalse).rawValue)
}
if resetEnhanced {
    output["setAXEnhancedUserInterfaceFalse"] = setFlag("AXEnhancedUserInterface", false)
    emit(output); exit(0)
}
if setManual { output["setAXManualAccessibility"] = setFlag("AXManualAccessibility", true) }
if setEnhanced { output["setAXEnhancedUserInterface"] = setFlag("AXEnhancedUserInterface", true) }
if setManual || setEnhanced { Thread.sleep(forTimeInterval: 0.5) }

func copy(_ element: AXUIElement, _ name: String) -> (AXError, CFTypeRef?) {
    var value: CFTypeRef?
    let status = AXUIElementCopyAttributeValue(element, name as CFString, &value)
    return (status, value)
}
/// A value without text: strings become their UTF-16 length.
func describe(_ value: CFTypeRef?) -> Any {
    guard let value else { return NSNull() }
    let type = CFGetTypeID(value)
    if type == CFStringGetTypeID() { return ["string", (value as! String).utf16.count] }
    if type == CFBooleanGetTypeID() { return value as! Bool }
    if type == CFNumberGetTypeID() { return (value as! NSNumber).doubleValue }
    if type == AXUIElementGetTypeID() {
        let role = copy(value as! AXUIElement, kAXRoleAttribute as String).1 as? String
        return ["element", role ?? "?"]
    }
    if type == AXValueGetTypeID() {
        let axValue = value as! AXValue
        var range = CFRange()
        if AXValueGetType(axValue) == .cfRange, AXValueGetValue(axValue, .cfRange, &range) {
            return ["range", range.location, range.length]
        }
        return ["axvalue", Int(AXValueGetType(axValue).rawValue)]
    }
    if type == CFArrayGetTypeID() { return ["array", (value as! [AnyObject]).count] }
    return ["type", (CFCopyTypeIDDescription(type) as String?) ?? "?"]
}
func summary(_ element: AXUIElement) -> [String: Any] {
    AXUIElementSetMessagingTimeout(element, 0.5)
    var names: CFArray?
    let namesStatus = AXUIElementCopyAttributeNames(element, &names)
    var attributes: [String: Any] = [:]
    for name in (names as? [String]) ?? [] {
        let (status, value) = copy(element, name)
        var settable = DarwinBoolean(false)
        AXUIElementIsAttributeSettable(element, name as CFString, &settable)
        attributes[name] = ["status": Int(status.rawValue), "value": describe(value), "settable": settable.boolValue]
    }
    var parameterized: CFArray?
    AXUIElementCopyParameterizedAttributeNames(element, &parameterized)
    return ["namesStatus": Int(namesStatus.rawValue), "attributes": attributes,
            "parameterized": (parameterized as? [String]) ?? []]
}

let (focusedStatus, focused) = copy(appElement, kAXFocusedUIElementAttribute as String)
output["focusedUIElementStatus"] = Int(focusedStatus.rawValue)
let (windowStatus, _) = copy(appElement, kAXFocusedWindowAttribute as String)
output["focusedWindowStatus"] = Int(windowStatus.rawValue)
for name in ["AXManualAccessibility", "AXEnhancedUserInterface"] {
    let (status, value) = copy(appElement, name)
    output[name] = ["status": Int(status.rawValue), "value": describe(value)]
}
if let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() {
    var element = focused as! AXUIElement
    output["focused"] = summary(element)
    var ancestors: [[String: Any]] = []
    for _ in 0..<6 {
        let (status, parent) = copy(element, kAXParentAttribute as String)
        guard status == .success, let parent, CFGetTypeID(parent) == AXUIElementGetTypeID() else { break }
        element = parent as! AXUIElement
        let role = copy(element, kAXRoleAttribute as String).1 as? String
        let value = copy(element, kAXValueAttribute as String)
        let range = copy(element, kAXSelectedTextRangeAttribute as String)
        ancestors.append(["role": role ?? "?", "value": describe(value.1), "selectedRange": describe(range.1)])
    }
    output["ancestors"] = ancestors
}
output["note"] = "No text is printed: strings appear as their UTF-16 length. AXError 0 = success, -25205 = attribute unsupported, -25204 = cannot complete, -25212 = no value."
emit(output)
