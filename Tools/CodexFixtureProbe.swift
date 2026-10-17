import AppKit
import ApplicationServices
import Carbon
import LayoutPilotCore

// Explicitly authorized isolated LP-CODEX-001 browser fixture ONLY.
// Activates only Chrome once; authenticates the exact fixture URL/field. No conversation fields or Enter key.
struct Failure: Error { let reason: String }
func require(_ ok: Bool, _ reason: String) throws { if !ok { throw Failure(reason: reason) } }
var axErrors: [String: Int] = [:]
func attr(_ e: AXUIElement, _ key: String) -> CFTypeRef? {
    AXUIElementSetMessagingTimeout(e, 0.15)
    var v: CFTypeRef?; let status = AXUIElementCopyAttributeValue(e,key as CFString,&v); if status != .success { axErrors["\(key):\(status.rawValue)", default:0] += 1 }; return status == .success ? v : nil
}
func element(_ v: CFTypeRef?) -> AXUIElement? { guard let v, CFGetTypeID(v)==AXUIElementGetTypeID() else{return nil};return (v as! AXUIElement) }
func pause(_ s: Double) { RunLoop.current.run(until: Date(timeIntervalSinceNow:s)) }
let fixtureURL="http://127.0.0.1:18763/?fixture=LP-CODEX-001"
@main struct FixtureProbe {
 static func main() {
  var failureDiagnostics: (() -> [String:Any])?
  do {
   let mode=CommandLine.arguments.dropFirst().first ?? "read"
   if mode.hasPrefix("omnibox-") {
    try require(CommandLine.arguments.count == 3, "omnibox_report_required")
    try OmniboxProbe.run(mode, reportPath: CommandLine.arguments[2]); return
   }
   try require(["read","old","unicode","production","production-noop","type-wrong","type-correct","type-stream","clear","type-excluded","cleanup-modifiers","type-yo","type-typo","post-paste-space","type-manual"].contains(mode),"invalid_mode")
   try require(AXIsProcessTrusted() && CGPreflightPostEventAccess() && !IsSecureEventInputEnabled(),"permissions_or_secure_input")
   guard let app=NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.google.Chrome" }) else { throw Failure(reason:"chrome_not_running") }
   _ = app.activate(options: []); pause(0.5)
   try require(NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier,"fixture_host_not_frontmost")
   try require(app.bundleIdentifier=="com.google.Chrome","fixture_host_not_frontmost")
   let application=AXUIElementCreateApplication(app.processIdentifier)
   guard let field=element(attr(application,kAXFocusedUIElementAttribute)), let window=element(attr(field,kAXWindowAttribute)) else {throw Failure(reason:"no_focused_field")}
   func authenticated() throws {
    try require(!IsSecureEventInputEnabled() && AXIsProcessTrusted() && CGPreflightPostEventAccess(),"permissions_changed")
    try require(NSWorkspace.shared.frontmostApplication?.processIdentifier==app.processIdentifier,"focus_changed")
    guard let current=element(attr(application,kAXFocusedUIElementAttribute)),let win=element(attr(current,kAXWindowAttribute)) else {throw Failure(reason:"focus_unavailable")}
    try require(CFEqual(field,current) && CFEqual(window,win),"field_or_window_changed")
    try require(["LP-CODEX-001 rich", "LP-CODEX-001 plain", "LP-CODEX-001 single"].contains(attr(field,kAXDescriptionAttribute) as? String ?? ""),"not_fixture_field")
    try require((attr(field,kAXSubroleAttribute) as? String) != kAXSecureTextFieldSubrole,"secure_fixture_field")
    var ancestor: AXUIElement?=field;var matched=false
    for _ in 0..<20 {
      guard let a=ancestor else{break}
      if let raw=attr(a,kAXURLAttribute) {
       let url=(raw as? URL)?.absoluteString ?? (raw as? String) ?? ""
       if url==fixtureURL {matched=true;break}
      }
      ancestor=element(attr(a,kAXParentAttribute))
    }
    try require(matched,"not_isolated_fixture_url")
   }
   func snapshot() throws -> [String:Any] {
    try authenticated()
    guard let text=attr(field,kAXValueAttribute) as? String, text.utf16.count<256 else{throw Failure(reason:"fixture_value_unavailable")}
    var range=CFRange();guard let v=attr(field,kAXSelectedTextRangeAttribute),CFGetTypeID(v)==AXValueGetTypeID(),AXValueGetValue(v as! AXValue,.cfRange,&range) else{throw Failure(reason:"fixture_selection_unavailable")}
    return ["text":text,"location":range.location,"length":range.length]
   }
   if mode == "type-manual" {
    // This branch deliberately keeps the exact same isolated Chrome identity
    // guard. No clipboard, Return, conversation target, or modifier cleanup.
    let modifierKeys: [CGKeyCode] = [55,54,56,60,58,61,59,62,57,63]
    let activeMask: CGEventFlags = [.maskShift,.maskControl,.maskAlternate,.maskCommand,.maskAlphaShift,.maskSecondaryFn,.maskHelp]
    let deviceSideMask: UInt64 = 0x20ff
    var ownsShiftDown = false
    var emittedFrames: [[String:Any]] = []
    func modifiersAllowed(allowOwnShift: Bool = false) -> Bool {
     let allowed: UInt64 = allowOwnShift ? CGEventFlags.maskShift.rawValue | 0x2 : 0
     let checked = activeMask.rawValue | deviceSideMask
     // Both HID and combined state must contain only neutral or our own
     // tracked left Shift. A delayed zero state must not prevent its release.
     return [CGEventSourceStateID.hidSystemState,.combinedSessionState].allSatisfy {
      CGEventSource.flagsState($0).rawValue & checked & ~allowed == 0
     } && modifierKeys.filter { !allowOwnShift || $0 != 56 }.allSatisfy {
       !CGEventSource.keyState(.hidSystemState,key:$0) && !CGEventSource.keyState(.combinedSessionState,key:$0)
      }
    }
    func guarded() throws {
     try authenticated()
     try require(modifiersAllowed(allowOwnShift:ownsShiftDown),"manual_foreign_or_unexpected_modifier")
    }
    failureDiagnostics = {
     ["finalModifiersNeutral": !ownsShiftDown && modifiersAllowed(),
      "ownedShiftPending": ownsShiftDown,
      "emittedFrameCount": emittedFrames.count,
      "hidModifierFlags": CGEventSource.flagsState(.hidSystemState).rawValue,
      "combinedModifierFlags": CGEventSource.flagsState(.combinedSessionState).rawValue,
      "clipboardUsed": false, "returnEvents": 0]
    }
    func awaitOwnedReleaseNeutral() throws {
     try require(ownsShiftDown,"manual_release_wait_without_owned_press")
     let deadline = ProcessInfo.processInfo.systemUptime + 0.5
     while true {
      try authenticated()
      // Only readonly observation during propagation of our just-posted up.
      // A foreign flag/key fails immediately; no cleanup event is injected.
      try require(modifiersAllowed(allowOwnShift:ownsShiftDown),"manual_foreign_modifier_after_owned_release")
      if modifiersAllowed() { return }
      try require(ProcessInfo.processInfo.systemUptime < deadline,"manual_owned_shift_release_not_neutral")
      pause(0.01)
     }
    }
    let source = CGEventSource(stateID:.privateState)!
    func emit(_ key: CGKeyCode, down: Bool, shiftFrame: Bool = false) throws {
     try guarded()
     try require((shiftFrame && key == 56) || (!shiftFrame && [5,4,11,2,17,45,49,51].contains(key)),"manual_key_not_allowed")
     if shiftFrame { try require(ownsShiftDown != down,"manual_unowned_shift_release_or_duplicate_press") }
     let event = CGEvent(keyboardEventSource:source,virtualKey:key,keyDown:down)!
     event.flags = shiftFrame && down ? CGEventFlags(rawValue: CGEventFlags.maskShift.rawValue | 0x2) : []
     if shiftFrame { event.type = .flagsChanged }
     // Only our balanced, locally tracked Shift frame may be released. On a
     // failed identity guard no fallback event is sent to a different target.
     event.post(tap:.cghidEventTap)
     if shiftFrame && down { ownsShiftDown = true }
     emittedFrames.append(["keyCode":Int(key),"down":down,"flagsChanged":shiftFrame,"flags":event.flags.rawValue,"uptime":ProcessInfo.processInfo.systemUptime])
     pause(0.025)
     if shiftFrame && !down {
      try awaitOwnedReleaseNeutral()
      ownsShiftDown = false
     }
    }
    func select(_ range: CFRange, expectedText: String) throws -> [String:Any] {
     try guarded()
     let before = try snapshot()
     try require(before["text"] as? String == expectedText,"manual_selection_text_changed_before_write")
     guard let oldLocation = before["location"] as? Int, let oldLength = before["length"] as? Int,
      oldLocation >= 0, oldLength >= 0, oldLocation <= expectedText.utf16.count,
      oldLength <= expectedText.utf16.count - oldLocation else { throw Failure(reason:"manual_selection_old_range_invalid") }
     try guarded()
     var range = range
     try require(AXUIElementSetAttributeValue(field,kAXSelectedTextRangeAttribute as CFString,AXValueCreate(.cfRange,&range)!) == .success,"manual_selection_write_failed")
     let deadline = ProcessInfo.processInfo.systemUptime + 0.15
     while true {
      try require(ProcessInfo.processInfo.systemUptime <= deadline,"manual_selection_ack_timeout")
      try guarded()
      let observed = try snapshot()
      try require(ProcessInfo.processInfo.systemUptime <= deadline,"manual_selection_ack_timeout")
      try require(observed["text"] as? String == expectedText,"manual_selection_text_changed_during_ack")
      let location = observed["location"] as? Int, length = observed["length"] as? Int
      if location == range.location && length == range.length { return observed }
      try require(location == oldLocation && length == oldLength,"manual_selection_unexpected_range_during_ack")
      pause(min(0.005,max(0,deadline - ProcessInfo.processInfo.systemUptime)))
     }
    }
    try guarded()
    let setup = try snapshot()
    guard let setupText = setup["text"] as? String else { throw Failure(reason:"manual_setup_text_unavailable") }
    let allowedSetup = ["", "\n", "ghbdtn", "ghbdtn ", "ghbdtn  ", "привет", "привет ", "привет  ", "hello  ", "ещё  ", "еще  ", "превет  ", "первая\nвторая\tстрока", "первая\nвторая\tстрока ", String(repeating:"привет ",count:20)+" "]
    try require(allowedSetup.contains(setupText),"manual_setup_not_own_synthetic_text")
    if !setupText.isEmpty && setupText != "\n" {
     let selected = try select(CFRange(location:0,length:setupText.utf16.count),expectedText:setupText)
     try require(selected["text"] as? String == setupText && selected["location"] as? Int == 0 && selected["length"] as? Int == setupText.utf16.count,"manual_clear_selection_not_verified")
     try emit(51,down:true); try emit(51,down:false)
     pause(0.1)
    }
    let initial = try snapshot()
    try require(["", "\n"].contains(initial["text"] as? String ?? "missing"),"manual_requires_empty_fixture")
    if initial["text"] as? String == "\n" {
     // A newline may be Chromium's empty-editor AX representation. Do not
     // silently add a word at a stale selected range.
     let selected = try select(CFRange(location:0,length:1),expectedText:"\n")
     try require(selected["location"] as? Int == 0 && selected["length"] as? Int == 1,"manual_empty_newline_selection_not_verified")
    }
    try guarded()
    let originalSource = InputSources.identifier
    defer { _ = InputSources.restore(identifier:originalSource) }
    try require(InputSources.select(.english),"manual_english_source_unavailable")
    pause(0.2)
    for key: CGKeyCode in [5,4,11,2,17,45] {
     try emit(key,down:true); try emit(key,down:false)
    }
    pause(0.15)
    let typed = try snapshot()
    try require(typed["text"] as? String == "ghbdtn" && typed["location"] as? Int == 6 && typed["length"] as? Int == 0,"manual_typed_word_not_verified")
    let selected = try select(CFRange(location:0,length:6),expectedText:"ghbdtn")
    try require(selected["text"] as? String == "ghbdtn" && selected["location"] as? Int == 0 && selected["length"] as? Int == 6,"manual_exact_word_selection_not_verified")
    pause(0.15)
    for index in 0..<2 {
     try emit(56,down:true,shiftFrame:true)
     pause(0.04)
     try emit(56,down:false,shiftFrame:true)
     if index == 0 { pause(0.07) }
    }
    pause(0.6)
    let corrected = try snapshot()
    let intermediatePassed = corrected["text"] as? String == "привет" && corrected["location"] as? Int == 6 && corrected["length"] as? Int == 0 && !ownsShiftDown && modifiersAllowed()
    // Stop before additional text if the selected word was not corrected.
    if intermediatePassed {
     for _ in 0..<2 { try emit(49,down:true); try emit(49,down:false) }
     pause(0.5)
    }
    let after = try snapshot()
    let neutral = !ownsShiftDown && modifiersAllowed()
    let passed = intermediatePassed && after["text"] as? String == "привет  " && after["location"] as? Int == 8 && after["length"] as? Int == 0 && neutral
    let report: [String:Any] = ["mode":mode,"fixtureURL":fixtureURL,"pid":Int(app.processIdentifier),"before":initial,"typed":typed,"selected":selected,"afterManual":corrected,"after":after,"intermediatePassed":intermediatePassed,"passed":passed,"finalModifiersNeutral":neutral,"clipboardUsed":false,"returnEvents":0,"emittedFrames":emittedFrames]
    print(String(decoding:try JSONSerialization.data(withJSONObject:report,options:[.sortedKeys]),as:UTF8.self))
    if !passed { exit(2) }; return
   }
   if mode == "post-paste-space" {
    let payload="первая\nвторая\tстрока"
    let before=try snapshot()
    try require(before["text"] as? String == payload && before["location"] as? Int == payload.utf16.count && before["length"] as? Int == 0,"not_own_paste_result")
    let modifierKeys:[CGKeyCode]=[55,54,56,60,58,61,59,62,57,63]
    func neutral() -> Bool {
     CGEventSource.flagsState(.combinedSessionState).intersection([.maskShift,.maskControl,.maskAlternate,.maskCommand,.maskAlphaShift,.maskSecondaryFn]).isEmpty &&
      modifierKeys.allSatisfy { !CGEventSource.keyState(.hidSystemState,key:$0) && !CGEventSource.keyState(.combinedSessionState,key:$0) }
    }
    try require(neutral(),"active_modifiers")
    let source=CGEventSource(stateID:.hidSystemState)!
    for down in [true,false] {
     try authenticated();try require(neutral(),"modifiers_changed")
     let event=CGEvent(keyboardEventSource:source,virtualKey:49,keyDown:down)!
     event.flags=[];event.post(tap:.cghidEventTap);pause(0.025)
    }
    pause(0.5)
    let after=try snapshot(),expected=payload+" "
    let passed=after["text"] as? String == expected && after["location"] as? Int == expected.utf16.count && after["length"] as? Int == 0 && neutral()
    let report:[String:Any]=["mode":mode,"before":before,"after":after,"expected":expected,"passed":passed,"finalModifiersNeutral":neutral(),"fixtureURL":fixtureURL]
    print(String(decoding:try JSONSerialization.data(withJSONObject:report,options:[.sortedKeys]),as:UTF8.self));if !passed {exit(2)};return
   }
   if mode == "cleanup-modifiers" {
    let keys: [CGKeyCode] = [55,54,56,60,58,61,59,62]
    try require(keys.allSatisfy { !CGEventSource.keyState(.hidSystemState,key:$0) },"physical_modifier_pressed")
    let flags=CGEventSource.flagsState(.combinedSessionState)
    try require(flags.intersection([.maskShift,.maskControl,.maskAlternate,.maskCommand]) == [.maskShift,.maskCommand],"not_test_paste_modifier_frame")
    let original=InputSources.identifier
    defer { _ = InputSources.restore(identifier:original) }
    let source=CGEventSource(stateID:.privateState)!
    for key: CGKeyCode in [56,55] {
     try authenticated()
     try require(keys.allSatisfy { !CGEventSource.keyState(.hidSystemState,key:$0) },"physical_modifier_pressed")
     let event=CGEvent(keyboardEventSource:source,virtualKey:key,keyDown:false)!
     event.type = .flagsChanged; event.flags=[];event.post(tap:.cghidEventTap);pause(0.025)
    }
    pause(0.3)
    let neutral=CGEventSource.flagsState(.combinedSessionState).intersection([.maskShift,.maskControl,.maskAlternate,.maskCommand]).isEmpty
    let report:[String:Any] = ["mode":mode,"neutral":neutral,"after":try snapshot(),"fixtureURL":fixtureURL]
    print(String(decoding:try JSONSerialization.data(withJSONObject:report,options:[.sortedKeys]),as:UTF8.self));if !neutral {exit(2)};return
   }
   if mode.hasPrefix("type-") || mode == "clear" {
    func ordinaryGuarded() throws {
     try authenticated()
     let mask: UInt64 = CGEventFlags([.maskShift,.maskControl,.maskAlternate,.maskCommand,.maskAlphaShift,.maskSecondaryFn,.maskHelp]).rawValue | 0x20ff
     let keys: [CGKeyCode] = [54,55,56,60,58,61,59,62,57,63]
     try require([CGEventSourceStateID.hidSystemState,.combinedSessionState].allSatisfy { state in
      CGEventSource.flagsState(state).rawValue & mask == 0 && keys.allSatisfy { !CGEventSource.keyState(state,key:$0) }
     },"ordinary_foreign_modifier")
    }
    try ordinaryGuarded()
    let setup=try snapshot()
    if let text=setup["text"] as? String, !text.isEmpty && text != "\n" {
     try require(["ghbdtn ","ghbdtn  ","привет  ","hello  ","ещё  ","еще  ","превет  ","первая\nвторая\tстрока","первая\nвторая\tстрока ",String(repeating:"привет ",count:20)+" "].contains(text),"typing_requires_synthetic_fixture")
     try ordinaryGuarded();var all=CFRange(location:0,length:text.utf16.count)
     try require(AXUIElementSetAttributeValue(field,kAXSelectedTextRangeAttribute as CFString,AXValueCreate(.cfRange,&all)!) == .success,"clear_selection_failed")
     pause(0.05)
     let selected=try snapshot();try require(selected["location"] as? Int == 0 && selected["length"] as? Int == text.utf16.count,"clear_selection_not_verified")
     let clearSource=CGEventSource(stateID:.privateState)!
     for down in [true,false] {
      try ordinaryGuarded();let event=CGEvent(keyboardEventSource:clearSource,virtualKey:51,keyDown:down)!
      event.flags=[];event.postToPid(app.processIdentifier);pause(0.025)
     }
     pause(0.1)
    }
    let initial=try snapshot();try require(["", "\n"].contains(initial["text"] as? String ?? "missing"), "typing_requires_empty_fixture")
    if mode == "clear" {
     print(String(decoding:try JSONSerialization.data(withJSONObject:["mode":mode,"after":initial,"fixtureURL":fixtureURL],options:[.sortedKeys]),as:UTF8.self));return
    }
    try ordinaryGuarded()
    let original=InputSources.identifier
    defer { _ = InputSources.restore(identifier:original) }
    try require(InputSources.select(["type-yo","type-typo"].contains(mode) ? .russian : .english),"requested_source_unavailable")
    let selectedSource=InputSources.identifier
    pause(0.2)
    let typingSource=InputSources.identifier
    var emitted:[[String:Any]]=[]
    let wordKeys: [CGKeyCode]
    switch mode {
    case "type-correct":wordKeys=[4,14,37,37,31,49]
    case "type-yo":wordKeys=[17,31,17,49]
    case "type-typo":wordKeys=[5,4,17,2,17,45,49]
    default:wordKeys=[5,4,11,2,17,45,49]
    }
    let keys = Array(repeating:wordKeys,count:mode=="type-stream" ? 20 : 1).flatMap { $0 }
    let source=CGEventSource(stateID:CommandLine.arguments.contains("--hid-source") ? .hidSystemState : .privateState)!
    var beforeFirstSpace: [String:Any]?
    for key in keys {
     if key == 49 && beforeFirstSpace == nil { beforeFirstSpace = try snapshot() }
     for down in [true,false] {
      try ordinaryGuarded()
      let event=CGEvent(keyboardEventSource:source,virtualKey:key,keyDown:down)!
      if down {
       var n=0;var chars=[UniChar](repeating:0,count:16)
       event.keyboardGetUnicodeString(maxStringLength:16,actualStringLength:&n,unicodeString:&chars)
       emitted.append(["keyCode":Int(key),"eventSourceState":event.getIntegerValueField(.eventSourceStateID),"source":InputSources.identifier,"unicode":String(decoding:chars.prefix(n),as:UTF16.self)])
      }
      event.flags=[];event.post(tap:.cghidEventTap);pause(0.025)
     }
    }
    pause(0.6)
    let first=try snapshot()
    for down in [true,false] {
     try ordinaryGuarded();let event=CGEvent(keyboardEventSource:source,virtualKey:49,keyDown:down)!
     event.flags=[];event.post(tap:.cghidEventTap);pause(0.025)
    }
    pause(0.5)
    let after=try snapshot()
    let expected=["type-yo":"ещё  ","type-typo":"привет  "][mode] ?? (mode=="type-stream" ? String(repeating:"привет ",count:20)+" " : (mode=="type-excluded" ? "ghbdtn  " : (mode=="type-wrong" ? "привет  " : "hello  ")))
    let passed=(after["text"] as? String)==expected && (after["length"] as? Int)==0 && (after["location"] as? Int)==expected.utf16.count
    let report:[String:Any] = ["mode":mode,"field":attr(field,kAXDescriptionAttribute) as? String ?? "", "before":initial,"selectedSource":selectedSource,"typingSource":typingSource,"emitted":emitted,"beforeFirstSpace":beforeFirstSpace ?? [:],"afterFirstSpace":first,"after":after,"expected":expected,"passed":passed,"fixtureURL":fixtureURL]
    print(String(decoding:try JSONSerialization.data(withJSONObject:report,options:[.sortedKeys]),as:UTF8.self))
    if !passed {exit(2)}
    return
   }
   if mode != "read" {
    let initial=try snapshot();try require(initial["text"] as? String == "ghbdtn ","unexpected_fixture_text")
    try authenticated();var caret=CFRange(location:7,length:0)
    let cv=AXValueCreate(.cfRange,&caret)!
    try require(AXUIElementSetAttributeValue(field,kAXSelectedTextRangeAttribute as CFString,cv) == .success,"setup_caret_failed")
    pause(0.03)
   }
   let before=try snapshot();var report:[String:Any] = ["mode":mode,"before":before,"fixtureURL":fixtureURL]
   if mode != "read" {
    try require(before["text"] as? String == "ghbdtn ","unexpected_fixture_text")
    if mode.hasPrefix("production") {
     guard let actual=AccessibilityEditor.snapshot() else { throw Failure(reason:"production_snapshot_unavailable") }
     let writer: ((String,pid_t)->Bool)? = mode=="production-noop" ? { _,_ in true } : nil
     let finished=DispatchSemaphore(value:0)
     var resultName="not_started"
     DispatchQueue(label:"fixture.production-accessibility").async {
      let result=AccessibilityEditor.replace(actual,range:NSRange(location:0,length:6),replacement:"привет",
        testKeyboardInsertion:writer,isCurrent:{ DispatchQueue.main.sync { (try? authenticated()) != nil } })
      switch result {case .verified:resultName="verified";case .notApplied:resultName="notApplied";case .uncertain:resultName="uncertain"}
      finished.signal()
     }
     while finished.wait(timeout:.now()) == .timedOut { pause(0.005) }
     report["result"]=resultName
     report["after"]=try snapshot()
     print(String(decoding:try JSONSerialization.data(withJSONObject:report,options:[.sortedKeys]),as:UTF8.self));return
    }
    try authenticated();var r=CFRange(location:0,length:6);let v=AXValueCreate(.cfRange,&r)!
    report["selectionStatus"]=AXUIElementSetAttributeValue(field,kAXSelectedTextRangeAttribute as CFString,v).rawValue
    report["selected"]=try snapshot()
    try require((attr(field,kAXSelectedTextAttribute) as? String)=="ghbdtn","selected_text_not_verified")
    try authenticated()
    if mode=="old" {
     report["writeStatus"]=AXUIElementSetAttributeValue(field,kAXSelectedTextAttribute as CFString,"привет" as CFString).rawValue
    } else {
     let source=CGEventSource(stateID:.privateState)!
     for down in [true,false] {
      try authenticated()
      let e=CGEvent(keyboardEventSource:source,virtualKey:0,keyDown:down)!
      let chars=Array("привет".utf16);chars.withUnsafeBufferPointer { e.keyboardSetUnicodeString(stringLength:$0.count,unicodeString:$0.baseAddress!) }
      e.setIntegerValueField(.eventSourceUserData,value:0x4c50544c)
      e.postToPid(app.processIdentifier);pause(0.02)
     }
    }
    pause(0.25);report["after"]=try snapshot()
   }
   print(String(decoding:try JSONSerialization.data(withJSONObject:report,options:[.sortedKeys]),as:UTF8.self))
  } catch {
   var report: [String:Any] = ["error":(error as? Failure)?.reason ?? String(describing:error),"notice":"Stopped; no automatic retry or wider field access.","axErrors":axErrors]
   if let failureDiagnostics { report["manualReadonlyState"] = failureDiagnostics() }
   print(String(decoding:try! JSONSerialization.data(withJSONObject:report,options:[.sortedKeys]),as:UTF8.self));exit(1)
  }
 }
}
