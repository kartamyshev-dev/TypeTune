// Explicitly authorized synthetic-input fixture driver. This is not evidence of
// physical-keyboard behavior. It never changes TypeTune's production trust rules.
import AppKit
import Carbon
import ApplicationServices

struct CheckFailure: Error { let code: String }
func fail(_ code: String) throws -> Never { throw CheckFailure(code: code) }
func emit(_ value: [String: Any]) {
    if let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
       let text = String(data: data, encoding: .utf8) { print(text); fflush(stdout) }
}
let fixturePrefix = "TypeTune Native Check"
let openCodeBundle = "ai.opencode.desktop"
let openCodeTitle = "OpenCode"
let openCodePrompt = "Промпт"
let openCodeEmptyPlaceholder = "Спросите что угодно, / — команды, @ — контекст..."
let browserFixtureDescription = "TypeTune Native Check contenteditable"
let domOracleDescription = "TypeTune Native Check oracle"
let browserFixtureBundles = ["com.apple.Safari","com.google.Chrome"]
func validOpenCodeDraftURL(_ value: String) -> Bool {
    // Require the exact observed URL form: no escaping, extra query, fragment,
    // or alternative routing semantics may broaden the isolated draft guard.
    let prefix = "oc://renderer/new-session?draftId="
    guard value.hasPrefix(prefix) else { return false }
    let nonce = String(value.dropFirst(prefix.count))
    guard let uuid = UUID(uuidString:nonce) else { return false }
    return uuid.uuidString.lowercased() == nonce
}
func validateOpenCodeDraftLinks(_ urls: [String], expected: String) throws {
    // Reject any other internal tab route, including routes whose session
    // shape is unknown to this fixture driver.
    let internalURLs = urls.filter { URLComponents(string:$0)?.scheme?.lowercased() == "oc" }
    guard internalURLs.count == 1, internalURLs[0] == expected
    else { try fail("opencode_draft_links_mismatch") }
}
let fixtureWords = ["", "hello ", "ghbdtn", "привет", "Ghbdtn", "Привет", "ghbdtn ", "привет ",
    "ghbdtn  ", "привет  ", "Ghbdtn ", "Привет ", "ghbdtn ghbdtn ", "привет привет ",
    "ghbdtn привет ", "привет ghbdtn ", "ghbdtn ghbdtn  ", "привет привет  ",
    "ghbdtn, ", "привет, ", "🙂\nghbdtn ", "🙂\nпривет ",
    "ghbdtn Ghbdtn ", "ghbdtn Привет ", "привет Ghbdtn ", "привет Привет "]
func webkitFixture(_ value: String) -> String {
    value.hasSuffix(" ") ? String(value.dropLast()) + "\u{a0}" : value
}
func blinkFixture(_ value: String) -> String {
    // Chrome contenteditable's independently observed two-space suffix is two
    // NBSPs. Preserve all internal spaces and every other WebKit expectation.
    if value.hasSuffix("  ") && !value.hasSuffix("   ") {
        return String(value.dropLast(2)) + "\u{a0}\u{a0}"
    }
    return webkitFixture(value)
}
let allowedText: Set<String> = Set((fixtureWords + fixtureWords.map(webkitFixture) + fixtureWords.map(blinkFixture)).flatMap { word in (0...word.count).map { String(word.prefix($0)) } })
let abc = "com.apple.keylayout.ABC"
let russian = "com.apple.keylayout.RussianWin"
let keyCodes: [Character: CGKeyCode] = ["a":0,"s":1,"d":2,"f":3,"h":4,"g":5,"z":6,"x":7,"c":8,"v":9,
    "b":11,"q":12,"w":13,"e":14,"r":15,"y":16,"t":17,"1":18,"2":19,"3":20,"4":21,"6":22,"5":23,
    "9":25,"7":26,"8":28,"0":29,"o":31,"u":32,"i":34,"p":35,"l":37,"j":38,"k":40,",":43,"n":45,"m":46," ":49]
let ruCharacters: [Character: Character] = Dictionary(uniqueKeysWithValues: zip(Array("qwertyuiopasdfghjklzxcvbnm"), Array("йцукенгшщзфывапролдячсмить")))
let physicalCharacters = Dictionary(uniqueKeysWithValues:keyCodes.map { ($0.value,$0.key) })
let driverMarker: Int64 = 0x4e41544956455453 // NATIVETS; outside TypeTune's reserved markers.

func refreshFixtureUnicode(_ event: CGEvent, layout: () -> String) throws {
    let shortcuts: CGEventFlags = [.maskCommand,.maskControl,.maskAlternate,.maskAlphaShift,.maskSecondaryFn]
    guard event.type == .keyDown || event.type == .keyUp,
          event.flags.intersection(shortcuts).isEmpty,
          let physical = physicalCharacters[CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))],
          physical == " " || ruCharacters[physical] != nil else { return }
    let selected = layout()
    guard selected == abc || selected == russian else { try fail("unexpected_input_source") }
    var text = String(selected == russian ? (ruCharacters[physical] ?? physical) : physical)
    if event.flags.contains(.maskShift) { text = text.uppercased() }
    let units = Array(text.utf16)
    event.keyboardSetUnicodeString(stringLength:units.count,unicodeString:units)
}

struct Options {
    var inspect = false
    var selfCheck = false
    var activate = false
    var observed = false
    var pid: pid_t = 0
    var bundle = ""
    var title = ""
    var scenario = "manual"
    var repetitions = 1
    var keyDelay = 15
    var nextDelay = 25
    var editorSpaces = "literal"
    var draftURL: String?
    var domOracle = false
    var isOpenCode: Bool { draftURL != nil }
    init(_ arguments: [String]) throws {
        var index = 0
        while index < arguments.count {
            let option = arguments[index]; index += 1
            if option == "--inspect" { inspect = true; continue }
            if option == "--self-check" { selfCheck = true; continue }
            if option == "--activate" { activate = true; continue }
            if option == "--observed" { observed = true; continue }
            if option == "--dom-oracle" { domOracle = true; continue }
            guard index < arguments.count else { try fail("missing_option_value") }
            let value = arguments[index]; index += 1
            switch option {
            case "--pid": pid = pid_t(value) ?? 0
            case "--bundle": bundle = value
            case "--title": title = value
            case "--scenario": scenario = value
            case "--repeat": repetitions = Int(value) ?? 0
            case "--key-delay-ms": keyDelay = Int(value) ?? -1
            case "--next-delay-ms": nextDelay = Int(value) ?? -1
            case "--editor-spaces": editorSpaces = value
            case "--draft-url": draftURL = value
            default: try fail("unknown_option")
            }
        }
        if selfCheck { return }
        let openCodeRequested = draftURL != nil || bundle == openCodeBundle || title == openCodeTitle
        let fixtureIdentityValid: Bool
        if openCodeRequested {
            fixtureIdentityValid = bundle == openCodeBundle && title == openCodeTitle &&
                draftURL.map(validOpenCodeDraftURL) == true
        } else { fixtureIdentityValid = title.hasPrefix(fixturePrefix) }
        guard !domOracle || (!openCodeRequested && browserFixtureBundles.contains(bundle) && title.hasPrefix(fixturePrefix))
        else { try fail("invalid_dom_oracle_profile") }
        guard editorSpaces != "blink" || (bundle == "com.google.Chrome" && domOracle)
        else { try fail("invalid_blink_fixture_profile") }
        guard pid > 0, !bundle.isEmpty, fixtureIdentityValid, title.count <= 128,
              ["raw","auto","manual","retoggle","spaces","case","nextword","nextword-shift","punctuation","unicode"].contains(scenario),
              (1...30).contains(repetitions), (0...100).contains(keyDelay), (0...300).contains(nextDelay),
              ["literal","webkit","blink"].contains(editorSpaces)
        else { try fail("invalid_arguments_or_fixture_title") }
    }
}

func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return nil }
    return value
}
func elementAttribute(_ element: AXUIElement, _ key: String) -> AXUIElement? {
    guard let value = attribute(element,key), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
    return (value as! AXUIElement)
}
func sourceID(_ source: TISInputSource) -> String {
    guard let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return "" }
    return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
}
func currentLayout() -> String {
    precondition(Thread.isMainThread)
    guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return "" }
    return sourceID(source)
}
struct FixtureTextState {
    let rawValue: String
    let rawRange: CFRange
    let value: String
    let range: CFRange
}
func checkedFixtureText(_ value: String, range: CFRange, openCode: Bool, initial: Bool, allowClearedLF: Bool = false) throws -> FixtureTextState {
    if openCode && initial && value != "" && value != "\u{200b}" { try fail("opencode_initial_prompt_not_empty") }
    if openCode && (value == "\u{200b}" || (value == "\n" && allowClearedLF && !initial)) {
        guard range.length == 0, range.location == 0 || range.location == 1
        else { try fail("opencode_empty_placeholder_selection_invalid") }
        return FixtureTextState(rawValue:value,rawRange:range,value:"",range:CFRange(location:0,length:0))
    }
    guard allowedText.contains(value) else { try fail("fixture_text_not_allowlisted") }
    guard range.location >= 0, range.length >= 0, range.location <= value.utf16.count,
          range.length <= value.utf16.count-range.location else { try fail("invalid_ax_selection") }
    return FixtureTextState(rawValue:value,rawRange:range,value:value,range:range)
}
struct OpenCodeEmptyState {
    private(set) var clearPending = false
    private(set) var clearedEmpty = false
    var allowsLF: Bool { clearPending || clearedEmpty }
    mutating func beginClear() { clearPending = true }
    mutating func endClear() { clearPending = false }
    mutating func observe(_ text: FixtureTextState) {
        if text.value.isEmpty {
            if clearPending || clearedEmpty { clearedEmpty = true }
        } else { clearedEmpty = false }
    }
}
struct Snapshot {
    let element: AXUIElement
    let value: String
    let range: CFRange
    let rawValue: String
    let rawRange: CFRange
    let role: String
}
struct FixtureAXNode {
    let element: AXUIElement
    let role: String
}
func fixtureAXChildren(_ element: AXUIElement) throws -> [AXUIElement] {
    var rawChildren: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(element,kAXChildrenAttribute as CFString,&rawChildren)
    if result == .attributeUnsupported || result == .noValue { return [] }
    guard result == .success, let rawChildren,
          CFGetTypeID(rawChildren) == CFArrayGetTypeID(), let children = rawChildren as? [AXUIElement]
    else { try fail("fixture_ax_children_unavailable") }
    return children
}
func fixtureAXTree(_ window: AXUIElement, deadline: TimeInterval) throws -> [FixtureAXNode] {
    var pending: [(AXUIElement,Int)] = [(window,0)]
    var visited: [FixtureAXNode] = []
    while let (element,depth) = pending.popLast() {
        guard ProcessInfo.processInfo.systemUptime < deadline else { try fail("driver_deadline") }
        guard depth <= 20, visited.count < 1000 else { try fail("fixture_ax_tree_limit") }
        guard !visited.contains(where:{CFEqual($0.element,element)}) else { try fail("fixture_ax_tree_repeated_element") }
        AXUIElementSetMessagingTimeout(element,0.05)
        guard let role = attribute(element,kAXRoleAttribute) as? String else { try fail("fixture_ax_tree_role_unavailable") }
        visited.append(FixtureAXNode(element:element,role:role))
        let children = try fixtureAXChildren(element)
        guard children.isEmpty || depth < 20,
              visited.count + pending.count + children.count <= 1000 else { try fail("fixture_ax_tree_limit") }
        for child in children { pending.append((child,depth+1)) }
    }
    return visited
}
func validateOpenCodeWindow(_ window: AXUIElement, draftURL: String, deadline: TimeInterval) throws {
    var linkURLs: [String] = []
    for node in try fixtureAXTree(window,deadline:deadline) where node.role == "AXLink" {
        let rawURL = attribute(node.element,kAXURLAttribute)
        if let url = rawURL as? String { linkURLs.append(url) }
        else if let url = rawURL as? URL { linkURLs.append(url.absoluteString) }
        else { try fail("opencode_ax_link_url_unavailable") }
    }
    try validateOpenCodeDraftLinks(linkURLs,expected:draftURL)
}
func checkedOpenCodeEmptyIndicators(placeholderCount: Int, sendEnabled: [Bool]) throws {
    guard placeholderCount == 1, sendEnabled == [false]
    else { try fail("opencode_empty_ui_not_confirmed") }
}
func validateOpenCodeClearedEmptyUI(_ parent: AXUIElement, prompt: AXUIElement, deadline: TimeInterval) throws {
    let nodes = try fixtureAXTree(parent,deadline:deadline)
    guard nodes.filter({CFEqual($0.element,prompt)}).count == 1 else { try fail("opencode_prompt_parent_mismatch") }
    let placeholders = nodes.filter {
        $0.role == kAXStaticTextRole &&
        ((attribute($0.element,kAXValueAttribute) as? String) == openCodeEmptyPlaceholder ||
         (attribute($0.element,kAXTitleAttribute) as? String) == openCodeEmptyPlaceholder)
    }
    let sendButtons = nodes.filter {
        $0.role == kAXButtonRole &&
        ((attribute($0.element,kAXTitleAttribute) as? String) == "Отправить" ||
         (attribute($0.element,kAXDescriptionAttribute) as? String) == "Отправить")
    }
    var enabledStates: [Bool] = []
    for button in sendButtons {
        guard let enabled = attribute(button.element,kAXEnabledAttribute),
              CFGetTypeID(enabled) == CFBooleanGetTypeID(), let state = enabled as? Bool
        else { try fail("opencode_empty_ui_not_confirmed") }
        enabledStates.append(state)
    }
    try checkedOpenCodeEmptyIndicators(placeholderCount:placeholders.count,sendEnabled:enabledStates)
    guard let parentAfter = elementAttribute(prompt,kAXParentAttribute), CFEqual(parentAfter,parent)
    else { try fail("opencode_prompt_parent_mismatch") }
}
struct DOMOracleState {
    let text: FixtureTextState
    let revision: Int
}
func checkedDOMOracle(_ json: String) throws -> DOMOracleState {
    guard let data = json.data(using:.utf8),
          let object = try? JSONSerialization.jsonObject(with:data), let fields = object as? [String:Any],
          Set(fields.keys) == Set(["field","value","caret","length","revision"]),
          fields["field"] as? String == "editable", let value = fields["value"] as? String
    else { try fail("dom_oracle_schema_invalid") }
    func integer(_ key: String) -> Int? {
        guard let number = fields[key] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID()
        else { return nil }
        return Int(number.stringValue)
    }
    guard let caret = integer("caret"), let length = integer("length"),
          let revision = integer("revision"), revision >= 0 else { try fail("dom_oracle_range_invalid") }
    let text = try checkedFixtureText(value,range:CFRange(location:caret,length:length),openCode:false,initial:false)
    return DOMOracleState(text:text,revision:revision)
}
func findDOMOracle(_ window: AXUIElement, deadline: TimeInterval) throws -> AXUIElement {
    let matches = try fixtureAXTree(window,deadline:deadline).filter {
        (attribute($0.element,kAXDescriptionAttribute) as? String) == domOracleDescription
    }
    guard matches.count == 1, matches[0].role == kAXTextAreaRole else { try fail("dom_oracle_element_mismatch") }
    return matches[0].element
}
func readDOMOracle(_ element: AXUIElement) throws -> String {
    guard (attribute(element,kAXRoleAttribute) as? String) == kAXTextAreaRole,
          (attribute(element,kAXDescriptionAttribute) as? String) == domOracleDescription
    else { try fail("dom_oracle_element_mismatch") }
    var settable: DarwinBoolean = false
    guard AXUIElementIsAttributeSettable(element,kAXValueAttribute as CFString,&settable) == .success,
          !settable.boolValue else { try fail("dom_oracle_not_readonly") }
    if let json = attribute(element,kAXValueAttribute) as? String { return json }
    // Some browser AX implementations expose readonly textarea contents only
    // in one direct static-text child. Do not search arbitrary descendants.
    let children = try fixtureAXChildren(element)
    guard children.count == 1,
          (attribute(children[0],kAXRoleAttribute) as? String) == kAXStaticTextRole,
          let json = attribute(children[0],kAXValueAttribute) as? String
    else { try fail("dom_oracle_value_unavailable") }
    return json
}

// Mandatory route containment for synthetic fixture input. AX focus alone
// cannot prove the destination of a globally posted Quartz event.
let fixtureTypeTuneBundle = "dev.kartamyshev.TypeTune"
let fixtureTypeTunePath = "/Applications/TypeTune.app"
let fixtureTypeTuneOwnMarker: Int64 = 0x5459504554554e45
let fixtureTypeTuneReplayMarker: Int64 = 0x5459504552504c59
struct FixtureTypeTuneIdentity: Equatable {
    let pid: pid_t
    let launchDate: Date?
}
func fixtureTypeTuneIdentity() throws -> FixtureTypeTuneIdentity? {
    let apps = NSRunningApplication.runningApplications(withBundleIdentifier:fixtureTypeTuneBundle).filter{!$0.isTerminated}
    if apps.isEmpty { return nil }
    guard apps.count == 1, let app = apps.first,
          app.bundleURL?.standardizedFileURL.path == fixtureTypeTunePath,
          app.executableURL?.standardizedFileURL.path == fixtureTypeTunePath + "/Contents/MacOS/TypeTune"
    else { try fail("route_guard_typetune_identity_unverified") }
    return FixtureTypeTuneIdentity(pid:app.processIdentifier,launchDate:app.launchDate)
}
struct FixtureRouteEvent {
    let type: CGEventType
    let key: CGKeyCode
    let flags: CGEventFlags
    let marker: Int64
    let sourcePID: Int64
    let targetPID: Int64
}
struct FixtureRoutePolicy {
    let fixturePID: pid_t
    let driverPID: pid_t
    let typeTunePID: pid_t?
    var reason: String?
    var firstFailureEvent: FixtureRouteEvent?
    var allowed = 0
    var blocked = 0
    var wrongTarget = 0
    var unknownSource = 0
    var cleanup = false
    var cleanupRemaining: Set<CGKeyCode> = []
    var deliveredDriverKeys: Set<CGKeyCode> = []
    mutating func accept(_ event: FixtureRouteEvent, ownDriver: Bool) -> Bool {
        if ownDriver {
            if event.type == .keyDown || (event.type == .flagsChanged && event.flags.contains(.maskShift)) {
                deliveredDriverKeys.insert(event.key)
            } else if event.type == .keyUp || event.type == .flagsChanged {
                deliveredDriverKeys.remove(event.key)
            }
        }
        allowed += 1; return true
    }
    mutating func latch(_ value: String) { if reason == nil { reason = value } }
    func isScoped(marker: Int64, sourcePID: Int64) -> Bool {
        (marker == driverMarker && sourcePID == Int64(driverPID)) ||
        (typeTunePID != nil && [fixtureTypeTuneOwnMarker,fixtureTypeTuneReplayMarker].contains(marker))
    }
    mutating func permits(_ event: FixtureRouteEvent) -> Bool {
        guard isScoped(marker:event.marker,sourcePID:event.sourcePID) else { return true }
        let ownDriver = event.marker == driverMarker && event.sourcePID == Int64(driverPID)
        let knownEngine = typeTunePID.map { pid in
            (event.marker == fixtureTypeTuneOwnMarker && event.sourcePID == Int64(pid)) ||
            (event.marker == fixtureTypeTuneReplayMarker && [Int64(pid),Int64(driverPID)].contains(event.sourcePID))
        } ?? false
        guard ownDriver || knownEngine else {
            unknownSource += 1; blocked += 1
            if firstFailureEvent == nil { firstFailureEvent = event }
            latch("route_guard_engine_source_unknown"); return false
        }
        guard event.targetPID > 0, event.targetPID == Int64(fixturePID) else {
            wrongTarget += 1; blocked += 1
            if firstFailureEvent == nil { firstFailureEvent = event }
            latch("route_guard_wrong_target"); return false
        }
        if cleanup {
            let release = event.type == .keyUp || (event.type == .flagsChanged && event.key == 56)
            if ownDriver && release && event.flags.isEmpty && cleanupRemaining.remove(event.key) != nil {
                return accept(event,ownDriver:ownDriver)
            }
            blocked += 1; latch("route_guard_cleanup_event_invalid"); return false
        }
        if reason != nil { blocked += 1; return false }
        return accept(event,ownDriver:ownDriver)
    }
}
final class FixtureRouteGuard {
    private let lock = NSLock()
    private let ready = DispatchSemaphore(value:0)
    private let ended = DispatchSemaphore(value:0)
    private var policy: FixtureRoutePolicy
    private let deadline: TimeInterval
    private var worker: Thread?
    private var runLoop: CFRunLoop?
    private var stopRequested = false
    private var finished = false
    private var started = false
    init(fixturePID: pid_t, typeTunePID: pid_t?, deadline: TimeInterval) {
        policy = FixtureRoutePolicy(fixturePID:fixturePID,driverPID:getpid(),typeTunePID:typeTunePID)
        self.deadline = deadline
        policy.deliveredDriverKeys.reserveCapacity(128)
    }
    private func latch(_ reason: String) { lock.lock(); policy.latch(reason); lock.unlock() }
    func markFailure(_ reason: String) { latch(reason) }
    func check() throws {
        lock.lock(); let reason = policy.reason; lock.unlock()
        if let reason { try fail(reason) }
    }
    private func metadataLocked() -> [String:Any] {
        var result: [String:Any] = ["mandatory":true,"allowed_events":policy.allowed,"blocked_events":policy.blocked,
                "wrong_target_events":policy.wrongTarget,"unknown_source_events":policy.unknownSource,
                "engine_filter":policy.typeTunePID != nil,"cleanup_pending":policy.cleanupRemaining.count,
                "delivered_keys_pending":policy.deliveredDriverKeys.count,
                "unmarked_events_covered":false,"reason":policy.reason ?? "none"]
        if let event = policy.firstFailureEvent {
            result["failure_target_pid"] = event.targetPID; result["failure_source_pid"] = event.sourcePID
            result["failure_event_type"] = event.type.rawValue; result["failure_keycode"] = event.key
        }
        return result
    }
    func metadata() -> [String:Any] {
        lock.lock(); defer { lock.unlock() }; return metadataLocked()
    }
    func healthyMetadata() throws -> [String:Any] {
        lock.lock(); defer { lock.unlock() }
        if let reason = policy.reason { try fail(reason) }
        return metadataLocked()
    }
    func beginCleanup(_ attempted: Set<CGKeyCode>) -> Set<CGKeyCode> {
        lock.lock(); defer { lock.unlock() }
        // A blocked key-up must not erase a down that reached the fixture.
        let keys = attempted.union(policy.deliveredDriverKeys)
        policy.cleanup = true; policy.cleanupRemaining = keys
        return keys
    }
    func finishCleanup() {
        let until = ProcessInfo.processInfo.systemUptime + 0.25
        repeat {
            lock.lock(); let done = policy.cleanupRemaining.isEmpty; lock.unlock()
            if done { break }
            Thread.sleep(forTimeInterval:0.005)
        } while ProcessInfo.processInfo.systemUptime < until
        lock.lock(); policy.cleanup = false; lock.unlock()
    }
    private func verifyMask(_ required: CGEventMask) throws -> UInt32 {
        var count: UInt32 = 0
        guard CGGetEventTapList(0,nil,&count) == .success, count > 0, count <= 4096 else { try fail("route_guard_tap_list_unavailable") }
        let capacity = min(4096,Int(count)+16)
        var taps = [CGEventTapInformation](repeating:CGEventTapInformation(),count:capacity)
        var returned: UInt32 = 0
        guard CGGetEventTapList(UInt32(capacity),&taps,&returned) == .success, returned <= capacity
        else { try fail("route_guard_tap_list_unavailable") }
        let own = taps.prefix(Int(returned)).filter {
            $0.tappingProcess == getpid() && $0.tapPoint == .cgAnnotatedSessionEventTap && $0.options == .defaultTap
        }
        guard own.count == 1, own[0].enabled, own[0].eventsOfInterest & required == required
        else { try fail("route_guard_full_keyboard_mask_unverified") }
        return own[0].eventTapID
    }
    private func process(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            latch("route_guard_tap_disabled"); return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown || type == .keyUp || type == .flagsChanged else { return Unmanaged.passUnretained(event) }
        let marker = event.getIntegerValueField(.eventSourceUserData)
        let sourcePID = event.getIntegerValueField(.eventSourceUnixProcessID)
        lock.lock(); defer { lock.unlock() }
        guard policy.isScoped(marker:marker,sourcePID:sourcePID) else { return Unmanaged.passUnretained(event) }
        let allowed = policy.permits(FixtureRouteEvent(type:type,key:CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode)),
            flags:event.flags,marker:marker,sourcePID:sourcePID,targetPID:event.getIntegerValueField(.eventTargetUnixProcessID)))
        return allowed ? Unmanaged.passUnretained(event) : nil
    }
    private func work() {
        defer {
            lock.lock(); finished = true; runLoop = nil; lock.unlock()
            ready.signal(); ended.signal()
        }
        guard CGPreflightListenEventAccess() else { latch("route_guard_listen_permission_missing"); return }
        let mask = [CGEventType.keyDown,.keyUp,.flagsChanged].reduce(CGEventMask(0)){$0 | (CGEventMask(1)<<$1.rawValue)}
        let callback: CGEventTapCallBack = { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            return Unmanaged<FixtureRouteGuard>.fromOpaque(context).takeUnretainedValue().process(type,event)
        }
        guard let tap = CGEvent.tapCreate(tap:.cgAnnotatedSessionEventTap,place:.tailAppendEventTap,options:.defaultTap,
                                          eventsOfInterest:mask,callback:callback,userInfo:Unmanaged.passUnretained(self).toOpaque()),
              let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault,tap,0)
        else { latch("route_guard_tap_unavailable"); return }
        let loop = CFRunLoopGetCurrent()
        CFRunLoopAddSource(loop,source,.commonModes)
        CGEvent.tapEnable(tap:tap,enable:true)
        defer {
            CGEvent.tapEnable(tap:tap,enable:false)
            CFRunLoopRemoveSource(loop,source,.commonModes)
            CFRunLoopSourceInvalidate(source); CFMachPortInvalidate(tap)
        }
        do {
            guard CFMachPortIsValid(tap), CGEvent.tapIsEnabled(tap:tap) else { try fail("route_guard_tap_unavailable") }
            _ = try verifyMask(mask)
        } catch let error as CheckFailure { latch(error.code); return }
        catch { latch("route_guard_startup_failed"); return }
        lock.lock(); runLoop = loop; let cancelled = stopRequested; lock.unlock()
        if cancelled { return }
        let timer = Timer(timeInterval:0.02,repeats:true) { [self] _ in
            if ProcessInfo.processInfo.systemUptime >= deadline { latch("driver_deadline") }
            if !CFMachPortIsValid(tap) || !CGEvent.tapIsEnabled(tap:tap) { latch("route_guard_tap_disabled") }
        }
        RunLoop.current.add(timer,forMode:.common)
        defer { timer.invalidate() }
        CFRunLoopPerformBlock(loop,CFRunLoopMode.defaultMode.rawValue) { [self] in ready.signal() }
        CFRunLoopRun()
        lock.lock()
        if !stopRequested { policy.latch("route_guard_worker_stopped") }
        lock.unlock()
    }
    func start() throws {
        lock.lock(); started = true; lock.unlock()
        let thread = Thread { [self] in work() }
        thread.name = "TypeTuneFixtureRouteGuard"; worker = thread; thread.start()
        guard ready.wait(timeout:.now()+2) == .success else {
            latch("route_guard_startup_timeout"); stop(); try fail("route_guard_startup_timeout")
        }
        try check()
    }
    func stop() {
        lock.lock(); stopRequested = true; let loop = runLoop; let shouldWait = started && !finished; lock.unlock()
        if let loop { CFRunLoopStop(loop); CFRunLoopWakeUp(loop) }
        if shouldWait { _ = ended.wait(timeout:.now()+1) }
    }
}

// This is only a read-only fixture-observation budget, not the production
// input transaction budget. The absolute deadline never moves after a retry.
struct FixtureSnapshotRetryWindow {
    let deadline: TimeInterval
    init(startedAt: TimeInterval, driverDeadline: TimeInterval) {
        deadline = min(driverDeadline,startedAt + 0.5)
    }
    static func isTransient(_ code: String) -> Bool {
        ["invalid_ax_selection","ax_snapshot_changing",
         "ax_focused_window_unavailable","ax_window_title_unavailable","focused_ax_element_unavailable",
         "ax_role_unavailable","ax_value_unavailable","ax_selection_unavailable","target_identity_unavailable",
         "fixture_ax_tree_role_unavailable","fixture_ax_children_unavailable"].contains(code)
    }
    func permits(_ code: String, at now: TimeInterval) -> Bool {
        Self.isTransient(code) && now < deadline
    }
}

final class Driver {
    let options: Options
    let deadline = ProcessInfo.processInfo.systemUptime + 150
    var focus: AXUIElement?
    var boundWindow: AXUIElement?
    var boundOracle: AXUIElement?
    var boundOpenCodePromptParent: AXUIElement?
    var openCodeEmptyState = OpenCodeEmptyState()
    var openCodeClearTarget: Snapshot?
    var posted = 0
    var axPreparationSelections = 0
    var snapshotRetryCount = 0
    var snapshotRetryMaxElapsedMS = 0.0
    var snapshotRetryLastReason = "none"
    var snapshotRetryExhaustedCount = 0
    func snapshotRetryMetadata() -> [String:Any] {
        ["retry_count":snapshotRetryCount,"max_elapsed_ms":snapshotRetryMaxElapsedMS,
         "last_reason":snapshotRetryLastReason,"exhausted_count":snapshotRetryExhaustedCount,
         "budget_ms":500]
    }
    var lastPostAt = ProcessInfo.processInfo.systemUptime
    var shiftSamples: [[String: Any]] = []
    var pressedByDriver: Set<CGKeyCode> = []
    let source: CGEventSource
    let typeTuneIdentity: FixtureTypeTuneIdentity?
    let routeGuard: FixtureRouteGuard
    func expectedFixture(_ value: String) -> String {
        switch options.editorSpaces {
        case "blink": return blinkFixture(value)
        case "webkit": return webkitFixture(value)
        default: return value
        }
    }
    init(_ options: Options) throws {
        self.options = options
        guard let source = CGEventSource(stateID: .hidSystemState) else { try fail("cannot_create_synthetic_event_source") }
        self.source = source
        source.localEventsSuppressionInterval = 0
        typeTuneIdentity = try fixtureTypeTuneIdentity()
        routeGuard = FixtureRouteGuard(fixturePID:options.pid,typeTunePID:typeTuneIdentity?.pid,deadline:deadline)
        do { try routeGuard.start() } catch { routeGuard.stop(); throw error }
    }
    deinit { routeGuard.stop() }
    func checkRouteAndEngine() throws {
        try routeGuard.check()
        do {
            guard try fixtureTypeTuneIdentity() == typeTuneIdentity else { try fail("route_guard_typetune_identity_changed") }
        } catch {
            routeGuard.markFailure("route_guard_typetune_identity_changed")
            throw error
        }
        try routeGuard.check()
    }
    func pause(_ milliseconds: Int) throws {
        try routeGuard.check()
        guard ProcessInfo.processInfo.systemUptime < deadline else { try fail("driver_deadline") }
        RunLoop.current.run(until: Date().addingTimeInterval(Double(milliseconds)/1000))
        try routeGuard.check()
    }
    func snapshot(bind: Bool = false, requireFrontmost: Bool = true) throws -> Snapshot {
        let startedAt = ProcessInfo.processInfo.systemUptime
        let retry = FixtureSnapshotRetryWindow(startedAt:startedAt,driverDeadline:deadline)
        var transientReason: String?
        defer {
            if transientReason != nil {
                snapshotRetryMaxElapsedMS = max(snapshotRetryMaxElapsedMS,
                    (ProcessInfo.processInfo.systemUptime-startedAt)*1000)
            }
        }
        while true {
            let state: Snapshot
            do { state = try snapshotOnce(bind:bind,requireFrontmost:requireFrontmost) }
            catch let error as CheckFailure where FixtureSnapshotRetryWindow.isTransient(error.code) {
                transientReason = error.code; snapshotRetryLastReason = error.code
                // Retry reads only. Every attempt repeats route, process,
                // window, field, secure-input and content guards; genuine
                // identity changes are never classified as transient.
                guard retry.permits(error.code,at:ProcessInfo.processInfo.systemUptime) else {
                    snapshotRetryExhaustedCount += 1; throw error
                }
                try pause(5)
                guard retry.permits(error.code,at:ProcessInfo.processInfo.systemUptime) else {
                    snapshotRetryExhaustedCount += 1; throw error
                }
                snapshotRetryCount += 1
                continue
            }
            // A slow successful reread must not extend the same retry window.
            if let transientReason, !retry.permits(transientReason,at:ProcessInfo.processInfo.systemUptime) {
                snapshotRetryExhaustedCount += 1; try fail(transientReason)
            }
            return state
        }
    }
    private func snapshotOnce(bind: Bool, requireFrontmost: Bool) throws -> Snapshot {
        try checkRouteAndEngine()
        guard ProcessInfo.processInfo.systemUptime < deadline else { try fail("driver_deadline") }
        guard AXIsProcessTrusted() else { try fail("driver_accessibility_permission_missing") }
        guard !IsSecureEventInputEnabled() else { try fail("secure_input_enabled") }
        guard let app = NSRunningApplication(processIdentifier:options.pid),
              let bundle = app.bundleIdentifier else { try fail("target_identity_unavailable") }
        guard !app.isTerminated, bundle == options.bundle else { try fail("target_pid_or_bundle_mismatch") }
        if requireFrontmost && NSWorkspace.shared.frontmostApplication?.processIdentifier != options.pid {
            try fail("target_pid_or_bundle_not_frontmost")
        }
        let application = AXUIElementCreateApplication(options.pid)
        AXUIElementSetMessagingTimeout(application,0.05)
        guard let window = elementAttribute(application,kAXFocusedWindowAttribute)
        else { try fail("ax_focused_window_unavailable") }
        if let boundWindow, !CFEqual(boundWindow,window) { try fail("focused_window_changed") }
        guard let title = attribute(window,kAXTitleAttribute) as? String
        else { try fail("ax_window_title_unavailable") }
        guard title == options.title else {
            // Never print another document's title. Only these fixed fixture
            // variants (including the editor's own Edited suffix) are public.
            let knownTitle = #"^TypeTune Native Check(?:\.(?:rtf|txt|html))?(?: [—–-] (?:Edited|Изменено|Safari|Google Chrome))?$"#
            var detail: [String:Any] = ["status":"FIXTURE_GUARD_FAILED","reason":"fixture_window_title_mismatch",
                                      "fixture_title_prefix":title.hasPrefix(fixturePrefix)]
            if title.range(of:knownTitle,options:.regularExpression) != nil { detail["observed_fixture_title"] = title }
            emit(detail)
            try fail("fixture_window_title_mismatch")
        }
        guard let element = elementAttribute(application,kAXFocusedUIElementAttribute) else { try fail("focused_ax_element_unavailable") }
        AXUIElementSetMessagingTimeout(element,0.05)
        var elementPID: pid_t = 0
        guard AXUIElementGetPid(element,&elementPID) == .success, elementPID == options.pid else { try fail("focused_element_pid_mismatch") }
        if let focus, !CFEqual(focus, element) { try fail("focused_element_changed") }
        if let fieldWindow = elementAttribute(element,kAXWindowAttribute), !CFEqual(fieldWindow,window) {
            try fail("focused_element_window_mismatch")
        }
        if let draftURL = options.draftURL { try validateOpenCodeWindow(window,draftURL:draftURL,deadline:deadline) }
        guard let role = attribute(element,kAXRoleAttribute) as? String else { try fail("ax_role_unavailable") }
        let subrole = attribute(element,kAXSubroleAttribute) as? String ?? ""
        guard [kAXTextAreaRole,kAXTextFieldRole,kAXComboBoxRole].contains(role), subrole != kAXSecureTextFieldSubrole else { try fail("focused_element_not_plain_text") }
        var sampledOpenCodeParent: AXUIElement?
        if options.isOpenCode {
            guard role == kAXTextAreaRole, (attribute(element,kAXDescriptionAttribute) as? String) == openCodePrompt,
                  let parent = elementAttribute(element,kAXParentAttribute)
            else { try fail("opencode_focused_prompt_mismatch") }
            if let boundOpenCodePromptParent, !CFEqual(boundOpenCodePromptParent,parent) {
                try fail("opencode_prompt_parent_mismatch")
            }
            sampledOpenCodeParent = parent
        }
        let state: FixtureTextState
        var sampledOracle: AXUIElement?
        if options.domOracle {
            guard role == kAXTextAreaRole,
                  (attribute(element,kAXDescriptionAttribute) as? String) == browserFixtureDescription
            else { try fail("dom_oracle_focused_fixture_mismatch") }
            let oracle = try findDOMOracle(window,deadline:deadline)
            if let boundOracle, !CFEqual(boundOracle,oracle) { try fail("dom_oracle_element_changed") }
            let json = try readDOMOracle(oracle)
            let observed = try checkedDOMOracle(json)
            let jsonAfter = try readDOMOracle(oracle)
            _ = try checkedDOMOracle(jsonAfter)
            guard jsonAfter == json else { try fail("ax_snapshot_changing") }
            state = observed.text
            sampledOracle = oracle
        } else {
            guard let value = attribute(element,kAXValueAttribute) as? String else { try fail("ax_value_unavailable") }
            guard let raw = attribute(element,kAXSelectedTextRangeAttribute), CFGetTypeID(raw) == AXValueGetTypeID() else { try fail("ax_selection_unavailable") }
            let selected = raw as! AXValue
            var range = CFRange()
            guard AXValueGetType(selected) == .cfRange, AXValueGetValue(selected,.cfRange,&range) else { try fail("invalid_ax_selection") }
            guard let valueAfter = attribute(element,kAXValueAttribute) as? String else { try fail("ax_value_unavailable") }
            let allowClearedLF = options.isOpenCode && focus != nil && openCodeEmptyState.allowsLF
            state = try checkedFixtureText(value,range:range,openCode:options.isOpenCode,initial:focus == nil,allowClearedLF:allowClearedLF)
            _ = try checkedFixtureText(valueAfter,range:range,openCode:options.isOpenCode,initial:focus == nil,allowClearedLF:allowClearedLF)
            guard valueAfter == value else { try fail("ax_snapshot_changing") }
            if options.isOpenCode && value == "\n" {
                guard let parent = sampledOpenCodeParent else { try fail("opencode_prompt_parent_mismatch") }
                try validateOpenCodeClearedEmptyUI(parent,prompt:element,deadline:deadline)
                // The UI evidence is collected after the raw reads, so confirm
                // the exact LF and collapsed caret again before accepting it.
                guard (attribute(element,kAXValueAttribute) as? String) == value,
                      let selectedAfterRaw = attribute(element,kAXSelectedTextRangeAttribute),
                      CFGetTypeID(selectedAfterRaw) == AXValueGetTypeID()
                else { try fail("ax_snapshot_changing") }
                let selectedAfter = selectedAfterRaw as! AXValue
                var rangeAfter = CFRange()
                guard AXValueGetType(selectedAfter) == .cfRange,
                      AXValueGetValue(selectedAfter,.cfRange,&rangeAfter),
                      rangeAfter.location == range.location, rangeAfter.length == range.length
                else { try fail("ax_snapshot_changing") }
            }
        }
        guard let windowAfter = elementAttribute(application,kAXFocusedWindowAttribute), CFEqual(windowAfter,window),
              let elementAfter = elementAttribute(application,kAXFocusedUIElementAttribute), CFEqual(elementAfter,element),
              (attribute(windowAfter,kAXTitleAttribute) as? String) == options.title
        else { try fail("ax_snapshot_changing") }
        // Traversing an accessibility tree may outlast a foreground change.
        // Repeat process and input guards after the last AX read, before bind
        // or a caller's next synthetic event.
        guard AXIsProcessTrusted() else { try fail("driver_accessibility_permission_missing") }
        guard !IsSecureEventInputEnabled() else { try fail("secure_input_enabled") }
        guard let appAfter = NSRunningApplication(processIdentifier:options.pid),
              !appAfter.isTerminated, appAfter.bundleIdentifier == options.bundle
        else { try fail("target_pid_or_bundle_mismatch") }
        if requireFrontmost && NSWorkspace.shared.frontmostApplication?.processIdentifier != options.pid {
            try fail("target_pid_or_bundle_not_frontmost")
        }
        try checkRouteAndEngine()
        // Commit identity only after every title, draft, field, content and
        // selection guard has passed. A failed initial read binds nothing.
        if bind {
            focus = element; boundWindow = window; boundOracle = sampledOracle
            boundOpenCodePromptParent = sampledOpenCodeParent
        }
        if options.isOpenCode { openCodeEmptyState.observe(state) }
        return Snapshot(element:element,value:state.value,range:state.range,
                        rawValue:state.rawValue,rawRange:state.rawRange,role:role)
    }
    func activateIfRequested() throws {
        guard options.activate else { return }
        // First inspect the exact existing fixture without changing focus. Only
        // then may we raise its window and activate that same process.
        _ = try snapshot(bind:true,requireFrontmost:false)
        let application = AXUIElementCreateApplication(options.pid)
        AXUIElementSetMessagingTimeout(application,0.05)
        guard let window = elementAttribute(application,kAXFocusedWindowAttribute),
              let boundWindow, CFEqual(window,boundWindow),
              (attribute(window,kAXTitleAttribute) as? String) == options.title,
              let app = NSRunningApplication(processIdentifier:options.pid), app.bundleIdentifier == options.bundle
        else { try fail("activation_fixture_changed") }
        let raised = AXUIElementPerformAction(window,kAXRaiseAction as CFString)
        guard raised == .success || raised == .actionUnsupported else { try fail("fixture_raise_failed") }
        guard app.activate(options:[]) else { try fail("fixture_activation_failed") }
        let until = ProcessInfo.processInfo.systemUptime+1
        repeat {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == options.pid {
                _ = try snapshot(); return
            }
            try pause(20)
        } while ProcessInfo.processInfo.systemUptime < until
        try fail("fixture_not_frontmost_after_activation")
    }
    func inspect() throws {
        let state = try snapshot(bind:true)
        emit(["mode":"inspect","status":"OK","fixture_text_allowlisted":true,"value_utf16_count":state.value.utf16.count,
              "caret":state.range.location,"selection_length":state.range.length,"role":state.role,
              "raw_value_utf16_count":state.rawValue.utf16.count,"raw_caret":state.rawRange.location,
              "raw_selection_length":state.rawRange.length,"opencode_draft_guard":options.isOpenCode,
              "dom_oracle_guard":options.domOracle,"route_guard":routeGuard.metadata(),
              "layout":currentLayout(),"accessibility":AXIsProcessTrusted(),"post":CGPreflightPostEventAccess(),
              "listen":CGPreflightListenEventAccess(),"pid":options.pid,"bundle":options.bundle,"events_posted":posted,
              "shift_hid_down":CGEventSource.keyState(.hidSystemState,key:56),
              "shift_session_down":CGEventSource.keyState(.combinedSessionState,key:56)])
    }
    func post(_ event: CGEvent) throws {
        try routeGuard.check()
        // No fixture scenario may send Return or keypad Enter, including an
        // accidental future caller. Multiline setup uses guarded AX only.
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        guard keyCode != 36, keyCode != 76 else { try fail("fixture_submit_key_forbidden") }
        let before = try snapshot()
        let beginsOpenCodeClear = openCodeClearTarget != nil
        if let target = openCodeClearTarget {
            guard options.isOpenCode, event.type == .keyDown, keyCode == 51,
                  before.rawValue == target.rawValue, !before.value.isEmpty,
                  before.rawRange.location == 0, before.rawRange.length == before.rawValue.utf16.count,
                  before.rawRange.location == target.rawRange.location,
                  before.rawRange.length == target.rawRange.length
            else { try fail("opencode_clear_target_changed_before_post") }
        }
        guard CGPreflightPostEventAccess() else { try fail("driver_post_permission_missing") }
        event.setIntegerValueField(.eventSourceUserData,value:driverMarker)
        // Do not overwrite eventSourceUnixProcessID or label this physical input.
        // AX/TCC checks can outlive a layout switch. Resolve plain-key Unicode
        // only now; no AX query or wait follows this refresh before posting.
        try routeGuard.check()
        try refreshFixtureUnicode(event,layout:currentLayout)
        event.post(tap:.cghidEventTap)
        if beginsOpenCodeClear {
            // Arm LF handling only once our checked Backspace keyDown has
            // actually been posted; its following keyUp may see empty LF.
            openCodeEmptyState.beginClear()
            openCodeClearTarget = nil
        }
        lastPostAt = ProcessInfo.processInfo.systemUptime
        posted += 1
        let code = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        if event.type == .keyDown || (event.type == .flagsChanged && event.flags.contains(.maskShift)) {
            pressedByDriver.insert(code)
        } else { pressedByDriver.remove(code) }
        try routeGuard.check()
    }
    func releaseOnFailure() {
        // Balance only keys this driver pressed, using natural CGEvent key-up
        // payloads and the captured PID, never another foreground app. No new
        // key-down/shortcut is allowed after a fixture guard has failed.
        guard NSRunningApplication(processIdentifier:options.pid)?.bundleIdentifier == options.bundle else { return }
        let cleanupKeys = routeGuard.beginCleanup(pressedByDriver)
        defer { routeGuard.finishCleanup() }
        for code in cleanupKeys {
            guard let event = CGEvent(keyboardEventSource:source,virtualKey:code,keyDown:false) else { continue }
            event.flags=[]
            if code == 56 { event.type = .flagsChanged }
            event.setIntegerValueField(.eventSourceUserData,value:driverMarker)
            event.postToPid(options.pid)
            posted += 1
        }
        pressedByDriver.removeAll()
    }
    func key(_ code: CGKeyCode, flags: CGEventFlags = []) throws {
        guard let down = CGEvent(keyboardEventSource:source,virtualKey:code,keyDown:true),
              let up = CGEvent(keyboardEventSource:source,virtualKey:code,keyDown:false) else { try fail("event_allocation_failed") }
        down.flags=flags; up.flags=flags
        try post(down); try post(up)
    }
    func shift(_ down: Bool) throws {
        guard let event = CGEvent(keyboardEventSource:source,virtualKey:56,keyDown:down) else { try fail("event_allocation_failed") }
        event.type = .flagsChanged
        event.flags = down ? CGEventFlags(rawValue:CGEventFlags.maskShift.rawValue | 0x2) : []
        try post(event)
        try pause(35)
        shiftSamples.append(["requested_down":down,"hid_down":CGEventSource.keyState(.hidSystemState,key:56),
                             "session_down":CGEventSource.keyState(.combinedSessionState,key:56),
                             "session_shift_flag":CGEventSource.flagsState(.combinedSessionState).contains(.maskShift)])
    }
    func doubleShift() throws {
        for _ in 0..<2 { try shift(true); try shift(false); try pause(45) }
    }
    func type(_ physicalLetters: String) throws {
        for character in physicalLetters {
            let lower = Character(String(character).lowercased())
            guard let code = keyCodes[lower] else { try fail("unsupported_fixture_key") }
            let upper = character != lower
            if upper { try shift(true) }
            try key(code,flags:upper ? .maskShift:[])
            if upper { try shift(false) }
            try pause(options.keyDelay)
        }
    }
    func waitFor(_ value: String, layout: String?, timeout: Double = 1.5) throws -> Double {
        let start = ProcessInfo.processInfo.systemUptime
        repeat {
            let state = try snapshot()
            if state.value == value, state.range.location == value.utf16.count, state.range.length == 0,
               layout == nil || currentLayout() == layout { return (ProcessInfo.processInfo.systemUptime-start)*1000 }
            try pause(5)
        } while ProcessInfo.processInfo.systemUptime-start < timeout
        try assertionFailure(try snapshot(),expected:value,reason:"text_caret_or_layout_assertion_failed")
    }
    func assertionFailure(_ state: Snapshot, expected value: String, reason: String) throws -> Never {
        var failure: [String:Any] = ["status":"ASSERTION_FAILED","text_match":state.value==value,"expected_fixture":value,
              "observed_utf16_count":state.value.utf16.count,"caret":state.range.location,
              "selection_length":state.range.length,"layout":currentLayout(),"reason":reason]
        if options.observed && allowedText.contains(state.value) { failure["observed_fixture"] = state.value }
        emit(failure)
        try fail(reason)
    }
    func confirmStable(_ value: String, layout: String) throws -> Double {
        let start = ProcessInfo.processInfo.systemUptime
        repeat {
            let state = try snapshot()
            guard state.value == value, state.range.location == value.utf16.count, state.range.length == 0,
                  currentLayout() == layout else {
                try assertionFailure(state,expected:value,reason:"result_changed_after_first_match")
            }
            let modifiers: CGEventFlags = [.maskShift,.maskCommand,.maskControl,.maskAlternate,.maskAlphaShift]
            let sessionFlags = CGEventSource.flagsState(.combinedSessionState).intersection(modifiers)
            guard sessionFlags.isEmpty else {
                emit(["status":"ASSERTION_FAILED","reason":"modifiers_latched_after_output",
                      "session_modifier_flags":sessionFlags.rawValue,
                      "hid_modifier_flags":CGEventSource.flagsState(.hidSystemState).intersection(modifiers).rawValue])
                try fail("modifiers_latched_after_output")
            }
            let elapsed = ProcessInfo.processInfo.systemUptime-start
            if elapsed >= 0.5 { return elapsed*1000 }
            try pause(10)
        } while true
    }
    func clearFixture() throws {
        defer { openCodeEmptyState.endClear(); openCodeClearTarget = nil }
        let state = try snapshot()
        if !state.value.isEmpty {
            try key(0,flags:.maskCommand)
            let selectionDeadline = ProcessInfo.processInfo.systemUptime + 1
            var selected = try snapshot()
            while selected.range.location != 0 || selected.range.length != selected.value.utf16.count {
                if ProcessInfo.processInfo.systemUptime >= selectionDeadline { break }
                try pause(10)
                selected = try snapshot()
            }
            if selected.range.location != 0 || selected.range.length != selected.value.utf16.count {
                // Some editors ignore synthetic Command flags without physical
                // modifier edges. Cmd+A was still sent to reset engine history;
                // selecting this exact isolated synthetic fixture is safe via AX.
                selected = try snapshot()
                let expectedValue = selected.value
                var full = CFRange(location:0,length:expectedValue.utf16.count)
                guard let range = AXValueCreate(.cfRange,&full),
                      AXUIElementSetAttributeValue(selected.element,kAXSelectedTextRangeAttribute as CFString,range) == .success
                else { try fail("fixture_ax_select_all_failed") }
                axPreparationSelections += 1
                let verifyDeadline = ProcessInfo.processInfo.systemUptime + 1
                repeat {
                    selected = try snapshot()
                    guard selected.value == expectedValue else { try fail("fixture_changed_during_select_all") }
                    if selected.range.location == 0 && selected.range.length == expectedValue.utf16.count { break }
                    guard ProcessInfo.processInfo.systemUptime < verifyDeadline else { try fail("fixture_ax_selection_not_confirmed") }
                    try pause(10)
                } while true
            }
            let confirmed = try snapshot()
            guard confirmed.value == selected.value, confirmed.range.location == 0,
                  confirmed.range.length == confirmed.value.utf16.count else { try fail("fixture_selection_changed_before_clear") }
            // post() rechecks this exact fully selected fixture, then arms LF
            // handling only after it has sent our Backspace keyDown.
            if options.isOpenCode { openCodeClearTarget = confirmed }
            try key(51)
        }
        _ = try waitFor("",layout:nil)
        try pause(40)
    }
    func prepare() throws {
        try clearFixture()
        _ = try snapshot()
        guard let sources = TISCreateInputSourceList([kTISPropertyInputSourceID as String:abc] as CFDictionary,false)?.takeRetainedValue() as? [TISInputSource],
              let english = sources.first, TISSelectInputSource(english) == noErr,
              currentLayout() == abc else { try fail("cannot_select_abc") }
        try pause(80)
        // Consume the documented first-word anti-loop after an external layout
        // change using a valid English fixture, then clear it through real events.
        try type("hello ")
        _ = try waitFor(expectedFixture("hello "),layout:abc)
        // AX can show hello before the switcher processes its Space. Keep the
        // fixture still so Cmd+A cannot make that warmup event stale. This is
        // preparation; scenario latency starts only after prepare() returns.
        _ = try confirmStable(expectedFixture("hello "),layout:abc)
        try clearFixture()
    }
    func run() throws {
        _ = try snapshot(bind:true)
        guard CGPreflightPostEventAccess() else { try fail("driver_post_permission_missing") }
        guard CGEventSource.flagsState(.combinedSessionState).intersection([.maskShift,.maskControl,.maskAlternate,.maskCommand,.maskAlphaShift]).isEmpty else { try fail("physical_modifier_or_caps_held") }
        emit(["status":"START","origin":"synthetic_hidSystemState","source_pid_overridden":false,
              "driver_pid":ProcessInfo.processInfo.processIdentifier,"target_pid":options.pid,"scenario":options.scenario,"repetitions":options.repetitions,"editor_spaces":options.editorSpaces,
              "dom_oracle_guard":options.domOracle,"opencode_draft_guard":options.isOpenCode])
        // Activation is setup, not measured input. Let observers establish the
        // new field before warmup; no keys may race the focus transition.
        let initial = try snapshot()
        _ = try confirmStable(initial.value, layout: currentLayout())
        for iteration in 1...options.repetitions {
            if iteration > 1 { try pause(150) }
            try prepare()
            if options.scenario == "unicode" {
                // Prepare only this empty, guarded fixture. The correction must
                // preserve a non-BMP character and a preceding line boundary.
                let state = try snapshot()
                guard state.value.isEmpty else { try fail("unicode_fixture_not_empty") }
                let prefix = "🙂\n"
                guard AXUIElementSetAttributeValue(state.element,kAXValueAttribute as CFString,prefix as CFString) == .success
                else { try fail("unicode_fixture_seed_unavailable") }
                var caret = CFRange(location:prefix.utf16.count,length:0)
                guard let range = AXValueCreate(.cfRange,&caret),
                      AXUIElementSetAttributeValue(state.element,kAXSelectedTextRangeAttribute as CFString,range) == .success
                else { try fail("unicode_fixture_caret_unavailable") }
                _ = try waitFor(prefix,layout:abc)
            }
            let started = ProcessInfo.processInfo.systemUptime
            try type(options.scenario == "case" ? "Ghbdtn" : "ghbdtn")
            if options.scenario == "punctuation" { try type(",") }
            let triggerAt = ProcessInfo.processInfo.systemUptime
            var expected = "привет", expectedLayout = russian
            switch options.scenario {
            case "raw": try key(49); expected="ghbdtn "; expectedLayout=abc
            case "manual": try doubleShift()
            case "retoggle":
                try doubleShift(); _ = try waitFor("привет",layout:russian)
                try doubleShift(); expected="ghbdtn"; expectedLayout=abc
            case "spaces":
                try key(49); try key(49); expected="привет  "
            case "case": try key(49); expected="Привет "
            case "punctuation": try key(49); expected="привет, "
            case "unicode": try key(49); expected="🙂\nпривет "
            case "nextword":
                try key(49); try pause(options.nextDelay)
                try type("ghbdtn "); expected="привет привет "
            case "nextword-shift":
                try key(49); try pause(options.nextDelay)
                try type("Ghbdtn "); expected="привет Привет "
            default: try key(49); expected="привет "
            }
            expected = expectedFixture(expected)
            let settle = try waitFor(expected,layout:expectedLayout)
            let firstMatchAt = ProcessInfo.processInfo.systemUptime
            // The final assertion must remain true without any further input.
            // Clearing and the first retoggle assertion keep their fast path;
            // warmup settles separately before scenario timing begins.
            let stableWindow = try confirmStable(expected,layout:expectedLayout)
            try checkRouteAndEngine()
            let healthyRoute = try routeGuard.healthyMetadata()
            emit(["status":"PASS","route_guard":healthyRoute,"snapshot_retry":snapshotRetryMetadata(),"scenario":options.scenario,"iteration":iteration,"expected_fixture":expected,
                  "text_match":true,"caret_match":true,"layout_match":true,"modifiers_released":true,"layout":currentLayout(),
                  "iteration_ms":(firstMatchAt-started)*1000,"trigger_sequence_to_assertion_ms":(firstMatchAt-triggerAt)*1000,
                  "last_post_to_assertion_ms":(firstMatchAt-lastPostAt)*1000,"final_poll_ms":settle,
                  "first_match_ms":settle,"stable_window_ms":stableWindow,
                  "events_posted":posted,"preparation_ax_selection_fallbacks":axPreparationSelections,
                  "synthetic_shift_hid_matches":shiftSamples.allSatisfy{($0["requested_down"] as? Bool)==($0["hid_down"] as? Bool)},
                  "shift_samples":shiftSamples])
            shiftSamples.removeAll(keepingCapacity:true)
        }
    }
}

func selfCheck() throws {
    guard allowedText.contains(""), allowedText.contains("ghbdtn"), allowedText.contains("привет привет "),
          !allowedText.contains("private document"), !allowedText.contains("ghbdtn\n"),
          keyCodes["g"] == 5, ruCharacters["g"] == "п", ruCharacters["n"] == "т",
          driverMarker & 0x7fff000000000000 != 0x5454000000000000 else { try fail("self_check_failed") }
    guard allowedText.contains("привет, "), keyCodes[","] == 43,
          allowedText.contains("🙂\nпривет "), "🙂\nпривет ".utf16.count == 10
    else { try fail("fixture_extended_text_failed") }
    guard webkitFixture("привет  ")=="привет \u{a0}", allowedText.contains("hello\u{a0}")
    else { try fail("webkit_fixture_failed") }
    do { _ = try Options(["--pid","1","--bundle","fixture","--title","Ordinary document"]); try fail("unsafe_title_accepted") }
    catch let error as CheckFailure where error.code == "invalid_arguments_or_fixture_title" {}
    let valid = try Options(["--pid","1","--bundle","fixture","--title","TypeTune Native Check.rtf","--repeat","30"])
    guard valid.repetitions == 30 else { try fail("self_check_failed") }
    guard let source = CGEventSource(stateID:.hidSystemState),
          let edge = CGEvent(keyboardEventSource:source,virtualKey:56,keyDown:true) else { try fail("event_allocation_failed") }
    edge.type = .flagsChanged; edge.flags = CGEventFlags(rawValue:CGEventFlags.maskShift.rawValue | 0x2)
    guard edge.type == .flagsChanged, edge.getIntegerValueField(.keyboardEventKeycode) == 56,
          edge.flags.contains(.maskShift) else { try fail("shift_event_shape_failed") }
    func unicode(_ event: CGEvent) -> String {
        var count = 0
        var units = [UniChar](repeating:0,count:16)
        event.keyboardGetUnicodeString(maxStringLength:units.count,actualStringLength:&count,unicodeString:&units)
        return String(utf16CodeUnits:units,count:count)
    }
    func checkMapping(_ code: CGKeyCode, _ flags: CGEventFlags, _ layout: String, _ expected: String) throws {
        guard let event = CGEvent(keyboardEventSource:source,virtualKey:code,keyDown:true) else { try fail("event_allocation_failed") }
        event.flags = flags
        let stale = Array("h".utf16)
        event.keyboardSetUnicodeString(stringLength:stale.count,unicodeString:stale)
        try refreshFixtureUnicode(event,layout:{layout})
        guard unicode(event) == expected else { try fail("fixture_unicode_mapping_failed") }
    }
    try checkMapping(4,[],abc,"h")
    try checkMapping(4,[],russian,"р")
    try checkMapping(5,.maskShift,russian,"П")
    try checkMapping(5,.maskShift,abc,"G")
    try checkMapping(49,[],russian," ")
    try checkMapping(0,.maskCommand,russian,"h") // Shortcut Unicode stays untouched.
    try checkMapping(51,[],russian,"h") // Backspace stays untouched.
    guard let up = CGEvent(keyboardEventSource:source,virtualKey:4,keyDown:false) else { try fail("event_allocation_failed") }
    up.flags = []
    let stale = Array("h".utf16)
    up.keyboardSetUnicodeString(stringLength:stale.count,unicodeString:stale)
    var layoutRead = false
    try refreshFixtureUnicode(up,layout:{layoutRead=true;return russian})
    guard unicode(up) == "р", layoutRead else { try fail("fixture_key_up_unicode_failed") }
    try refreshFixtureUnicode(up,layout:{abc})
    guard unicode(up) == "h" else { try fail("fixture_key_up_unicode_failed") }
    up.flags = .maskCommand
    try refreshFixtureUnicode(up,layout:{russian})
    guard unicode(up) == "h" else { try fail("fixture_shortcut_key_up_changed") }
    do { try checkMapping(4,[],"unsupported","h"); try fail("unsupported_source_accepted") }
    catch let error as CheckFailure where error.code == "unexpected_input_source" {}
    var addedChecks = 0
    let retryWindow = FixtureSnapshotRetryWindow(startedAt:10,driverDeadline:150)
    guard retryWindow.deadline == 10.5,
          retryWindow.permits("ax_focused_window_unavailable",at:10.499),
          !retryWindow.permits("ax_focused_window_unavailable",at:10.5),
          !retryWindow.permits("ax_focused_window_unavailable",at:11)
    else { try fail("snapshot_retry_fixed_window_failed") }
    addedChecks += 1
    let clippedRetry = FixtureSnapshotRetryWindow(startedAt:10,driverDeadline:10.2)
    guard clippedRetry.deadline == 10.2,
          clippedRetry.permits("ax_focused_window_unavailable",at:10.199),
          !clippedRetry.permits("ax_focused_window_unavailable",at:10.2)
    else { try fail("snapshot_retry_driver_deadline_failed") }
    addedChecks += 1
    for reason in ["focused_window_changed","fixture_window_title_mismatch","focused_element_changed",
                   "focused_element_pid_mismatch","focused_element_window_mismatch","target_pid_or_bundle_mismatch",
                   "target_pid_or_bundle_not_frontmost","dom_oracle_element_changed","dom_oracle_focused_fixture_mismatch",
                   "opencode_prompt_parent_mismatch","opencode_draft_links_mismatch","fixture_text_not_allowlisted",
                   "secure_input_enabled","route_guard_wrong_target","route_guard_typetune_identity_changed","driver_deadline"] {
        guard !FixtureSnapshotRetryWindow.isTransient(reason), !retryWindow.permits(reason,at:10)
        else { try fail("snapshot_retry_hard_failure_accepted") }
        addedChecks += 1
    }
    func expectFailure(_ code: String, _ body: () throws -> Void) throws {
        do { try body(); try fail("expected_guard_failure_missing") }
        catch let error as CheckFailure where error.code == code { addedChecks += 1 }
    }
    let chromeDOM = ["--pid","1","--bundle","com.google.Chrome","--title",fixturePrefix,"--dom-oracle"]
    let blink = try Options(chromeDOM + ["--editor-spaces","blink"])
    guard blink.editorSpaces == "blink", blink.domOracle else { try fail("blink_options_failed") }
    addedChecks += 1
    for (input,expected) in [("ghbdtn  ","ghbdtn\u{a0}\u{a0}"),("привет  ","привет\u{a0}\u{a0}"),
                             ("hello ","hello\u{a0}"),("привет привет ","привет привет\u{a0}"),
                             ("привет  привет  ","привет  привет\u{a0}\u{a0}"),
                             ("привет   ","привет  \u{a0}"),("привет", "привет")] {
        guard blinkFixture(input) == expected else { try fail("blink_narrow_space_mapping_failed") }
        addedChecks += 1
    }
    for value in ["ghbdtn\u{a0}\u{a0}","привет\u{a0}\u{a0}"] {
        guard allowedText.contains(value) else { try fail("blink_fixture_allowlist_failed") }
        addedChecks += 1
    }
    guard !allowedText.contains("private\u{a0}\u{a0}"), !allowedText.contains("привет\u{a0}\u{a0}\u{a0}"),
          webkitFixture("привет  ") == "привет \u{a0}"
    else { try fail("blink_fixture_scope_broadened") }
    addedChecks += 1
    for (bundle,oracle) in [("com.google.Chrome",false),("com.apple.Safari",true),
                            ("com.apple.Safari",false),("com.apple.TextEdit",false)] {
        let args = ["--pid","1","--bundle",bundle,"--title",fixturePrefix,"--editor-spaces","blink"] + (oracle ? ["--dom-oracle"] : [])
        try expectFailure("invalid_blink_fixture_profile") { _ = try Options(args) }
    }
    let draftURL = "oc://renderer/new-session?draftId=01234567-89ab-4cde-8fab-0123456789ab"
    let openCodeArgs = ["--pid","1","--bundle",openCodeBundle,"--title",openCodeTitle]
    let openCode = try Options(openCodeArgs + ["--draft-url",draftURL])
    guard openCode.isOpenCode, openCode.draftURL == draftURL else { try fail("opencode_options_failed") }
    addedChecks += 1
    try expectFailure("invalid_arguments_or_fixture_title") { _ = try Options(openCodeArgs) }
    try expectFailure("invalid_arguments_or_fixture_title") {
        _ = try Options(["--pid","1","--bundle","fixture","--title",openCodeTitle,"--draft-url",draftURL])
    }
    try expectFailure("invalid_arguments_or_fixture_title") {
        _ = try Options(openCodeArgs + ["--draft-url","oc://renderer/new-session?draftId=not-a-uuid"])
    }
    for suffix in ["&sessionId=other","#fragment"] {
        try expectFailure("invalid_arguments_or_fixture_title") { _ = try Options(openCodeArgs + ["--draft-url",draftURL+suffix]) }
    }
    try expectFailure("invalid_arguments_or_fixture_title") {
        _ = try Options(["--pid","1","--bundle","com.apple.Safari","--title",fixturePrefix,"--draft-url",draftURL])
    }
    try expectFailure("invalid_arguments_or_fixture_title") {
        _ = try Options(["--pid","1","--bundle",openCodeBundle,"--title",fixturePrefix])
    }
    for raw in ["","\u{200b}"] {
        let state = try checkedFixtureText(raw,range:CFRange(location:0,length:0),openCode:true,initial:true)
        guard state.value.isEmpty, state.range.location == 0, state.rawValue == raw else { try fail("opencode_empty_fixture_failed") }
        addedChecks += 1
    }
    let placeholder = try checkedFixtureText("\u{200b}",range:CFRange(location:1,length:0),openCode:true,initial:true)
    guard placeholder.value.isEmpty, placeholder.range.location == 0, placeholder.rawRange.location == 1
    else { try fail("opencode_empty_fixture_failed") }
    addedChecks += 1
    try expectFailure("opencode_empty_placeholder_selection_invalid") {
        _ = try checkedFixtureText("\u{200b}",range:CFRange(location:0,length:1),openCode:true,initial:true)
    }
    try expectFailure("opencode_empty_placeholder_selection_invalid") {
        _ = try checkedFixtureText("\u{200b}",range:CFRange(location:2,length:0),openCode:true,initial:true)
    }
    try expectFailure("opencode_initial_prompt_not_empty") {
        _ = try checkedFixtureText("ghbdtn",range:CFRange(location:6,length:0),openCode:true,initial:true)
    }
    try expectFailure("fixture_text_not_allowlisted") {
        _ = try checkedFixtureText("ghbdtn\u{200b}",range:CFRange(location:7,length:0),openCode:true,initial:false)
    }
    try expectFailure("fixture_text_not_allowlisted") {
        _ = try checkedFixtureText("\u{200b}",range:CFRange(location:0,length:0),openCode:false,initial:false)
    }
    let nonempty = try checkedFixtureText("привет ",range:CFRange(location:2,length:3),openCode:true,initial:false)
    guard nonempty.value == "привет ", nonempty.rawValue == nonempty.value,
          nonempty.range.location == 2, nonempty.range.length == 3,
          nonempty.rawRange.location == 2, nonempty.rawRange.length == 3 else { try fail("opencode_nonempty_changed") }
    addedChecks += 1
    try expectFailure("invalid_ax_selection") {
        _ = try checkedFixtureText("ghbdtn",range:CFRange(location:7,length:0),openCode:true,initial:false)
    }
    try validateOpenCodeDraftLinks(["https://example.invalid/help",draftURL],expected:draftURL)
    addedChecks += 1
    for urls in [[String](),[draftURL,draftURL],[draftURL,"oc://renderer/session/existing"],
                 [draftURL,"oc://renderer/unknown-route"],
                 ["oc://renderer/new-session?draftId=11234567-89ab-4cde-8fab-0123456789ab"]] {
        try expectFailure("opencode_draft_links_mismatch") { try validateOpenCodeDraftLinks(urls,expected:draftURL) }
    }
    for bundle in browserFixtureBundles {
        let browser = try Options(["--pid","1","--bundle",bundle,"--title",fixturePrefix,"--dom-oracle"])
        guard browser.domOracle, !browser.isOpenCode else { try fail("dom_oracle_options_failed") }
        addedChecks += 1
    }
    try expectFailure("invalid_dom_oracle_profile") {
        _ = try Options(["--pid","1","--bundle","fixture","--title",fixturePrefix,"--dom-oracle"])
    }
    try expectFailure("invalid_dom_oracle_profile") {
        _ = try Options(["--pid","1","--bundle","com.apple.Safari","--title","ordinary page","--dom-oracle"])
    }
    try expectFailure("invalid_dom_oracle_profile") { _ = try Options(openCodeArgs + ["--draft-url",draftURL,"--dom-oracle"]) }
    func oracleJSON(_ fields: [String:Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject:fields,options:[.sortedKeys])
        guard let json = String(data:data,encoding:.utf8) else { try fail("self_check_failed") }
        return json
    }
    let emptyOracle: [String:Any] = ["field":"editable","value":"","caret":0,"length":0,"revision":2]
    let emptyDOM = try checkedDOMOracle(oracleJSON(emptyOracle))
    guard emptyDOM.text.value.isEmpty, emptyDOM.text.range.location == 0,
          emptyDOM.text.range.length == 0, emptyDOM.revision == 2 else { try fail("dom_oracle_empty_failed") }
    addedChecks += 1
    let unicodeDOM = try checkedDOMOracle(oracleJSON(["field":"editable","value":"🙂\nпривет ","caret":3,"length":7,"revision":4]))
    guard unicodeDOM.text.value == "🙂\nпривет ", unicodeDOM.text.rawValue == unicodeDOM.text.value,
          unicodeDOM.text.range.location == 3, unicodeDOM.text.range.length == 7,
          unicodeDOM.text.rawRange.location == 3, unicodeDOM.revision == 4 else { try fail("dom_oracle_unicode_failed") }
    addedChecks += 1
    let webkitDOM = try checkedDOMOracle(oracleJSON(["field":"editable","value":"hello\u{a0}","caret":6,"length":0,"revision":5]))
    guard webkitDOM.text.value == "hello\u{a0}", webkitDOM.text.range.location == 6 else { try fail("dom_oracle_webkit_changed") }
    addedChecks += 1
    for update: [String:Any] in [["field":"other"],["unexpected":"extra"],["value":42]] {
        var fields = emptyOracle; fields.merge(update,uniquingKeysWith:{$1})
        try expectFailure("dom_oracle_schema_invalid") { _ = try checkedDOMOracle(oracleJSON(fields)) }
    }
    for update: [String:Any] in [["caret":true],["length":0.5],["revision":-1],["revision":true],["revision":"2"]] {
        var fields = emptyOracle; fields.merge(update,uniquingKeysWith:{$1})
        try expectFailure("dom_oracle_range_invalid") { _ = try checkedDOMOracle(oracleJSON(fields)) }
    }
    for value in ["private document","\n","\u{200b}"] {
        var fields = emptyOracle; fields["value"] = value
        try expectFailure("fixture_text_not_allowlisted") { _ = try checkedDOMOracle(oracleJSON(fields)) }
    }
    for update: [String:Any] in [["caret":1],["length":1],["caret":-1]] {
        var fields = emptyOracle; fields.merge(update,uniquingKeysWith:{$1})
        try expectFailure("invalid_ax_selection") { _ = try checkedDOMOracle(oracleJSON(fields)) }
    }
    try expectFailure("dom_oracle_schema_invalid") { _ = try checkedDOMOracle("not JSON") }
    for caret in [0,1] {
        let cleared = try checkedFixtureText("\n",range:CFRange(location:caret,length:0),openCode:true,initial:false,allowClearedLF:true)
        guard cleared.value.isEmpty, cleared.range.location == 0, cleared.range.length == 0,
              cleared.rawValue == "\n", cleared.rawRange.location == caret else { try fail("opencode_cleared_lf_failed") }
        addedChecks += 1
    }
    try expectFailure("opencode_initial_prompt_not_empty") {
        _ = try checkedFixtureText("\n",range:CFRange(location:0,length:0),openCode:true,initial:true,allowClearedLF:true)
    }
    try expectFailure("fixture_text_not_allowlisted") {
        _ = try checkedFixtureText("\n",range:CFRange(location:0,length:0),openCode:true,initial:false)
    }
    try expectFailure("fixture_text_not_allowlisted") {
        _ = try checkedFixtureText("\n",range:CFRange(location:0,length:0),openCode:false,initial:false,allowClearedLF:true)
    }
    for range in [CFRange(location:0,length:1),CFRange(location:2,length:0),CFRange(location:-1,length:0)] {
        try expectFailure("opencode_empty_placeholder_selection_invalid") {
            _ = try checkedFixtureText("\n",range:range,openCode:true,initial:false,allowClearedLF:true)
        }
    }
    for value in ["\n\n","ghbdtn\n","\nhello"] {
        try expectFailure("fixture_text_not_allowlisted") {
            _ = try checkedFixtureText(value,range:CFRange(location:0,length:0),openCode:true,initial:false,allowClearedLF:true)
        }
    }
    try checkedOpenCodeEmptyIndicators(placeholderCount:1,sendEnabled:[false])
    addedChecks += 1
    for count in [0,2] {
        try expectFailure("opencode_empty_ui_not_confirmed") {
            try checkedOpenCodeEmptyIndicators(placeholderCount:count,sendEnabled:[false])
        }
    }
    for enabled: [Bool] in [[],[true],[false,false],[false,true]] {
        try expectFailure("opencode_empty_ui_not_confirmed") {
            try checkedOpenCodeEmptyIndicators(placeholderCount:1,sendEnabled:enabled)
        }
    }
    var emptyPolicy = OpenCodeEmptyState()
    let emptyText = try checkedFixtureText("",range:CFRange(location:0,length:0),openCode:true,initial:true)
    emptyPolicy.observe(emptyText)
    guard !emptyPolicy.allowsLF else { try fail("opencode_initial_lf_epoch_accepted") }
    addedChecks += 1
    emptyPolicy.beginClear()
    emptyPolicy.observe(nonempty)
    guard emptyPolicy.allowsLF, emptyPolicy.clearPending, !emptyPolicy.clearedEmpty
    else { try fail("opencode_pending_clear_lost") }
    addedChecks += 1
    emptyPolicy.observe(emptyText)
    emptyPolicy.endClear()
    guard emptyPolicy.allowsLF, !emptyPolicy.clearPending, emptyPolicy.clearedEmpty
    else { try fail("opencode_cleared_empty_epoch_lost") }
    addedChecks += 1
    emptyPolicy.observe(nonempty)
    guard !emptyPolicy.allowsLF else { try fail("opencode_nonempty_lf_epoch_retained") }
    addedChecks += 1
    emptyPolicy.beginClear()
    emptyPolicy.endClear()
    guard !emptyPolicy.allowsLF else { try fail("opencode_unconfirmed_lf_epoch_retained") }
    addedChecks += 1
    func routeEvent(marker: Int64 = driverMarker, source: Int64 = 11, target: Int64 = 22,
                    type: CGEventType = .keyDown, key: CGKeyCode = 5, flags: CGEventFlags = []) -> FixtureRouteEvent {
        FixtureRouteEvent(type:type,key:key,flags:flags,marker:marker,sourcePID:source,targetPID:target)
    }
    func routePolicy(engine: pid_t? = 33) -> FixtureRoutePolicy {
        FixtureRoutePolicy(fixturePID:22,driverPID:11,typeTunePID:engine)
    }
    var permitted = routePolicy()
    guard permitted.permits(routeEvent()), permitted.reason == nil, permitted.allowed == 1 else { try fail("route_driver_match_failed") }
    addedChecks += 1
    for event in [routeEvent(marker:123,source:11,target:99),routeEvent(marker:driverMarker,source:44,target:99),
                  routeEvent(marker:123,source:33,target:99)] {
        var policy = routePolicy()
        guard policy.permits(event), policy.reason == nil, policy.allowed == 0, policy.blocked == 0
        else { try fail("route_unrelated_event_captured") }
        addedChecks += 1
    }
    var off = routePolicy(engine:nil)
    guard off.permits(routeEvent(marker:fixtureTypeTuneOwnMarker,source:33,target:99)), off.reason == nil
    else { try fail("route_inactive_engine_captured") }
    addedChecks += 1
    for target: Int64 in [0,-1,99] {
        var policy = routePolicy()
        guard !policy.permits(routeEvent(target:target)), policy.reason == "route_guard_wrong_target",
              policy.firstFailureEvent?.targetPID == target, policy.wrongTarget == 1,
              !policy.permits(routeEvent()), policy.blocked == 2 else { try fail("route_wrong_target_not_latched") }
        addedChecks += 1
    }
    for event in [routeEvent(marker:fixtureTypeTuneOwnMarker,source:33),
                  routeEvent(marker:fixtureTypeTuneReplayMarker,source:33),
                  routeEvent(marker:fixtureTypeTuneReplayMarker,source:11)] {
        var policy = routePolicy()
        guard policy.permits(event), policy.reason == nil else { try fail("route_verified_engine_failed") }
        addedChecks += 1
    }
    for event in [routeEvent(marker:fixtureTypeTuneOwnMarker,source:0),
                  routeEvent(marker:fixtureTypeTuneOwnMarker,source:11),
                  routeEvent(marker:fixtureTypeTuneReplayMarker,source:0),
                  routeEvent(marker:fixtureTypeTuneReplayMarker,source:44)] {
        var policy = routePolicy()
        guard !policy.permits(event), policy.reason == "route_guard_engine_source_unknown", policy.unknownSource == 1,
              policy.firstFailureEvent?.sourcePID == event.sourcePID else { try fail("route_unknown_engine_source_accepted") }
        addedChecks += 1
    }
    var cleanup = routePolicy()
    _ = cleanup.permits(routeEvent(target:99))
    cleanup.cleanup = true; cleanup.cleanupRemaining = [5,56]
    guard cleanup.permits(routeEvent(type:.keyUp)), cleanup.cleanupRemaining == [56],
          cleanup.permits(routeEvent(type:.flagsChanged,key:56)), cleanup.cleanupRemaining.isEmpty,
          cleanup.reason == "route_guard_wrong_target" else { try fail("route_cleanup_release_failed") }
    addedChecks += 1
    for event in [routeEvent(type:.keyDown),routeEvent(type:.keyUp,key:6),
                  routeEvent(type:.flagsChanged,key:56,flags:.maskShift),
                  routeEvent(type:.keyUp,flags:.maskCommand),routeEvent(target:99,type:.keyUp),
                  routeEvent(marker:fixtureTypeTuneOwnMarker,source:33,type:.keyUp)] {
        var policy = routePolicy(); policy.latch("failure"); policy.cleanup = true; policy.cleanupRemaining = [5,56]
        guard !policy.permits(event), policy.cleanupRemaining == [5,56] else { try fail("route_cleanup_scope_broadened") }
        addedChecks += 1
    }
    var plainCleanup = routePolicy(); plainCleanup.cleanup = true; plainCleanup.cleanupRemaining = [5]
    guard plainCleanup.permits(routeEvent(type:.keyUp)), plainCleanup.cleanupRemaining.isEmpty,
          !plainCleanup.permits(routeEvent(type:.keyUp)) else { try fail("route_cleanup_repeated_release_accepted") }
    addedChecks += 1
    var delivered = routePolicy()
    guard delivered.permits(routeEvent()), delivered.deliveredDriverKeys == [5],
          !delivered.permits(routeEvent(target:99,type:.keyUp)), delivered.deliveredDriverKeys == [5]
    else { try fail("route_blocked_up_lost_delivered_key") }
    delivered.cleanup = true; delivered.cleanupRemaining = delivered.deliveredDriverKeys
    guard delivered.permits(routeEvent(type:.keyUp)), delivered.deliveredDriverKeys.isEmpty,
          delivered.cleanupRemaining.isEmpty else { try fail("route_delivered_key_cleanup_failed") }
    addedChecks += 1
    var balanced = routePolicy()
    guard balanced.permits(routeEvent()), balanced.permits(routeEvent(type:.keyUp)),
          balanced.deliveredDriverKeys.isEmpty else { try fail("route_allowed_up_not_balanced") }
    addedChecks += 1
    var stopped = routePolicy(); stopped.latch("route_guard_tap_disabled")
    guard !stopped.permits(routeEvent()), stopped.reason == "route_guard_tap_disabled"
    else { try fail("route_disabled_tap_policy_failed") }
    addedChecks += 1
    emit(["status":"PASS","mode":"self-check","events_posted":0,"test_count":23+addedChecks,
          "note":"HID key-state behavior requires an authorized live fixture; event construction alone does not verify it."])
}

do {
    let options = try Options(Array(CommandLine.arguments.dropFirst()))
    if options.selfCheck { try selfCheck() }
    else {
        let driver = try Driver(options)
        defer { driver.routeGuard.stop() }
        do {
            try driver.activateIfRequested()
            if options.inspect { try driver.inspect() } else { try driver.run() }
            try driver.pause(50)
            try driver.checkRouteAndEngine()
        }
        catch {
            driver.releaseOnFailure()
            emit(["status":"STOPPED","events_posted":driver.posted,"shift_samples":driver.shiftSamples,"route_guard":driver.routeGuard.metadata(),"snapshot_retry":driver.snapshotRetryMetadata()])
            throw error
        }
    }
} catch let error as CheckFailure {
    emit(["status":"ERROR","reason":error.code]); exit(1)
} catch {
    emit(["status":"ERROR","reason":"unexpected_driver_error"]); exit(1)
}
