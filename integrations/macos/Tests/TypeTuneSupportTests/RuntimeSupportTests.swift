import Foundation
import Testing
@testable import TypeTuneSupport

struct RuntimeSupportTests {
    @Test func beforeEditRejectRestoresOriginalLayout() {
        var selected: [String] = []
        let result=LayoutRestore.after("rejected",original:"us") { mode in
            selected.append(mode);return true
        }
        #expect(result == "rejected")
        #expect(selected == ["us"])
        selected=[]
        #expect(LayoutRestore.after("verified",original:"us") { mode in selected.append(mode);return true } == "verified")
        #expect(selected.isEmpty)
        #expect(LayoutRestore.after("indeterminate",original:"ru") { _ in fatalError("must not restore after an edit started") } == "indeterminate")
    }

    @Test func editAckUsesSourceElapsedAndDoesNotClaimResetAsVerified() {
        #expect(EditAcknowledgement.resultTime(sourceMs:100,elapsedMs:2500) == 2600)
        #expect(EditAcknowledgement.visibleOutcome(native:"verified",engine:"verified") == "verified")
        #expect(EditAcknowledgement.visibleOutcome(native:"verified",engine:"reset") == "reset")
        #expect(EditAcknowledgement.visibleOutcome(native:"submitted",engine:"stale") == "reset")
        #expect(EditAcknowledgement.visibleOutcome(native:"rejected",engine:"reset") == "reset")
    }

    @Test func loginItemRollbackTargetsPreviousEffectiveState() {
        #expect(LoginItemIntent.rollbackTarget(desired:true,previous:false) == false)
        #expect(LoginItemIntent.rollbackTarget(desired:false,previous:true) == true)
        #expect(LoginItemIntent.rollbackTarget(desired:true,previous:true) == nil)
    }
}
