// Isolated Terminal fixture driver. The independent oracle is the text/caret
// actually received by macos-terminal-fixture.py through the PTY. It is not
// physical-keyboard, shell, visual-screen-caret, or arbitrary TUI acceptance.
import AppKit
import Carbon
import ApplicationServices
import Darwin

struct CheckFailure: Error { let code: String }
func fail(_ code: String) throws -> Never { throw CheckFailure(code: code) }
func emit(_ value: [String: Any]) {
    if let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
       let text = String(data: data, encoding: .utf8) { print(text); fflush(stdout) }
}
let fixturePrefix = "TypeTune Native Check"
let fixtureWords = ["", "hello ", "ghbdtn", "привет", "Ghbdtn", "Привет", "ghbdtn ", "привет ",
    "ghbdtn  ", "привет  ", "Ghbdtn ", "Привет ", "ghbdtn ghbdtn ", "привет привет ",
    "ghbdtn привет ", "привет ghbdtn ", "ghbdtn ghbdtn  ", "привет привет  "]
let allowedText: Set<String> = Set(fixtureWords.flatMap { word in (0...word.count).map { String(word.prefix($0)) } })
let abc = "com.apple.keylayout.ABC"
let russian = "com.apple.keylayout.RussianWin"
let keyCodes: [Character: CGKeyCode] = ["a":0,"s":1,"d":2,"f":3,"h":4,"g":5,"z":6,"x":7,"c":8,"v":9,
    "b":11,"q":12,"w":13,"e":14,"r":15,"y":16,"t":17,"1":18,"2":19,"3":20,"4":21,"6":22,"5":23,
    "9":25,"7":26,"8":28,"0":29,"o":31,"u":32,"i":34,"p":35,"l":37,"j":38,"k":40,"n":45,"m":46," ":49]
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
    var runDirectory = ""
    var runID = ""
    var pid: pid_t = 0
    var bundle = ""
    var title = ""
    var scenario = "manual"
    var repetitions = 1
    var keyDelay = 15
    var nextDelay = 25
    init(_ arguments: [String]) throws {
        var index = 0
        while index < arguments.count {
            let option = arguments[index]; index += 1
            if option == "--inspect" { inspect = true; continue }
            if option == "--self-check" { selfCheck = true; continue }
            if option == "--activate" { activate = true; continue }
            if option == "--observed" { observed = true; continue }
            guard index < arguments.count else { try fail("missing_option_value") }
            let value = arguments[index]; index += 1
            switch option {
            case "--pid": pid = pid_t(value) ?? 0
            case "--bundle": bundle = value
            case "--title": title = value
            case "--run-dir": runDirectory = value
            case "--run-id": runID = value
            case "--scenario": scenario = value
            case "--repeat": repetitions = Int(value) ?? 0
            case "--key-delay-ms": keyDelay = Int(value) ?? -1
            case "--next-delay-ms": nextDelay = Int(value) ?? -1
            default: try fail("unknown_option")
            }
        }
        if selfCheck { return }
        guard pid > 0, bundle == "com.apple.Terminal", title.hasPrefix(fixturePrefix), title.count <= 128,
              runDirectory.hasPrefix("/"), runID.range(of:"^[a-f0-9]{32}$",options:.regularExpression) != nil,
              title == "TypeTune Native Check Terminal " + runID,
              ["auto","manual","retoggle","spaces","case","nextword"].contains(scenario),
              (1...30).contains(repetitions), (0...100).contains(keyDelay), (0...300).contains(nextDelay)
        else { try fail("invalid_arguments_or_fixture_title") }
    }
}


struct OracleState: Decodable {
    let version: Int
    let run_id: String
    let title: String
    let helper_pid: pid_t
    let uid: uid_t
    let tty: String
    let foreground: Bool
    let updated_unix_ms: Double
    let revision: UInt64
    let received_bytes: UInt64
    let pending_utf8_bytes: Int
    let value: String
    let caret_utf16: Int
    let selection_length: Int
    let status: String
}

final class OracleReader {
    let path: String
    let runID: String
    let title: String
    private var directoryIdentity: (dev_t,ino_t)?
    private var tty: String?
    private var revision: UInt64 = 0
    private var byteCount: UInt64 = 0
    private(set) var helperPID: pid_t = 0
    private let foregroundCheck: (pid_t,String) -> Bool
    init(path: String, runID: String, title: String,
         foregroundCheck: @escaping (pid_t,String) -> Bool = OracleReader.isForegroundHelper) {
        self.path=path; self.runID=runID; self.title=title
        self.foregroundCheck=foregroundCheck
    }
    static func isForegroundHelper(_ pid: pid_t, _ tty: String) -> Bool {
        // Query only metadata; do not read bytes, alter termios or acquire a TTY.
        let fd=Darwin.open(tty,O_RDONLY|O_NOCTTY|O_NOFOLLOW|O_NONBLOCK)
        guard fd >= 0 else { return false }
        defer { Darwin.close(fd) }
        var info=stat()
        let group=getpgid(pid)
        return fstat(fd,&info) == 0 && info.st_mode & mode_t(S_IFMT) == mode_t(S_IFCHR)
            && group > 0 && tcgetpgrp(fd) == group
    }
    func read() throws -> OracleState {
        let directory = Darwin.open(path,O_RDONLY|O_DIRECTORY|O_NOFOLLOW)
        guard directory >= 0 else { try fail("oracle_directory_unavailable") }
        defer { Darwin.close(directory) }
        var info = stat()
        guard fstat(directory,&info) == 0,
              info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              info.st_mode & 0o777 == 0o700, info.st_uid == getuid() else { try fail("unsafe_oracle_directory") }
        if let identity=directoryIdentity {
            guard identity.0 == info.st_dev, identity.1 == info.st_ino else { try fail("oracle_directory_changed") }
        } else { directoryIdentity=(info.st_dev,info.st_ino) }
        let file = openat(directory,"state.json",O_RDONLY|O_NOFOLLOW)
        guard file >= 0 else { try fail("oracle_state_unavailable") }
        defer { Darwin.close(file) }
        guard fstat(file,&info) == 0,
              info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              info.st_mode & 0o777 == 0o600, info.st_uid == getuid(), info.st_nlink == 1,
              info.st_size > 0, info.st_size <= 8192 else { try fail("unsafe_oracle_state") }
        var bytes = [UInt8](repeating:0,count:Int(info.st_size))
        let count = bytes.withUnsafeMutableBytes { Darwin.read(file,$0.baseAddress,$0.count) }
        guard count == bytes.count else { try fail("oracle_read_incomplete") }
        guard let state = try? JSONDecoder().decode(OracleState.self,from:Data(bytes)) else { try fail("oracle_invalid_json") }
        let age = Date().timeIntervalSince1970*1000-state.updated_unix_ms
        guard state.version == 1, state.run_id == runID, state.title == title,
              state.uid == getuid(), state.helper_pid > 1 else { try fail("oracle_identity_mismatch") }
        guard age.isFinite, age >= -1000, age <= 500 else { try fail("oracle_stale") }
        guard state.status == "ready", state.foreground, kill(state.helper_pid,0) == 0 else { try fail("oracle_helper_not_ready") }
        guard state.tty.range(of:"^/dev/ttys[0-9A-Za-z]+$",options:.regularExpression) != nil else { try fail("oracle_invalid_tty") }
        guard foregroundCheck(state.helper_pid,state.tty) else { try fail("oracle_foreground_not_confirmed") }
        if helperPID != 0 {
            guard helperPID == state.helper_pid, tty == state.tty else { try fail("oracle_helper_changed") }
        } else { helperPID=state.helper_pid; tty=state.tty }
        guard state.revision >= revision, state.received_bytes >= byteCount else { try fail("oracle_state_went_backwards") }
        guard allowedText.contains(state.value), state.caret_utf16 == state.value.utf16.count,
              state.selection_length == 0, (0...3).contains(state.pending_utf8_bytes) else { try fail("oracle_fixture_state_invalid") }
        revision=state.revision; byteCount=state.received_bytes
        return state
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
struct Snapshot {
    let element: AXUIElement
    let value: String
    let range: CFRange
    let role: String
    let utf8Complete: Bool
}

final class Driver {
    let options: Options
    let deadline = ProcessInfo.processInfo.systemUptime + 180
    var focus: AXUIElement?
    var focusWindow: AXUIElement?
    let oracle: OracleReader
    var posted = 0
    var axPreparationSelections = 0
    var lastPostAt = ProcessInfo.processInfo.systemUptime
    var shiftSamples: [[String: Any]] = []
    var pressedByDriver: Set<CGKeyCode> = []
    let source: CGEventSource
    init(_ options: Options) throws {
        self.options = options
        self.oracle = OracleReader(path:options.runDirectory,runID:options.runID,title:options.title)
        guard let source = CGEventSource(stateID: .hidSystemState) else { try fail("cannot_create_synthetic_event_source") }
        self.source = source
        source.localEventsSuppressionInterval = 0
    }
    func pause(_ milliseconds: Int) throws {
        guard ProcessInfo.processInfo.systemUptime < deadline else { try fail("driver_deadline") }
        RunLoop.current.run(until: Date().addingTimeInterval(Double(milliseconds)/1000))
    }
    func snapshot(bind: Bool = false, requireFrontmost: Bool = true) throws -> Snapshot {
        let settleDeadline = min(deadline,ProcessInfo.processInfo.systemUptime + 0.1)
        while true {
            do { return try snapshotOnce(bind:bind,requireFrontmost:requireFrontmost) }
            catch let error as CheckFailure where ["invalid_ax_selection","ax_snapshot_changing",
                "ax_focused_window_unavailable","ax_window_title_unavailable","focused_ax_element_unavailable",
                "ax_role_unavailable","ax_value_unavailable","ax_selection_unavailable"].contains(error.code) {
                // AXValue and AXSelectedTextRange are independent reads. During
                // deletion they can briefly describe different editor frames.
                // Retry reads only; every attempt repeats all fixture guards.
                guard ProcessInfo.processInfo.systemUptime < settleDeadline else { throw error }
                try pause(5)
            }
        }
    }
    private func snapshotOnce(bind: Bool, requireFrontmost: Bool) throws -> Snapshot {
        guard ProcessInfo.processInfo.systemUptime < deadline else { try fail("driver_deadline") }
        guard AXIsProcessTrusted() else { try fail("driver_accessibility_permission_missing") }
        guard !IsSecureEventInputEnabled() else { try fail("secure_input_enabled") }
        guard let app = NSRunningApplication(processIdentifier:options.pid), app.bundleIdentifier == options.bundle
        else { try fail("target_pid_or_bundle_mismatch") }
        if requireFrontmost && NSWorkspace.shared.frontmostApplication?.processIdentifier != options.pid {
            try fail("target_pid_or_bundle_not_frontmost")
        }
        let application = AXUIElementCreateApplication(options.pid)
        AXUIElementSetMessagingTimeout(application,0.05)
        guard let window = elementAttribute(application,kAXFocusedWindowAttribute)
        else { try fail("ax_focused_window_unavailable") }
        if let bound=focusWindow, !CFEqual(bound,window) { try fail("fixture_window_changed") }
        if bind { focusWindow=window }
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
        if bind { focus = element }
        guard let role = attribute(element,kAXRoleAttribute) as? String else { try fail("ax_role_unavailable") }
        let subrole = attribute(element,kAXSubroleAttribute) as? String ?? ""
        // Terminal role must first be observed in the isolated fixture. Do not
        // relax this to a search field or window-wide keyboard target.
        guard role == kAXTextAreaRole, subrole != kAXSecureTextFieldSubrole else { try fail("focused_element_not_plain_text") }
        let state = try oracle.read()
        return Snapshot(element:element,value:state.value,
                        range:CFRange(location:state.caret_utf16,length:state.selection_length),role:role,
                        utf8Complete:state.pending_utf8_bytes == 0)
    }
    func activateIfRequested() throws {
        guard options.activate else { return }
        // First inspect the exact existing fixture without changing focus. Only
        // then may we raise its window and activate that same process.
        _ = try snapshot(bind:true,requireFrontmost:false)
        let application = AXUIElementCreateApplication(options.pid)
        AXUIElementSetMessagingTimeout(application,0.05)
        guard let window = elementAttribute(application,kAXFocusedWindowAttribute),
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
              "oracle":"independent_pty_editor","helper_pid":oracle.helperPID,
              "layout":currentLayout(),"accessibility":AXIsProcessTrusted(),"post":CGPreflightPostEventAccess(),
              "listen":CGPreflightListenEventAccess(),"pid":options.pid,"bundle":options.bundle,"events_posted":posted,
              "shift_hid_down":CGEventSource.keyState(.hidSystemState,key:56),
              "shift_session_down":CGEventSource.keyState(.combinedSessionState,key:56)])
    }
    func post(_ event: CGEvent) throws {
        _ = try snapshot()
        guard CGPreflightPostEventAccess() else { try fail("driver_post_permission_missing") }
        event.setIntegerValueField(.eventSourceUserData,value:driverMarker)
        // Do not overwrite eventSourceUnixProcessID or label this physical input.
        // AX/TCC checks can outlive a layout switch. Resolve plain-key Unicode
        // only now; no AX query or wait follows this refresh before posting.
        try refreshFixtureUnicode(event,layout:currentLayout)
        event.post(tap:.cghidEventTap)
        lastPostAt = ProcessInfo.processInfo.systemUptime
        posted += 1
        let code = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        if event.type == .keyDown || (event.type == .flagsChanged &&
            ((code == 56 && event.flags.contains(.maskShift)) || (code == 59 && event.flags.contains(.maskControl)))) {
            pressedByDriver.insert(code)
        } else { pressedByDriver.remove(code) }
    }
    func releaseOnFailure() {
        // Balance only keys this driver pressed, using natural CGEvent key-up
        // payloads and the captured PID, never another foreground app. No new
        // key-down/shortcut is allowed after a fixture guard has failed.
        guard NSRunningApplication(processIdentifier:options.pid)?.bundleIdentifier == options.bundle else { return }
        for code in pressedByDriver {
            guard let event = CGEvent(keyboardEventSource:source,virtualKey:code,keyDown:false) else { continue }
            event.flags=[]
            if code == 56 || code == 59 { event.type = .flagsChanged }
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
    func control(_ down: Bool) throws {
        guard let event = CGEvent(keyboardEventSource:source,virtualKey:59,keyDown:down) else { try fail("event_allocation_failed") }
        event.type = .flagsChanged
        event.flags = down ? CGEventFlags(rawValue:CGEventFlags.maskControl.rawValue | 0x1) : []
        try post(event)
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
            if state.utf8Complete, state.value == value, state.range.location == value.utf16.count, state.range.length == 0,
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
            guard state.utf8Complete, state.value == value, state.range.location == value.utf16.count, state.range.length == 0,
                  currentLayout() == layout else {
                try assertionFailure(state,expected:value,reason:"result_changed_after_first_match")
            }
            let elapsed = ProcessInfo.processInfo.systemUptime-start
            if elapsed >= 0.5 { return elapsed*1000 }
            try pause(10)
        } while true
    }
    func clearFixture() throws {
        _ = try snapshot()
        // Ctrl+U is an explicit command of the isolated editor, never a shell.
        // Real modifier edges also invalidate the switcher's typing history.
        try control(true); try key(32,flags:.maskControl); try control(false)
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
        _ = try waitFor("hello ",layout:abc)
        // PTY can show hello before the switcher processes its Space. Keep the
        // fixture still so Ctrl+U cannot make that warmup event stale. This is
        // preparation; scenario latency starts only after prepare() returns.
        _ = try confirmStable("hello ",layout:abc)
        try clearFixture()
    }
    func run() throws {
        _ = try snapshot(bind:true)
        guard CGPreflightPostEventAccess() else { try fail("driver_post_permission_missing") }
        guard CGEventSource.flagsState(.combinedSessionState).intersection([.maskShift,.maskControl,.maskAlternate,.maskCommand,.maskAlphaShift]).isEmpty else { try fail("physical_modifier_or_caps_held") }
        emit(["status":"START","origin":"synthetic_hidSystemState","source_pid_overridden":false,
              "oracle":"independent_pty_editor","helper_pid":oracle.helperPID,
              "driver_pid":ProcessInfo.processInfo.processIdentifier,"target_pid":options.pid,"scenario":options.scenario,"repetitions":options.repetitions])
        // Activation is setup, not measured input. Let observers establish the
        // new field before warmup; no keys may race the focus transition.
        let initial = try snapshot()
        _ = try confirmStable(initial.value, layout: currentLayout())
        for iteration in 1...options.repetitions {
            if iteration > 1 { try pause(150) }
            try prepare()
            let started = ProcessInfo.processInfo.systemUptime
            try type(options.scenario == "case" ? "Ghbdtn" : "ghbdtn")
            let triggerAt = ProcessInfo.processInfo.systemUptime
            var expected = "привет", expectedLayout = russian
            switch options.scenario {
            case "manual": try doubleShift()
            case "retoggle":
                try doubleShift(); _ = try waitFor("привет",layout:russian)
                try doubleShift(); expected="ghbdtn"; expectedLayout=abc
            case "spaces":
                try key(49); try key(49); expected="привет  "
            case "case": try key(49); expected="Привет "
            case "nextword":
                try key(49); try pause(options.nextDelay)
                try type("ghbdtn "); expected="привет привет "
            default: try key(49); expected="привет "
            }
            let settle = try waitFor(expected,layout:expectedLayout)
            let firstMatchAt = ProcessInfo.processInfo.systemUptime
            // The final assertion must remain true without any further input.
            // Clearing and the first retoggle assertion keep their fast path;
            // warmup settles separately before scenario timing begins.
            let stableWindow = try confirmStable(expected,layout:expectedLayout)
            emit(["status":"PASS","scenario":options.scenario,"iteration":iteration,"expected_fixture":expected,
                  "text_match":true,"caret_match":true,"caret_oracle":"fixture_logical_utf16",
                  "oracle":"independent_pty_editor","layout_match":true,"layout":currentLayout(),
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


func oracleSelfCheck() throws {
    let directory = NSTemporaryDirectory()+"TypeTuneTerminalSelfCheck-"+UUID().uuidString
    guard mkdir(directory,0o700) == 0 else { try fail("self_check_directory_failed") }
    defer { try? FileManager.default.removeItem(atPath:directory) }
    let identifier=String(repeating:"a",count:32), title="TypeTune Native Check Terminal "+String(repeating:"a",count:32)
    var state: [String:Any] = ["version":1,"run_id":identifier,"title":title,
        "helper_pid":getpid(),"uid":getuid(),"tty":"/dev/ttys000","foreground":true,
        "updated_unix_ms":Date().timeIntervalSince1970*1000,"revision":0,"received_bytes":0,
        "value":"","caret_utf16":0,"selection_length":0,"pending_utf8_bytes":0,"status":"ready"]
    let path=directory+"/state.json"
    func writeState() throws {
        let data=try JSONSerialization.data(withJSONObject:state)
        try data.write(to:URL(fileURLWithPath:path),options:.atomic)
        guard chmod(path,0o600) == 0 else { try fail("self_check_mode_failed") }
    }
    func rejects(_ reason:String,_ body:() throws -> Void) throws {
        do { try body(); try fail("unsafe_oracle_accepted") }
        catch let error as CheckFailure where error.code == reason {}
    }
    try writeState()
    let oracle=OracleReader(path:directory,runID:identifier,title:title,foregroundCheck:{_,_ in true})
    guard try oracle.read().value.isEmpty else { try fail("oracle_self_check_failed") }
    state["run_id"]=String(repeating:"b",count:32);try writeState()
    try rejects("oracle_identity_mismatch") {_ = try oracle.read()}
    state["run_id"]=identifier;state["updated_unix_ms"]=0;try writeState()
    try rejects("oracle_stale") {_ = try oracle.read()}
    state["updated_unix_ms"]=Date().timeIntervalSince1970*1000;try writeState()
    guard chmod(path,0o644) == 0 else { try fail("self_check_mode_failed") }
    try rejects("unsafe_oracle_state") {_ = try oracle.read()}
    guard chmod(path,0o600) == 0 else { try fail("self_check_mode_failed") }
    state["foreground"]=false;try writeState()
    try rejects("oracle_helper_not_ready") {_ = try oracle.read()}
    let link=directory+"/linked-run"
    guard symlink(directory,link) == 0 else { try fail("self_check_symlink_failed") }
    try rejects("oracle_directory_unavailable") {
        _ = try OracleReader(path:link,runID:identifier,title:title).read()
    }
}

func selfCheck() throws {
    guard allowedText.contains(""), allowedText.contains("ghbdtn"), allowedText.contains("привет привет "),
          !allowedText.contains("private document"), !allowedText.contains("ghbdtn\n"),
          keyCodes["g"] == 5, ruCharacters["g"] == "п", ruCharacters["n"] == "т",
          driverMarker & 0x7fff000000000000 != 0x5454000000000000 else { try fail("self_check_failed") }
    do { _ = try Options(["--pid","1","--bundle","fixture","--title","Ordinary document"]); try fail("unsafe_title_accepted") }
    catch let error as CheckFailure where error.code == "invalid_arguments_or_fixture_title" {}
    let valid = try Options(["--pid","1","--bundle","com.apple.Terminal","--title","TypeTune Native Check Terminal "+String(repeating:"a",count:32),"--repeat","30","--run-dir","/tmp/fixture","--run-id",String(repeating:"a",count:32)])
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
    try oracleSelfCheck()
    emit(["status":"PASS","mode":"self-check","events_posted":0,"test_count":26,
          "note":"HID key-state behavior requires an authorized live fixture; event construction alone does not verify it."])
}

do {
    let options = try Options(Array(CommandLine.arguments.dropFirst()))
    if options.selfCheck { try selfCheck() }
    else {
        let driver = try Driver(options)
        do {
            try driver.activateIfRequested()
            if options.inspect { try driver.inspect() } else { try driver.run() }
        }
        catch {
            driver.releaseOnFailure()
            emit(["status":"STOPPED","events_posted":driver.posted,"shift_samples":driver.shiftSamples])
            throw error
        }
    }
} catch let error as CheckFailure {
    emit(["status":"ERROR","reason":error.code]); exit(1)
} catch {
    emit(["status":"ERROR","reason":"unexpected_driver_error"]); exit(1)
}
