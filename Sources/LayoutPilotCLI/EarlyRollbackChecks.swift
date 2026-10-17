import Foundation
import LayoutPilotCore

func earlyRollbackChecks() -> [(Bool, String)] {
    var checks: [(Bool,String)] = []
    func check(_ result: Bool, _ name: String) { checks.append((result,"partial rollback: " + name)) }
    let decision = Decision(original: "ghb", replacement: "при", reason: .layout, targetLanguage: .russian)
    func plan(partial: Bool = true, pending: Bool = true, after: String = "say при",
              caret: NSRange = NSRange(location: 7,length: 0), original: Decision? = nil) -> PartialMutationRollbackPlan? {
        PartialMutationRollbackPlan(isPartial: partial, hasQueuedEditingInput: pending,
            beforeText:"say ghb",beforeSelection:NSRange(location:7,length:0),replacementRange:NSRange(location:4,length:3),
            decision:original ?? decision,afterText:after,afterSelection:caret)
    }
    check(plan()?.edit.expectedText == "say ghb" && plan()?.edit.cursor == 7,
          "pending editing suffix restores the whole pre-correction text and caret")
    check(plan(pending:false) == nil, "release-only queue does not request rollback")
    check(plan(partial:false) == nil, "completed-word correction is not rolled back by this policy")
    check(plan(after:"say приx") == nil, "unexpected text cannot authorize inverse write")
    check(plan(caret:NSRange(location:6,length:0)) == nil, "changed caret cannot authorize inverse write")
    check(plan(caret:NSRange(location:4,length:3)) == nil, "changed selection cannot authorize inverse write")
    check(plan(original:Decision(original:"other",replacement:"при",reason:.layout,targetLanguage:.russian)) == nil,
          "unrelated original token cannot be restored")
    let nfdBefore = "e\u{301} ghb", nfdAfter = "e\u{301} при"
    let nfd = PartialMutationRollbackPlan(isPartial:true,hasQueuedEditingInput:true,beforeText:nfdBefore,
        beforeSelection:NSRange(location:6,length:0),replacementRange:NSRange(location:3,length:3),
        decision:decision,afterText:nfdAfter,afterSelection:NSRange(location:6,length:0))
    check(nfd?.edit.expectedText.utf16.elementsEqual(nfdBefore.utf16) == true,
          "inverse preserves unrelated decomposed Unicode exactly")
    check(PartialMutationRollbackPlan(isPartial:true,hasQueuedEditingInput:true,beforeText:"say ghb tail",
        beforeSelection:NSRange(location:8,length:0),replacementRange:NSRange(location:4,length:3),
        decision:decision,afterText:"say при tail",afterSelection:NSRange(location:7,length:0)) == nil,
          "only a token ending at the original caret permits the inverse")
    check(PartialMutationRollbackPlan(isPartial:true,hasQueuedEditingInput:true,beforeText:"😀ghb",
        beforeSelection:NSRange(location:5,length:0),replacementRange:NSRange(location:1,length:4),
        decision:decision,afterText:"при",afterSelection:NSRange(location:3,length:0)) == nil,
          "a range splitting a surrogate cannot authorize rollback")
    return checks
}
