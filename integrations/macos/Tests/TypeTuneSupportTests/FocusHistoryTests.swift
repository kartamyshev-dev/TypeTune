import Testing
@testable import TypeTuneSupport

struct FocusHistoryTests {
    @Test func unknownFieldDoesNotHideARealMove() {
        var state = FocusHistory()
        let changes = ["10:100", "10:0", "10:100", "10:0", "10:200", "11:0", "11:0"].map { state.observe($0) }
        #expect(changes == [true, true, true, true, true, true, false])
    }
}
